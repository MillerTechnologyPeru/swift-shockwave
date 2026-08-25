import CSDL3
import Foundation
import ShockwaveFile
import ShockwavePlayer

/// Plays the player's sound channels through SDL3 audio: one SDL audio
/// stream per Director channel, all bound to the default playback device,
/// which mixes them. Each play replaces the channel's stream so a new
/// sound cuts off the old one, the way `puppetSound` does; SDL converts
/// from the sound's own rate/channel count to the device's.
@MainActor
final class SDLAudioSink: AudioSink {
  private let device: SDL_AudioDeviceID
  private var streams: [Int: OpaquePointer] = [:]
  /// Per-channel gains as set by play, so unmuting restores them.
  private var gains: [Int: Float] = [:]
  private var isMuted = false

  /// `nil` when no playback device could be opened (no audio hardware,
  /// or the audio subsystem isn't up) — the player then runs silent.
  init?() {
    let device = SDL_OpenAudioDevice(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, nil)
    guard device != 0 else { return nil }
    self.device = device
    SDL_ResumeAudioDevice(device)
  }

  /// Tears the streams and device down; the command calls this before
  /// `SDL.quit()`.
  func close() {
    for stream in streams.values { SDL_DestroyAudioStream(stream) }
    streams.removeAll()
    SDL_CloseAudioDevice(device)
  }

  func play(_ sound: SoundResource, onChannel channel: Int, volume: Int, pan: Int) {
    if ProcessInfo.processInfo.environment["SHOCKWAVE_AUDIO_LOG"] != nil {
      print("audio: channel \(channel) \(sound.frameCount) frames @\(sound.sampleRate)Hz x\(sound.channels) vol \(volume)")
    }
    stop(channel: channel)
    var source = SDL_AudioSpec(
      format: SDL_AUDIO_S16, channels: Int32(sound.channels), freq: Int32(sound.sampleRate))
    guard let stream = SDL_CreateAudioStream(&source, nil) else { return }
    guard SDL_BindAudioStream(device, stream) else {
      SDL_DestroyAudioStream(stream)
      return
    }
    let gain = Float(max(0, min(255, volume))) / 255
    gains[channel] = gain
    SDL_SetAudioStreamGain(stream, isMuted ? 0 : gain)
    sound.samples.withUnsafeBytes { buffer in
      _ = SDL_PutAudioStreamData(stream, buffer.baseAddress, Int32(buffer.count))
    }
    SDL_FlushAudioStream(stream)
    streams[channel] = stream
  }

  func setMuted(_ muted: Bool) {
    isMuted = muted
    for (channel, stream) in streams {
      SDL_SetAudioStreamGain(stream, muted ? 0 : gains[channel] ?? 1)
    }
  }

  func stop(channel: Int) {
    guard let stream = streams.removeValue(forKey: channel) else { return }
    SDL_UnbindAudioStream(stream)
    SDL_DestroyAudioStream(stream)
  }

  func isBusy(channel: Int) -> Bool {
    guard let stream = streams[channel] else { return false }
    return SDL_GetAudioStreamQueued(stream) > 0 || SDL_GetAudioStreamAvailable(stream) > 0
  }
}
