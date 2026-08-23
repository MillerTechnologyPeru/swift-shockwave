import Foundation
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer
import ShockwaveTestSupport
import Testing

/// The score's `locH`/`locV` locate a member's registration point and its
/// `width`/`height` are stale unless the sprite is stretched, so the drawn
/// rect is not the record's own numbers. These pin both rules to real
/// members in the junkbot sample.
@MainActor
private func player() throws -> (MoviePlayer, ScoreChunk) {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let score = try #require(try file.score())
  return (MoviePlayer(movie: movie), score)
}

@MainActor
@Test func unstretchedSpriteUsesMemberBoundsNotRecordSize() throws {
  let (player, score) = try player()
  // Frame 5 channel 53 is `MINIFIG_WALK_R_3_s1`, a 29x17 member whose
  // record carries a stale 29x18. Without the stretch flag the member wins.
  let record = try #require(score.frames[4].spriteRecord(channel: 53))
  #expect(!record.stretch)
  #expect((record.width, record.height) == (29, 18))

  let rect = player.spriteRect(record, spriteNumber: 53 - 5)
  #expect((rect.width, rect.height) == (29, 17))
}

@MainActor
@Test func stretchedSpriteKeepsRecordSize() throws {
  let (player, score) = try player()
  // Frame 9 channel 16 (`gmlb_box_2`) is one of the sample's few genuinely
  // stretched sprites: a 10x10 member drawn at 436x426.
  let record = try #require(score.frames[8].spriteRecord(channel: 16))
  #expect(record.stretch)

  let rect = player.spriteRect(record, spriteNumber: 16 - 5)
  #expect((rect.width, rect.height) == (436, 426))
}

@MainActor
@Test func rectIsOffsetByRegistrationPoint() throws {
  let (player, score) = try player()
  // `arrow` registers at (22, 18), so a record locating it at (56, 170)
  // puts the sprite's corner 22 left and 18 up from there.
  let record = try #require(score.frames[8].spriteRecord(channel: 8))
  #expect((record.left, record.top) == (56, 170))

  let rect = player.spriteRect(record, spriteNumber: 8 - 5)
  #expect((rect.left, rect.top) == (34, 152))
  #expect((rect.width, rect.height) == (45, 37))
}

@MainActor
@Test func registrationOffsetScalesWithStretch() throws {
  let (player, score) = try player()
  // `gmlb_box_2` registers at (5, 5) on a 10x10 member drawn at 436x426,
  // so the offset scales by the same factors rather than staying at (5, 5).
  let record = try #require(score.frames[8].spriteRecord(channel: 16))
  let rect = player.spriteRect(record, spriteNumber: 16 - 5)
  #expect(rect.left == 246 - 5 * 436 / 10)
  #expect(rect.top == 210 - 5 * 426 / 10)
}
