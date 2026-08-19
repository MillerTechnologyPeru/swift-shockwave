import Foundation

/// A Shockwave Audio (SWA) sound member's media — the `ediM` chunk a
/// compressed sound member owns: a header, then an MPEG audio (MP3)
/// bitstream. The header opens with its own size, then the sample rate;
/// a 16-byte GUID follows, and the rest is padding up to the declared size.
///
/// The bitstream isn't decoded here — that takes an MP3 decoder, which the
/// playback layer supplies — but its frame headers are walked to answer
/// `duration`, which Lingo reads before playing (the sample queues clips
/// with `#endTime: member.duration`).
public struct ShockwaveAudioMedia: Equatable, Sendable {
  public var sampleRate: Int
  /// The MPEG audio bitstream.
  public var bitstream: Data
  /// Playing time in milliseconds, from the frame headers.
  public var durationMilliseconds: Int

  public init?(ediMData data: Data) {
    let bytes = [UInt8](data)
    func u32(_ offset: Int) -> Int? {
      guard offset + 4 <= bytes.count else { return nil }
      return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8
        | Int(bytes[offset + 3])
    }
    guard let headerSize = u32(0), let rate = u32(8), headerSize >= 24, headerSize <= bytes.count
    else { return nil }
    sampleRate = rate
    bitstream = data.subdata(in: headerSize..<data.count)
    durationMilliseconds = Self.duration(of: bitstream)
    guard durationMilliseconds > 0 else { return nil }
  }

  /// A sound member whose `snd ` resource holds a Shockwave Audio stream
  /// instead of samples — how a burned (`.dcr`) movie stores its sounds:
  /// the Macintosh header survives, but what follows it is MP3.
  ///
  /// `nil` for an ordinary PCM resource: the sample area has to start with
  /// a run of MPEG frames that tiles it, which random samples don't.
  public init?(sndResource data: Data) {
    guard let layout = SoundResource.layout(ofSndResource: data),
      layout.dataOffset < data.count
    else { return nil }
    let stream = data.subdata(in: layout.dataOffset..<data.count)
    let (duration, consumed, frames) = Self.walk(stream)
    // The frames must account for essentially the whole sample area.
    guard frames > 0, duration > 0, consumed * 10 >= stream.count * 9 else { return nil }
    sampleRate = layout.sampleRate
    bitstream = stream
    durationMilliseconds = duration
  }

  /// Total playing time of an MPEG-1/2/2.5 layer I–III bitstream, by
  /// stepping frame to frame. Anything that isn't a frame sync (a stray
  /// tag, padding) is skipped a byte at a time.
  static func duration(of bitstream: Data) -> Int {
    walk(bitstream).duration
  }

  /// Steps frame to frame, reporting the playing time, how many bytes the
  /// frames covered, and how many there were.
  private static func walk(_ bitstream: Data) -> (duration: Int, consumed: Int, frames: Int) {
    let bytes = [UInt8](bitstream)
    let bitrateTable: [[Int]] = [
      // MPEG-1 layer III
      [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
      // MPEG-2/2.5 layer III
      [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
    ]
    let rateTable: [[Int]] = [
      [44100, 48000, 32000, 0],  // MPEG-1
      [22050, 24000, 16000, 0],  // MPEG-2
      [11025, 12000, 8000, 0],  // MPEG-2.5
    ]
    var samples = 0.0
    var consumed = 0
    var frames = 0
    var index = 0
    while index + 4 <= bytes.count {
      guard bytes[index] == 0xFF, bytes[index + 1] & 0xE0 == 0xE0 else {
        index += 1
        continue
      }
      let versionBits = Int(bytes[index + 1] >> 3) & 0x3
      let layerBits = Int(bytes[index + 1] >> 1) & 0x3
      let bitrateIndex = Int(bytes[index + 2] >> 4)
      let rateIndex = Int(bytes[index + 2] >> 2) & 0x3
      let padding = Int(bytes[index + 2] >> 1) & 0x1
      // Only layer III is handled (versionBits 1 is reserved).
      guard layerBits == 1, versionBits != 1, bitrateIndex != 0, bitrateIndex != 15, rateIndex != 3
      else {
        index += 1
        continue
      }
      let isMPEG1 = versionBits == 3
      let rateRow = isMPEG1 ? 0 : (versionBits == 2 ? 1 : 2)
      let bitrate = bitrateTable[isMPEG1 ? 0 : 1][bitrateIndex] * 1000
      let sampleRate = rateTable[rateRow][rateIndex]
      let samplesPerFrame = isMPEG1 ? 1152.0 : 576.0
      let frameLength = Int(samplesPerFrame / 8 * Double(bitrate) / Double(sampleRate)) + padding
      guard frameLength > 4 else {
        index += 1
        continue
      }
      samples += samplesPerFrame * 1000 / Double(sampleRate)
      consumed += frameLength
      frames += 1
      index += frameLength
    }
    return (Int(samples.rounded()), consumed, frames)
  }
}
