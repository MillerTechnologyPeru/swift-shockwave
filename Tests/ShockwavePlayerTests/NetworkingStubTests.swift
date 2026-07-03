import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

private func realPlayer() throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  return MoviePlayer(movie: movie)
}

@Test func preloadNetThingReportsDoneImmediately() throws {
  let player = try realPlayer()
  let environment = player.movieModel.lingoEnvironment

  let netID = environment.callGlobal("preloadNetThing", args: [.string("fake://asset")])
  #expect(netID.asInteger() != nil)

  let done = environment.callGlobal("netDone", args: [netID])
  #expect(done.asInteger() == 1)

  let error = environment.callGlobal("netError", args: [netID])
  #expect(error.asString() == "OK")
}

@Test func netIDsAreDistinctAndIncreasing() throws {
  let player = try realPlayer()
  let environment = player.movieModel.lingoEnvironment

  let first = try #require(environment.callGlobal("getNetText", args: [.string("fake://a")]).asInteger())
  let second = try #require(environment.callGlobal("getNetText", args: [.string("fake://b")]).asInteger())
  #expect(second == first + 1)

  let latest = environment.callGlobal("getLatestNetID", args: [])
  #expect(latest.asInteger() == second)
}

@Test func checkNetConnectionReportsOnline() throws {
  let player = try realPlayer()
  let environment = player.movieModel.lingoEnvironment
  #expect(environment.callGlobal("checkNetConnection", args: []).asInteger() == 1)
}
