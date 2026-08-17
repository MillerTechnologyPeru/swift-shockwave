import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer
import ShockwaveTestSupport
import Testing

@MainActor
private func playerAtMenu() throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()
  if let frame = movie.score?.frame(labeled: "mainmenu") { player.jump(to: frame) }
  return player
}

/// A sprite scripts have never touched still has to answer with what the
/// score authored. Reading VOID instead breaks the read-modify-write shape
/// scripts use constantly (`sprite(i).locV = sprite(i).locV - 80`), because
/// the arithmetic then yields VOID and the sprite never moves.
@MainActor
@Test func untouchedSpriteReportsItsScorePosition() throws {
  let player = try playerAtMenu()
  // Frame 9 channel 8 is sprite 3, authored at (56, 170).
  let sprite = try #require(player.sprite(.integer(3)))
  #expect(sprite.getProperty("locH").asInteger() == 56)
  #expect(sprite.getProperty("locV").asInteger() == 170)
  #expect(sprite.getProperty("ink").asInteger() == 8)
}

@MainActor
@Test func untouchedSpriteReportsItsScoreMember() throws {
  let player = try playerAtMenu()
  let sprite = try #require(player.sprite(.integer(3)))
  guard case .object(let object) = sprite.getProperty("member"),
    let member = object as? CastMember
  else {
    Issue.record("sprite should resolve its score member")
    return
  }
  #expect(member.name == "arrow")
}

/// Size comes from the member's bounds, not the record's stale numbers, so
/// it matches what actually gets drawn.
@MainActor
@Test func spriteSizeMatchesTheDrawnRect() throws {
  let player = try playerAtMenu()
  let sprite = try #require(player.sprite(.integer(3)))
  #expect(sprite.getProperty("width").asInteger() == 45)
  #expect(sprite.getProperty("height").asInteger() == 37)
}

/// A puppeted value wins over the score from then on.
@MainActor
@Test func puppetedValuesOverrideTheScore() throws {
  let player = try playerAtMenu()
  let sprite = try #require(player.sprite(.integer(3)))
  sprite.setProperty("locV", value: .integer(999))
  #expect(sprite.getProperty("locV").asInteger() == 999)
  #expect(sprite.getProperty("locH").asInteger() == 56)
}

/// `sprite(n)` and `member(...)` have to work as expressions, not just in
/// the `the ... of sprite n` spelling — scripts store the reference and use
/// it later.
@MainActor
@Test func spriteAndMemberAreCallableFromLingo() throws {
  let player = try playerAtMenu()
  let environment = player.movieModel.lingoEnvironment

  guard case .object(let object) = environment.callGlobal("sprite", args: [.integer(3)]),
    let sprite = object as? Sprite
  else {
    Issue.record("sprite(3) should answer a sprite")
    return
  }
  #expect(sprite.spriteNumber == 3)

  guard case .object(let found) = environment.callGlobal("member", args: [.string("bkg3")]),
    let member = found as? CastMember
  else {
    Issue.record("member(\"bkg3\") should answer a cast member")
    return
  }
  #expect(member.name == "bkg3")
}
