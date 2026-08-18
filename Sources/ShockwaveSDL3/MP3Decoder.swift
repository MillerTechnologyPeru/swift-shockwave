import AVFoundation
import Foundation
import ShockwaveFile

/// Decodes a Shockwave Audio member's MP3 bitstream to PCM through
/// AVFoundation — the platform decoder, so no codec ships with the player.
/// The bitstream goes to a temporary file because the framework reads
/// files, not buffers; it's removed once read.
enum MP3Decoder {
  static func decode(_ media: ShockwaveAudioMedia) -> SoundResource? {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("shockwave-\(UUID().uuidString).mp3")
    do {
      try media.bitstream.write(to: url)
    } catch {
      return nil
    }
    defer { try? FileManager.default.removeItem(at: url) }

    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let sourceFormat = file.processingFormat
    let channels = Int(sourceFormat.channelCount)
    let sampleRate = Int(sourceFormat.sampleRate)
    let frames = AVAudioFrameCount(file.length)
    guard channels > 0, sampleRate > 0, frames > 0,
      let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: sourceFormat.sampleRate,
        channels: sourceFormat.channelCount, interleaved: true),
      let buffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frames)
    else { return nil }
    // Reading in the file's own float format then converting keeps this
    // independent of what the decoder hands back.
    guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames),
      (try? file.read(into: floatBuffer)) != nil,
      let converter = AVAudioConverter(from: sourceFormat, to: target)
    else { return nil }
    var error: NSError?
    var consumed = false
    let status = converter.convert(to: buffer, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .endOfStream
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return floatBuffer
    }
    guard status != .error, let data = buffer.int16ChannelData else { return nil }
    let count = Int(buffer.frameLength) * channels
    let samples = Array(UnsafeBufferPointer(start: data[0], count: count))
    return SoundResource(sampleRate: sampleRate, channels: channels, samples: samples)
  }
}
