import BinaryParsing
import Foundation

/// The `VWSC` chunk: the movie's score — the frame/channel timeline plus the
/// behavior intervals attaching scripts to channel spans.
///
/// Always big-endian, independent of the container byte order.
public struct ScoreChunk: Sendable {
  /// One frame's channel state: raw fixed-size channel records, keyed by
  /// channel index, holding only channels that have ever been touched by a
  /// delta up to this frame (score frame data is delta-compressed against
  /// the previous frame). Channels 0..<6 are the special channels (frame
  /// script, tempo, transition, sounds, palette); sprite channel `n` is
  /// record `n + 5`.
  ///
  /// Records stay raw: field layout inside the sprite record varies by
  /// format version and isn't decoded until it can be validated against a
  /// movie that actually populates score sprites.
  public struct Frame: Sendable {
    public var channels: [Int: [UInt8]]

    public init(channels: [Int: [UInt8]]) {
      self.channels = channels
    }
  }

  /// A behavior attachment: `(castLib, member)` of a script cast member.
  /// `castLib` uses the file-internal library numbering
  /// (`CastListEntry.resourceId >> 16`).
  public struct BehaviorReference: Equatable, Sendable {
    public var castLib: Int
    public var member: Int

    public init(castLib: Int, member: Int) {
      self.castLib = castLib
      self.member = member
    }
  }

  /// One channel's span of frames and the behaviors scripted onto it.
  /// Channel numbering matches `Frame.channels`: 0 is the frame-script
  /// channel, sprites start at 6.
  public struct BehaviorInterval: Equatable, Sendable {
    public var startFrame: Int
    public var endFrame: Int
    public var channel: Int
    public var behaviors: [BehaviorReference]

    public init(startFrame: Int, endFrame: Int, channel: Int, behaviors: [BehaviorReference]) {
      self.startFrame = startFrame
      self.endFrame = endFrame
      self.channel = channel
      self.behaviors = behaviors
    }
  }

  public var version: Int
  public var channelRecordSize: Int
  public var channelCount: Int
  public var displayedChannelCount: Int
  public var frames: [Frame]
  public var behaviorIntervals: [BehaviorInterval]

  public init(
    version: Int,
    channelRecordSize: Int,
    channelCount: Int,
    displayedChannelCount: Int,
    frames: [Frame],
    behaviorIntervals: [BehaviorInterval]
  ) {
    self.version = version
    self.channelRecordSize = channelRecordSize
    self.channelCount = channelCount
    self.displayedChannelCount = displayedChannelCount
    self.frames = frames
    self.behaviorIntervals = behaviorIntervals
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    // Outer shell: an offset table of variable-size entries. Entry 0 is the
    // frame data; entry 1 indexes the behavior-interval descriptors, each of
    // which is a (primary, secondary, tertiary) triple of consecutive
    // entries.
    let totalLength = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    let _ = try Int32(parsingBigEndian: &input)  // header type marker (-3)
    let _ = try UInt32(parsingBigEndian: &input)  // offset to entry count
    let entryCount = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    let _ = try UInt32(parsingBigEndian: &input)  // entryCount + 1
    let entriesLength = try Int(parsing: &input, storedAsBigEndian: UInt32.self)

    var offsets: [Int] = []
    offsets.reserveCapacity(entryCount + 1)
    for _ in 0...entryCount {
      offsets.append(try Int(parsing: &input, storedAsBigEndian: UInt32.self))
    }
    guard offsets.last == entriesLength, 24 + (entryCount + 1) * 4 + entriesLength == totalLength
    else {
      throw ShockwaveFileError.invalidOffset(entriesLength)
    }
    let entriesData = try [UInt8](parsing: &input, byteCount: entriesLength)
    func entry(_ k: Int) throws -> ArraySlice<UInt8> {
      guard k >= 0, k < entryCount, offsets[k] <= offsets[k + 1] else {
        throw ShockwaveFileError.invalidOffset(k)
      }
      return entriesData[offsets[k]..<offsets[k + 1]]
    }

    let framesData = try entry(0)
    (version, channelRecordSize, channelCount, displayedChannelCount, frames) =
      try Self.readFrames([UInt8](framesData))

    var intervals: [BehaviorInterval] = []
    if entryCount > 1 {
      let index = [UInt8](try entry(1))
      let indexCount = index.count >= 4 ? Int(readU32(index, 0)) : 0
      intervals.reserveCapacity(indexCount)
      for i in 0..<indexCount {
        let primaryEntry = Int(readU32(index, 4 + i * 4))
        let primary = [UInt8](try entry(primaryEntry))
        guard primary.count >= 20 else {
          throw ShockwaveFileError.invalidOffset(primaryEntry)
        }
        let secondary = [UInt8](try entry(primaryEntry + 1))
        var behaviors: [BehaviorReference] = []
        behaviors.reserveCapacity(secondary.count / 8)
        for j in stride(from: 0, to: secondary.count - 7, by: 8) {
          behaviors.append(
            BehaviorReference(
              castLib: Int(readU16(secondary, j)), member: Int(readU16(secondary, j + 2))))
        }
        intervals.append(
          BehaviorInterval(
            startFrame: Int(readU32(primary, 0)),
            endFrame: Int(readU32(primary, 4)),
            channel: Int(readU32(primary, 16)),
            behaviors: behaviors
          ))
      }
    }
    behaviorIntervals = intervals
  }

  /// Decodes the delta-compressed frame data: each frame is a length-prefixed
  /// list of `(length, offset, bytes)` patches against a persistent
  /// channel-record buffer carried over from the previous frame.
  private static func readFrames(
    _ data: [UInt8]
  ) throws -> (
    version: Int, recordSize: Int, channels: Int, displayed: Int, frames: [Frame]
  ) {
    guard data.count >= 20 else { throw ShockwaveFileError.invalidOffset(0) }
    let actualLength = Int(readU32(data, 0))
    let headerSize = Int(readU32(data, 4))
    let frameCount = Int(readU32(data, 8))
    let version = Int(readU16(data, 12))
    let recordSize = Int(readU16(data, 14))
    let channels = Int(readU16(data, 16))
    let displayed = Int(readU16(data, 18))
    guard actualLength == data.count, headerSize >= 20, recordSize > 0 else {
      throw ShockwaveFileError.invalidOffset(actualLength)
    }

    var buffer = [UInt8](repeating: 0, count: channels * recordSize)
    var touched: Set<Int> = []
    var frames: [Frame] = []
    frames.reserveCapacity(frameCount)
    var position = headerSize
    for _ in 0..<frameCount {
      guard position + 2 <= data.count else { throw ShockwaveFileError.invalidOffset(position) }
      let frameLength = Int(readU16(data, position))
      let frameEnd = position + frameLength
      guard frameLength >= 2, frameEnd <= data.count else {
        throw ShockwaveFileError.invalidOffset(position)
      }
      position += 2
      while position < frameEnd {
        guard position + 4 <= frameEnd else { throw ShockwaveFileError.invalidOffset(position) }
        let patchLength = Int(readU16(data, position))
        let patchOffset = Int(readU16(data, position + 2))
        position += 4
        guard position + patchLength <= frameEnd, patchOffset + patchLength <= buffer.count
        else {
          throw ShockwaveFileError.invalidOffset(position)
        }
        buffer.replaceSubrange(
          patchOffset..<(patchOffset + patchLength), with: data[position..<(position + patchLength)]
        )
        position += patchLength
        for channel
          in (patchOffset / recordSize)...((patchOffset + max(patchLength, 1) - 1) / recordSize)
        {
          touched.insert(channel)
        }
      }
      var channelsSnapshot: [Int: [UInt8]] = [:]
      channelsSnapshot.reserveCapacity(touched.count)
      for channel in touched {
        channelsSnapshot[channel] = Array(
          buffer[(channel * recordSize)..<((channel + 1) * recordSize)])
      }
      frames.append(Frame(channels: channelsSnapshot))
    }
    return (version, recordSize, channels, displayed, frames)
  }
}

private func readU16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
  UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
}

private func readU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
  UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
    | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
}

private func readU16(_ bytes: ArraySlice<UInt8>, _ offset: Int) -> UInt16 {
  let base = bytes.startIndex + offset
  return UInt16(bytes[base]) << 8 | UInt16(bytes[base + 1])
}

private func readU32(_ bytes: ArraySlice<UInt8>, _ offset: Int) -> UInt32 {
  let base = bytes.startIndex + offset
  return UInt32(bytes[base]) << 24 | UInt32(bytes[base + 1]) << 16
    | UInt32(bytes[base + 2]) << 8 | UInt32(bytes[base + 3])
}
