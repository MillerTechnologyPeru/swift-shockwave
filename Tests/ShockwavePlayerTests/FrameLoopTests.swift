import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

private func startedPlayer() throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()
  return player
}

@Test func startDispatchesLifecycleInOrder() throws {
  let player = try startedPlayer()
  #expect(player.isPlaying)
  #expect(player.currentFrame == 1)
  #expect(player.movieModel.getProperty("frame").asInteger() == 1)

  // prepareMovie ran (its side effects stick) ...
  #expect(player.movieModel.getProperty("exitLock").asInteger() == 1)
  // ... then prepareFrame and enterFrame reached the movie script in order.
  #expect(player.transcript.contains("Junk is food!"))
  #expect(player.transcript.contains("My name is Junkbot"))
  let prepareIndex = try #require(player.transcript.firstIndex(of: "Junk is food!"))
  let enterIndex = try #require(player.transcript.firstIndex(of: "My name is Junkbot"))
  #expect(prepareIndex < enterIndex)
}

@Test func frameloopBehaviorHoldsTheFrame() throws {
  let player = try startedPlayer()
  // Frame 1's frame script is "frameloop": `on exitFrame me / go(the frame)`.
  // Stepping must dispatch it, and its `go(the frame)` holds the playhead —
  // the classic Director idle-loop idiom, running as real bytecode.
  player.step()
  #expect(player.currentFrame == 1)
  #expect(player.isPlaying)

  // The movie-level exitFrame handler also ran during the step (frame
  // events broadcast to every level), and re-entering the frame dispatched
  // prepareFrame/enterFrame again.
  let exits = player.transcript.filter { $0 == "I love to eat trash" }
  #expect(exits.count == 1)
  let enters = player.transcript.filter { $0 == "My name is Junkbot" }
  #expect(enters.count == 2)
}

@Test func jumpMovesPlayheadAndSwapsSpans() throws {
  let player = try startedPlayer()
  player.jump(to: 9)  // "mainmenu"
  #expect(player.currentFrame == 9)
  #expect(player.movieModel.getProperty("frame").asInteger() == 9)
  #expect(player.movieModel.score?.label(at: player.currentFrame) == "mainmenu")
  #expect(!player.activeSpans.isEmpty)
}

@Test func stepPastLastFrameStopsPlayback() throws {
  let player = try startedPlayer()
  let lastFrame = try #require(player.movieModel.score?.frameCount)
  player.jump(to: lastFrame)
  // Frame 30 has no frame script holding the playhead, so stepping falls
  // off the end of the score and playback stops.
  player.step()
  #expect(!player.isPlaying)
  #expect(player.activeSpans.isEmpty)
}

@Test func mouseUpBubblesThroughSpriteThenFrameThenMovie() throws {
  let player = try startedPlayer()
  let score = try #require(player.movieModel.score)

  // Find a span carrying the "global button" behavior (legoparts member 8,
  // whose compiled script defines mouseUp) and jump to its frames.
  let globalButton = ScoreChunk.BehaviorReference(castLib: 1, member: 8)
  let span = try #require(score.spans.first { $0.behaviors.contains(globalButton) })
  let spriteNumber = try #require(span.spriteNumber)
  player.jump(to: span.startFrame)

  // Dispatch to the sprite: its behavior defines mouseUp, so it handles it.
  #expect(player.dispatch("mouseUp", toSprite: spriteNumber))

  // No sprite target and no frame/movie mouseUp handler at this frame:
  // nothing handles the event.
  #expect(!player.dispatch("mouseUp"))

  // Movie-script handlers are the last stop in the bubbling order.
  #expect(player.dispatch("keyDown"))
}
