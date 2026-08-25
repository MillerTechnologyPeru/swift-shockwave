import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

@MainActor
private func startedPlayer() throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()
  return player
}

/// The keyboard's state is polled the way the mouse's is: `the key` and
/// `the keyCode` describe the last key down, the modifier properties the
/// modifiers, and `keyPressed(...)` — by character or Mac key code — the
/// keys held right now, which is how the play manager reads the space bar.
@MainActor
@Test func keyStateIsVisibleToLingo() throws {
  let player = try startedPlayer()
  let environment = player.movieModel.lingoEnvironment

  player.pressKey(character: " ", code: 49)
  #expect(player.movieModel.getProperty("key").asString() == " ")
  #expect(player.movieModel.getProperty("keyCode").asInteger() == 49)
  #expect(environment.callGlobal("keyPressed", args: [.string(" ")]).asBool())
  #expect(environment.callGlobal("keyPressed", args: [.integer(49)]).asBool())
  #expect(!environment.callGlobal("keyPressed", args: [.string("j")]).asBool())

  // Releasing empties the held set but leaves `the key` describing the
  // last key pressed, as Director does.
  player.releaseKey(character: " ", code: 49)
  #expect(!environment.callGlobal("keyPressed", args: [.string(" ")]).asBool())
  #expect(player.movieModel.getProperty("key").asString() == " ")

  // `keyPressed` matches either case of a letter.
  player.pressKey(character: "J", code: 38)
  #expect(environment.callGlobal("keyPressed", args: [.string("j")]).asBool())

  player.setModifiers(shift: true, option: false, command: false, control: true)
  #expect(player.movieModel.getProperty("shiftDown").asBool())
  #expect(!player.movieModel.getProperty("optionDown").asBool())
  #expect(player.movieModel.getProperty("controlDown").asBool())
}

/// A key going down raises `keyDown`, which reaches the sample's movie
/// script; its handler fans the key out to the "keyboard equivalent"
/// button behaviors with `sendAllSprites(#equiv_keydown, the key)`.
@MainActor
@Test func keyDownReachesTheMovieScript() throws {
  let player = try startedPlayer()
  var fanned: [LingoValue] = []
  player.movieModel.lingoEnvironment.registerGlobalFunction("sendAllSprites") { args in
    fanned = args
    return .void
  }
  player.pressKey(character: "j", code: 38)
  #expect(fanned.count == 2)
  #expect(fanned.first?.asString() == "equiv_keydown")
  #expect(fanned.last?.asString() == "j")
}
