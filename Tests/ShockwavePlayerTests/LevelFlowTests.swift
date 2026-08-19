import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

/// Runs the sample from its loading screen into a level of the level menu:
/// skip the intro, PLAY, dismiss the opening memo, then pick `row`.
@MainActor
private func playerInLevel(_ row: Int) throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  // No text engine in tests: treat text sprites as fully transparent so
  // clicks reach the list behind the level names.
  player.textCoverage = { _, width, height in [Bool](repeating: false, count: width * height) }
  player.start()
  func run(_ count: Int) {
    for _ in 0..<count {
      player.step()
      Thread.sleep(forTimeInterval: 0.02)
    }
  }
  let loading = try #require(movie.score?.frame(labeled: "loading"))
  let deadline = Date().addingTimeInterval(20)
  while player.currentFrame != loading && Date() < deadline { run(1) }
  player.pressMouse(x: 553, y: 379)  // SKIP INTRO
  player.releaseMouse(x: 553, y: 379)
  while player.existingSprite(8)?.puppeted("visible")?.asBool() != true, Date() < deadline { run(1) }
  player.pressMouse(x: 197, y: 170)  // PLAY
  player.releaseMouse(x: 197, y: 170)
  run(40)
  player.pressMouse(x: 230, y: 352)  // OK on the opening memo
  player.releaseMouse(x: 230, y: 352)
  run(40)
  let y = 95 + 21 * (row - 1)  // the list's 21px rows start at 95
  player.pressMouse(x: 300, y: y)
  player.releaseMouse(x: 300, y: y)
  // The level's title box slides in, holds for two seconds of `the timer`,
  // slides out, and only then does its callback start the level.
  let started = Date().addingTimeInterval(20)
  while Date() < started {
    run(1)
    if case .object(let object) = player.movieModel.lingoEnvironment.getGlobal("glob")
      .listGetAProp(.symbol("PLAYER")).listGetAProp(.symbol("play_manager")),
      (object as? ScriptInstance)?.getProperty("activeState").asString() == "Run"
    {
      break
    }
  }
  return player
}

@MainActor
private func manager(_ player: MoviePlayer, _ name: String) throws -> ScriptInstance {
  let player_ = player.movieModel.lingoEnvironment.getGlobal("glob")
    .listGetAProp(.symbol("PLAYER"))
  guard case .object(let object) = player_.listGetAProp(.symbol(name)),
    let instance = object as? ScriptInstance
  else {
    Issue.record("no \(name)")
    throw CancellationError()
  }
  return instance
}

/// Any level in the menu starts: the playhead reaches the play frame, the
/// level's pieces are placed, and Junkbot is among them. (Levels past the
/// second used to bounce back to the menu, because `building.LEVELS.count`
/// answered the property list's own key count.)
@MainActor
@Test(arguments: [1, 5, 8, 12]) func anyLevelInTheMenuStarts(row: Int) throws {
  let player = try playerInLevel(row)
  #expect(player.movieModel.score?.label(at: player.currentFrame) == "play")

  let glob = player.movieModel.lingoEnvironment.getGlobal("glob")
  #expect(glob.listGetAProp(.symbol("current")).listGetAProp(.symbol("level")).asInteger() == row)

  let play = try manager(player, "play_manager")
  #expect(play.getProperty("activeState").asString() == "Run")
  guard case .object(let field) = play.getProperty("playfield_manager"),
    case .listType(let parts) = field.getProperty("partslist")
  else {
    Issue.record("no playfield")
    return
  }
  #expect(parts.elements.count > 20)
  #expect(
    parts.elements.contains {
      $0.listGetAProp(.symbol("type")).asString().uppercased() == "MINIFIG"
    })
  #expect(!player.transcript.contains { $0.hasPrefix("script error") })
}

/// Clearing a level runs the win path: the play manager reports it to the
/// game manager, which stops the level, banks the move count against the
/// level, and moves to the between-levels state the success dialog drives.
@MainActor
@Test func clearingALevelBanksItAndPausesForTheDialog() throws {
  let player = try playerInLevel(1)
  let play = try manager(player, "play_manager")
  let game = try manager(player, "game_manager")
  // The movie never marks a running level in `gameState` — it only leaves
  // it at #PREGAME until a level ends.
  #expect(game.getProperty("gameState").asString() == "PREGAME")

  // One brick move, then the last goal collected — what the level's flag
  // pieces report when Junkbot eats the final piece of trash.
  _ = play.callMethod("addStatus", args: [.symbol("moves"), .integer(1)])
  let goals = play.getProperty("numGoals").asInteger() ?? 0
  #expect(goals >= 1)
  for _ in 0..<goals {
    _ = play.callMethod("addStatus", args: [.symbol("goals"), .integer(1)])
  }

  #expect(play.getProperty("activeState").asString() == "pause")
  #expect(game.getProperty("gameState").asString() == "INTERLEVEL")
  let glob = player.movieModel.lingoEnvironment.getGlobal("glob")
  #expect(glob.listGetAProp(.symbol("current")).listGetAProp(.symbol("moves")).asInteger() == 1)
  let level1 = glob.listGetAProp(.symbol("building"))[.integer(1)]
    .listGetAProp(.symbol("LEVELS"))[.integer(1)]
  #expect(level1.listGetAProp(.symbol("moves")).asInteger() == 1)
  #expect(!player.transcript.contains { $0.hasPrefix("script error") })
}
