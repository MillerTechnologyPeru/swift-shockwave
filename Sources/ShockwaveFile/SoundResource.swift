import Foundation

/// A sound cast member's samples, decoded from the Macintosh `snd `
/// resource Director stores its sounds as (the member's `snd ` child chunk
/// in the key table).
///
/// The resource is a format-1 or format-2 `snd ` header, then a sound
/// command list, then a sound header addressed by the command's `param2`
/// offset. Only uncompressed PCM is decoded — the standard header (8-bit
/// mono), the extended header (`encode 0xFF`: 8/16-bit, mono/stereo) and
/// the compressed header (`encode 0xFE`) only when its compression id says
/// "not compressed". Samples come out as native-endian signed 16-bit
/// interleaved frames whatever the source depth, so playback needs one
/// format. Compressed sounds (MACE, IMA4, µ-law) aren't handled and decode
/// to `nil`.
public struct SoundResource: Equatable, Sendable {
  public var sampleRate: Int
  public var channels: Int
  /// Signed 16-bit native-endian interleaved samples.
  public var samples: [Int16]

  public var frameCount: Int { channels > 0 ? samples.count / channels : 0 }
  /// Playing time in milliseconds — what Lingo's `member.duration` reports.
  public var durationMilliseconds: Int {
    sampleRate > 0 ? frameCount * 1000 / sampleRate : 0
  }

  public init(sampleRate: Int, channels: Int, samples: [Int16]) {
    self.sampleRate = sampleRate
    self.channels = channels
    self.samples = samples
  }

  /// Where a `snd ` resource's samples begin and how they are shaped.
  /// Split out so a resource whose "samples" are really a compressed
  /// stream (a burned movie's Shockwave Audio) can be recognized without
  /// decoding it as PCM.
  public struct Layout: Equatable, Sendable {
    public var sampleRate: Int
    public var channels: Int
    public var bitsPerSample: Int
    public var frameCount: Int
    /// Offset of the first sample byte within the resource.
    public var dataOffset: Int
  }

  public static func layout(ofSndResource data: Data) -> Layout? {
    let bytes = [UInt8](data)
    func u16(_ offset: Int) -> Int? {
      offset + 2 <= bytes.count ? Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) : nil
    }
    func u32(_ offset: Int) -> Int? {
      guard offset + 4 <= bytes.count else { return nil }
      return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8
        | Int(bytes[offset + 3])
    }
    guard let format = u16(0) else { return nil }
    // Format 1: modifier count, (id, init) pairs, then the command count.
    // Format 2: a reference count, then the command count.
    var offset: Int
    switch format {
    case 1:
      guard let modifiers = u16(2) else { return nil }
      offset = 4 + modifiers * 6
    case 2:
      offset = 4
    default:
      return nil
    }
    guard let commandCount = u16(offset) else { return nil }
    offset += 2
    // Find the sound command carrying the header offset: bufferCmd (0x51)
    // or soundCmd (0x50), with the "param2 is an offset" bit set.
    var headerOffset: Int?
    for _ in 0..<commandCount {
      guard let command = u16(offset), let param2 = u32(offset + 4) else { return nil }
      if command & 0x7FFF == 0x51 || command & 0x7FFF == 0x50 {
        headerOffset = param2
        break
      }
      offset += 8
    }
    guard let header = headerOffset, header + 22 <= bytes.count else { return nil }

    // Common prefix: samplePtr, length-or-channels, sampleRate (16.16),
    // loopStart, loopEnd, encode, baseFrequency.
    guard let lengthOrChannels = u32(header + 4), let rateFixed = u32(header + 8) else {
      return nil
    }
    let encode = bytes[header + 20]
    let sampleRate = rateFixed >> 16
    let dataStart: Int
    let frames: Int
    let bits: Int
    let channels: Int
    switch encode {
    case 0x00:
      // Standard header: 8-bit mono, `length` bytes of data right after.
      channels = 1
      frames = lengthOrChannels
      bits = 8
      dataStart = header + 22
    case 0xFF, 0xFE:
      // Extended / compressed header: numChannels, then numFrames,
      // AIFFSampleRate (80-bit), markerChunk, ...
      channels = lengthOrChannels
      guard let numFrames = u32(header + 22) else { return nil }
      frames = numFrames
      if encode == 0xFF {
        // instrumentChunks(4) AESRecording(4) sampleSize(2) futureUse(14)
        guard let sampleSize = u16(header + 48) else { return nil }
        bits = sampleSize
        dataStart = header + 64
      } else {
        // format(4) futureUse2(4) stateVars(4) leftOverSamples(4)
        // compressionID(2) packetSize(2) snthID(2) sampleSize(2)
        guard let compressionID = u16(header + 56), compressionID == 0,
          let sampleSize = u16(header + 62)
        else { return nil }
        bits = sampleSize
        dataStart = header + 64
      }
    default:
      return nil
    }
    guard sampleRate > 0, channels > 0, frames >= 0, bits == 8 || bits == 16,
      dataStart <= bytes.count
    else { return nil }
    return Layout(
      sampleRate: sampleRate, channels: channels, bitsPerSample: bits, frameCount: frames,
      dataOffset: dataStart)
  }

  /// Decodes a `snd ` resource's PCM samples. `nil` when the resource
  /// isn't one, or holds something other than plain samples.
  public init?(sndResource data: Data) {
    guard let layout = Self.layout(ofSndResource: data) else { return nil }
    let bytes = [UInt8](data)
    sampleRate = layout.sampleRate
    channels = layout.channels
    let bits = layout.bitsPerSample
    let dataStart = layout.dataOffset
    let sampleCount = min(
      layout.frameCount * layout.channels, (bytes.count - dataStart) / (bits / 8))
    guard sampleCount >= 0 else { return nil }
    var samples = [Int16](repeating: 0, count: sampleCount)
    if bits == 8 {
      // Unsigned 8-bit, silence at 0x80.
      for index in 0..<sampleCount {
        samples[index] = Int16(Int(bytes[dataStart + index]) - 128) << 8
      }
    } else {
      // Big-endian signed 16-bit.
      for index in 0..<sampleCount {
        let position = dataStart + index * 2
        samples[index] = Int16(bitPattern: UInt16(bytes[position]) << 8 | UInt16(bytes[position + 1]))
      }
    }
    self.samples = samples
  }
}
