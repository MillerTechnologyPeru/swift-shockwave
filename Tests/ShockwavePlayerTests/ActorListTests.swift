import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer
import ShockwaveTestSupport
import Testing

@MainActor
private func startedPlayer() throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let player = MoviePlayer(movie: try Movie.load(from: file))
  player.start()
  return player
}

/// `prepareMovie` sets `the actorList = []`, so the list exists from the
/// first frame even though nothing has joined it yet.
@MainActor
@Test func prepareMovieInitialisesTheActorList() throws {
  let player = try startedPlayer()
  guard case .listType = player.movieModel.getProperty("actorList") else {
    Issue.record("the actorList should be a list after prepareMovie")
    return
  }
}

/// Stepping frames must stay safe whatever `the actorList` holds — it is a
/// plain movie property scripts can set to anything.
@MainActor
@Test func steppingToleratesAnyActorListValue() throws {
  let player = try startedPlayer()
  for value: LingoValue in [.void, .integer(3), .string("nonsense"), .list([.integer(1)])] {
    player.movieModel.setProperty("actorList", value: value)
    player.step()
  }
  #expect(player.currentFrame >= 1)
}

/// The download manager gates its loading sequence on elapsed time
/// (`the ticks > bumpertimer + 110`), so the clock has to actually advance
/// rather than sitting at zero.
@MainActor
@Test func theTicksAndMillisecondsAdvance() throws {
  let player = try startedPlayer()
  let firstTicks = try #require(player.movieModel.getProperty("ticks").asInteger())
  let firstMs = try #require(player.movieModel.getProperty("milliseconds").asInteger())
  #expect(firstTicks >= 0)
  #expect(firstMs >= 0)

  Thread.sleep(forTimeInterval: 0.05)
  let laterMs = try #require(player.movieModel.getProperty("milliseconds").asInteger())
  #expect(laterMs > firstMs)
  #expect(try #require(player.movieModel.getProperty("ticks").asInteger()) >= firstTicks)
}

/// Nothing streams here — the movie is fully in memory before frame one —
/// so the streaming checks a network-built movie waits on all report ready.
@MainActor
@Test func streamingChecksReportEverythingReady() throws {
  let player = try startedPlayer()
  let environment = player.movieModel.lingoEnvironment
  #expect(environment.callGlobal("frameReady", args: []).asInteger() == 1)
  #expect(environment.callGlobal("frameReady", args: [.integer(1), .integer(7)]).asInteger() == 1)
  #expect(environment.callGlobal("mediaReady", args: []).asInteger() == 1)
}
