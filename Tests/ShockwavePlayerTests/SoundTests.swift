import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

/// A sink that remembers what it was told to play, and reports a channel
/// busy for as many `service` rounds as the test says.
private final class RecordingSink: AudioSink {
  var played: [(channel: Int, frames: Int, volume: Int)] = []
  var busyChannels: Set<Int> = []
  func play(_ sound: SoundResource, onChannel channel: Int, volume: Int, pan: Int) {
    played.append((channel, sound.frameCount, volume))
    busyChannels.insert(channel)
  }
  func stop(channel: Int) { busyChannels.remove(channel) }
  func isBusy(channel: Int) -> Bool { busyChannels.contains(channel) }
}

/// The sample's sounds are Macintosh `snd ` resources with extended
/// headers: 16-bit mono PCM at 16 kHz. `blockdrop` is the brick-landing
/// effect the play manager fires; its 2937-byte resource holds 1428 frames,
/// which Lingo sees as an 89 ms `duration`.
@Test func soundMembersDecodeTheirPCM() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let blockdrop = try #require(movie.castManager.member(named: "blockdrop"))
  let sound = try #require(blockdrop.sound)
  #expect(sound.sampleRate == 16000)
  #expect(sound.channels == 1)
  #expect(sound.frameCount == 1428)
  #expect(sound.durationMilliseconds == 89)
  #expect(blockdrop.getProperty("duration").asInteger() == 89)
  #expect(sound.samples.contains { $0 != 0 })

  // Every sound in the cast is either plain PCM or Shockwave Audio (the
  // music: MP3 in an `ediM` wrapper, whose duration comes from the frame
  // headers without decoding).
  let library = try #require(movie.castManager.library(named: "sound"))
  let sounds = library.members.values.filter { $0.chunk.type == .sound }
  #expect(sounds.count == 62)
  #expect(sounds.allSatisfy { $0.sound != nil || $0.shockwaveAudio != nil })
  let music = try #require(movie.castManager.member(named: "lego1.1"))
  let media = try #require(music.shockwaveAudio)
  #expect(media.sampleRate == 16000)
  // 77 MPEG-2 layer III frames at 16 kHz / 24 kbps: 36 ms each.
  #expect(media.bitstream.count == 8640 - 320)
  #expect(media.durationMilliseconds == 2772)
  #expect(music.getProperty("duration").asInteger() == media.durationMilliseconds)
}

/// `puppetSound(channel, member)` plays at once; `soundBusy` reflects the
/// sink; a channel's playlist feeds the sink one entry at a time as it
/// falls idle — the shape of the sample's `SndSFX` and `SndMusicStart`.
@MainActor
@Test func soundChannelsDriveTheSink() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  let sink = RecordingSink()
  player.audioSink = sink
  let environment = movie.lingoEnvironment

  _ = environment.callGlobal("puppetSound", args: [.integer(3), .string("blockdrop")])
  #expect(sink.played.map(\.channel) == [3])
  #expect(environment.callGlobal("soundBusy", args: [.integer(3)]).asBool())
  #expect(!environment.callGlobal("soundBusy", args: [.integer(4)]).asBool())
  _ = environment.callGlobal("puppetSound", args: [.integer(3), .integer(0)])
  #expect(!environment.callGlobal("soundBusy", args: [.integer(3)]).asBool())

  // A playlist on channel 1: two clips, played back to back.
  let channel = try #require(player.sound(.integer(1)))
  channel.setProperty("volume", value: .integer(128))
  let clip = LingoValue.propertyList([(key: .symbol("member"), value: .string("blockdrop"))])
  let clip2 = LingoValue.propertyList([(key: .symbol("member"), value: .string("blockclick"))])
  _ = channel.callMethod("setPlayList", args: [.list([clip, clip2])])
  #expect(channel.callMethod("getPlayList", args: []).count.asInteger() == 2)
  _ = channel.callMethod("play", args: [])
  #expect(sink.played.count == 2)
  #expect(sink.played.last?.channel == 1)
  #expect(sink.played.last?.volume == 128)
  #expect(channel.callMethod("getPlayList", args: []).count.asInteger() == 1)
  // Still busy: nothing more starts. Once the sink finishes, the next
  // entry goes out on the following frame.
  player.start()
  player.step()
  #expect(sink.played.count == 2)
  sink.busyChannels.remove(1)
  player.step()
  #expect(sink.played.count == 3)
  #expect(channel.callMethod("getPlayList", args: []).count.asInteger() == 0)
}

/// The score's own sound channels play as the playhead crosses them: the
/// sample's bumper frames carry `blockdrop`/`blockclick` then the three
/// intro stings. A sound sustained across frames starts once; a channel
/// `puppetSound` holds is the script's until given back.
@MainActor
@Test func scoreSoundChannelsPlayWithThePlayhead() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let score = try #require(movie.score)

  // What the score authors: nothing on frame 1, effects on frame 2, the
  // intro stings from frame 3, silent again at "loading".
  #expect(score.chunk.frames[0].soundMember(channel: 1) == nil)
  #expect(score.chunk.frames[1].soundMember(channel: 1)?.member == 29)
  #expect(score.chunk.frames[1].soundMember(channel: 2)?.member == 27)

  let player = MoviePlayer(movie: movie)
  let sink = RecordingSink()
  player.audioSink = sink
  player.start()

  // The playhead reaching frame 2 starts both channels' members. (The
  // movie holds on frame 1 waiting for its preload, so the playhead is
  // moved directly.)
  player.movePlayhead(to: 2)
  player.serviceScoreSounds()
  #expect(Set(sink.played.map(\.channel)) == [1, 2])
  let afterFrame2 = sink.played.count

  // The playhead staying put does not retrigger them.
  player.serviceScoreSounds()
  #expect(sink.played.count == afterFrame2)

  // With channel 1 puppeted, its score sound is the script's to ignore.
  _ = movie.lingoEnvironment.callGlobal("puppetSound", args: [.integer(1), .string("turn1")])
  let afterPuppet = sink.played.count
  player.movePlayhead(to: 3)
  player.serviceScoreSounds()
  // Channel 2's intro sting still plays; channel 1's is suppressed.
  #expect(sink.played.count == afterPuppet + 1)
  #expect(sink.played.last?.channel == 2)
}

/// `the soundEnabled` is the global mute: scripts (or the host) flip it,
/// and the player pushes the change to the sink without touching channel
/// state, so unmuting picks sounds up where they would have been.
@MainActor
@Test func soundEnabledMutesTheSink() throws {
  final class MutingSink: AudioSink {
    var muted: Bool?
    func play(_ sound: SoundResource, onChannel channel: Int, volume: Int, pan: Int) {}
    func stop(channel: Int) {}
    func isBusy(channel: Int) -> Bool { false }
    func setMuted(_ muted: Bool) { self.muted = muted }
  }
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  let sink = MutingSink()
  player.audioSink = sink
  player.start()
  #expect(player.soundEnabled)

  // A script writing the property is picked up on the next frame.
  player.movieModel.setProperty("soundEnabled", value: .integer(0))
  player.step()
  #expect(sink.muted == true)
  player.soundEnabled = true
  player.step()
  #expect(sink.muted == false)

  // A host that mutes before starting stays muted from the first frame.
  let mutedPlayer = MoviePlayer(movie: try Movie.load(from: file))
  mutedPlayer.soundEnabled = false
  mutedPlayer.start()
  #expect(!mutedPlayer.soundEnabled)
}
