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

@MainActor
private func actorNames(_ player: MoviePlayer) -> [String] {
  guard case .listType(let list) = player.movieModel.getProperty("actorList") else { return [] }
  return list.elements.compactMap {
    guard case .object(let object) = $0, let instance = object as? ScriptInstance else {
      return nil
    }
    return instance.member.name
  }
}

/// A handler reads `me` as its first argument, so anything it passes onward
/// depends on that binding. Both of the sample's actors join the list by
/// calling `(the actorList).add(me)` from inside a handler, which makes the
/// list a direct check that `me` is bound to the instance and not VOID.
@MainActor
@Test func actorsRegisterThemselvesDuringStartup() throws {
  let player = try startedPlayer()
  #expect(
    actorNames(player).sorted() == ["database manager", "download manager", "play manager"])
}

/// `the visible of sprite` is how scripts hide and reveal groups of
/// sprites; an untouched channel has no such property and stays visible.
@MainActor
@Test func spriteVisibilityFollowsThePuppetedProperty() throws {
  let player = try startedPlayer()
  #expect(player.isSpriteVisible(3))

  player.sprite(.integer(3))?.setProperty("visible", value: .integer(0))
  #expect(!player.isSpriteVisible(3))

  player.sprite(.integer(3))?.setProperty("visible", value: .integer(1))
  #expect(player.isSpriteVisible(3))
}

/// The sample idles on frame 1 until its download manager's `stepFrame`
/// calls `go("loading")`. That only lands if an actor's `go` redirects the
/// playhead immediately — a looping frame script would otherwise overwrite
/// the target with its own `go to the frame` before it took effect.
@MainActor
@Test func anActorCanSteerThePlayheadOffALoopingFrame() throws {
  let player = try startedPlayer()
  #expect(player.currentFrame == 1)

  let loading = try #require(player.movieModel.score?.frame(labeled: "loading"))
  let deadline = Date().addingTimeInterval(10)
  while player.currentFrame == 1 && Date() < deadline {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }
  #expect(player.currentFrame == loading)
}
