import LingoRuntime
import ShockwaveFile
import ShockwaveModel

/// Where decoded sound actually gets played. The player owns the Lingo
/// side of sound — channels, playlists, `puppetSound`, `soundBusy` — and
/// hands finished decisions ("play this on channel 3 at this volume") to
/// whatever audio backend is installed; without one the movie runs silent
/// and every channel reports idle.
public protocol AudioSink: AnyObject {
  /// Starts `sound` on `channel`, replacing whatever it was playing.
  /// `volume` is Lingo's 0–255, `pan` −100…100.
  func play(_ sound: SoundResource, onChannel channel: Int, volume: Int, pan: Int)
  func stop(channel: Int)
  /// Whether `channel` still has sound to play.
  func isBusy(channel: Int) -> Bool
  /// Silences (or restores) everything at the output without touching
  /// channel state — `the soundEnabled`. Sounds keep running underneath,
  /// so unmuting mid-sound picks up where it would have been.
  func setMuted(_ muted: Bool)
}

extension AudioSink {
  public func setMuted(_ muted: Bool) {}
}

/// One of Director's eight sound channels as Lingo sees it — `sound(n)`.
///
/// A channel plays one sound at a time from a playlist: `setPlayList` /
/// `queue` fill it, `play` starts it, and the player advances it as each
/// entry finishes. `puppetSound` bypasses the list and plays a member at
/// once. The sample's music code keeps channel 1 topped up from a text
/// playlist member and fires effects on whichever of channels 3–8 is idle.
public final class SoundChannel: LingoObject {
  public let number: Int
  private unowned let player: MoviePlayer
  /// Entries are Lingo property lists (`[#member: m, #startTime: 0, ...]`).
  private(set) var playlist: [LingoValue] = []
  private var properties: [String: LingoValue] = ["volume": .integer(255), "pan": .integer(0)]
  /// Set by `play()`; cleared by `stop()`. While on, the player feeds the
  /// next playlist entry whenever the channel falls idle.
  private(set) var isPlaying = false
  /// Whether `puppetSound` has taken this channel over — while on, the
  /// score's own sound channel is ignored, exactly like a puppeted sprite
  /// channel; `puppetSound(n, 0)` gives it back.
  var isPuppeted = false

  init(number: Int, player: MoviePlayer) {
    self.number = number
    self.player = player
    super.init(environment: player.movieModel.lingoEnvironment)
  }

  public var volume: Int { properties["volume"]?.asInteger() ?? 255 }
  public var pan: Int { properties["pan"]?.asInteger() ?? 0 }

  public var isBusy: Bool {
    player.audioSink?.isBusy(channel: number) ?? false
  }

  /// Plays `member` now, dropping whatever was playing.
  func play(member: CastMember) {
    guard let sound = player.decodedSound(of: member) else { return }
    properties["member"] = .object(member)
    player.audioSink?.play(sound, onChannel: number, volume: volume, pan: pan)
  }

  func stop() {
    isPlaying = false
    player.audioSink?.stop(channel: number)
  }

  /// Advances the playlist if the channel is idle and playing.
  func service() {
    guard isPlaying, !isBusy else { return }
    guard !playlist.isEmpty else {
      isPlaying = false
      return
    }
    let entry = playlist.removeFirst()
    if let member = resolveMember(entry.listGetAProp(.symbol("member"))) {
      play(member: member)
    }
  }

  private func resolveMember(_ value: LingoValue) -> CastMember? {
    if case .object(let object) = value { return object as? CastMember }
    return player.member(value, castLib: nil) as? CastMember
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "channelcount": return .integer(1)
    case "status": return .integer(isBusy ? 3 : 0)
    default: return properties[name.asciiLowercased()] ?? super.getProperty(name)
    }
  }

  public override func setProperty(_ name: String, value: LingoValue) {
    properties[name.asciiLowercased()] = value
  }

  public override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
    switch name.asciiLowercased() {
    case "play":
      // `play()` starts the playlist; `play(member)` plays that member.
      if let first = args.first, let member = resolveMember(first) {
        playlist.removeAll()
        isPlaying = true
        play(member: member)
      } else {
        isPlaying = true
        service()
      }
    case "stop":
      stop()
    case "pause":
      player.audioSink?.stop(channel: number)
    case "playnext":
      player.audioSink?.stop(channel: number)
      isPlaying = true
      service()
    case "setplaylist":
      playlist = args.first?.asSequence().filter { $0.isList } ?? []
    case "getplaylist":
      return .list(playlist)
    case "queue":
      if let entry = args.first, entry.isList { playlist.append(entry) }
    case "isbusy":
      return .integer(isBusy ? 1 : 0)
    default:
      return super.callMethod(name, args: args)
    }
    return .void
  }
}

/// The score's two sound channels. Director plays whatever member is
/// authored into them as the playhead moves: a new member starts when it
/// first appears, sustains across the frames it spans rather than
/// retriggering, and plays out even after its span ends. A channel
/// `puppetSound` has taken over is the script's until given back.
extension MoviePlayer {
  func serviceScoreSounds() {
    guard let score = movieModel.score, currentFrame >= 1,
      currentFrame <= score.chunk.frames.count
    else { return }
    let frame = score.chunk.frames[currentFrame - 1]
    for channelNumber in 1...2 {
      let authored = frame.soundMember(channel: channelNumber)
      let previous = scoreSounds[channelNumber]
      guard authored?.member != previous?.member || authored?.castLib != previous?.castLib
      else { continue }
      if let authored {
        scoreSounds[channelNumber] = authored
      } else {
        scoreSounds.removeValue(forKey: channelNumber)
      }
      guard let authored, !soundChannel(channelNumber).isPuppeted,
        let member = movieModel.castManager.library(scoreCastLib: authored.castLib)?
          .member(authored.member)
      else { continue }
      soundChannel(channelNumber).play(member: member)
    }
  }
}
