import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

/// Runs the sample to its loading screen and skips the intro, leaving the
/// demo level up with the play manager live.
@MainActor
private func playerOnTheDemoLevel() throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()
  let loading = try #require(movie.score?.frame(labeled: "loading"))
  let deadline = Date().addingTimeInterval(20)
  while player.currentFrame != loading && Date() < deadline {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }
  player.pressMouse(x: 553, y: 379)
  player.releaseMouse(x: 553, y: 379)
  for _ in 0..<3 {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }
  return player
}

/// The pointer's state is a movie property Lingo polls: `the mouseLoc`,
/// `the mouseH`/`mouseV`, `the mouseDown`, `the clickLoc`.
@MainActor
@Test func mouseStateIsVisibleToLingo() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()
  player.moveMouse(x: 40, y: 50)
  #expect(player.movieModel.getProperty("mouseH").asInteger() == 40)
  #expect(player.movieModel.getProperty("mouseV").asInteger() == 50)
  #expect(player.movieModel.getProperty("mouseLoc")[.integer(2)].asInteger() == 50)
  #expect(!player.movieModel.getProperty("mouseDown").asBool())
  player.pressMouse(x: 41, y: 51)
  #expect(player.movieModel.getProperty("mouseDown").asBool())
  #expect(player.movieModel.getProperty("clickLoc")[.integer(1)].asInteger() == 41)
  player.releaseMouse(x: 41, y: 51)
  #expect(!player.movieModel.getProperty("mouseDown").asBool())
}

/// The demo level's bricks are dragged by the play manager's `stepFrame`,
/// which reads `the mouseDown` and `the mouseLoc` every frame: a press
/// sampled on a brick's cell picks its group up, motion carries it along
/// (translucent while it hovers over no legal resting place), and it stays
/// attached to the pointer until it can be set down. This is "try moving
/// the colored bricks with the mouse", end to end.
@MainActor
@Test func bricksFollowThePointerWhileDragging() throws {
  let player = try playerOnTheDemoLevel()
  // Sprite 210 is the topmost blue brick on the loading level.
  let record = try #require(player.effectiveRecord(forSprite: 210))
  let before = player.spriteRect(record, spriteNumber: 210)
  let x = before.left + before.width / 2
  let y = before.top + before.height / 2
  // The title (sprite 2) covers the whole stage with a transparent ink;
  // the pointer falls through its keyed pixels to the brick.
  #expect(player.spriteAt(x: x, y: y) == 210)

  player.pressMouse(x: x, y: y)
  player.step()  // the frame that samples the press
  Thread.sleep(forTimeInterval: 0.02)
  for i in 1...6 {
    player.moveMouse(x: x, y: y - i * 6)
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }

  guard
    case .object(let object) = player.movieModel.lingoEnvironment.getGlobal("glob")
      .listGetAProp(.symbol("PLAYER")).listGetAProp(.symbol("play_manager")),
    let playManager = object as? ScriptInstance
  else {
    Issue.record("no play manager")
    return
  }
  #expect(playManager.getProperty("toolmode").asString() == "dragging")
  #expect(playManager.getProperty("movePieceGroup").count.asInteger() == 1)
  #expect(playManager.getProperty("gamestatus").listGetAProp(.symbol("moves")).asInteger() == 1)

  let after = player.spriteRect(
    try #require(player.effectiveRecord(forSprite: 210)), spriteNumber: 210)
  #expect(after.top == before.top - 36)  // two rows up
  #expect(after.left == before.left)
  #expect(player.sprite(.integer(210))?.getProperty("blend").asInteger() == 25)
  #expect(!player.transcript.contains { $0.hasPrefix("script error") })
}
