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
  // Frame 9 channel 12 is `lite_number_2`, a 12x15 member whose record
  // still carries a stale 136x30. Without the stretch flag the member wins.
  let record = try #require(score.frames[8].spriteRecord(channel: 12))
  #expect(!record.stretch)
  #expect((record.width, record.height) == (136, 30))

  let rect = player.spriteRect(record, spriteNumber: 12 - 5)
  #expect((rect.width, rect.height) == (12, 15))
}

@MainActor
@Test func stretchedSpriteKeepsRecordSize() throws {
  let (player, score) = try player()
  // Channel 16 (`door`) is one of the sample's few genuinely stretched
  // sprites: a 57x79 member drawn at 436x426.
  let record = try #require(score.frames[8].spriteRecord(channel: 16))
  #expect(record.stretch)

  let rect = player.spriteRect(record, spriteNumber: 16 - 5)
  #expect((rect.width, rect.height) == (436, 426))
}

@MainActor
@Test func rectIsOffsetByRegistrationPoint() throws {
  let (player, score) = try player()
  // `fusebox_pipes_r` registers at (20, 24), so a record locating it at
  // (56, 170) puts the sprite's corner 20 left and 24 up from there.
  let record = try #require(score.frames[8].spriteRecord(channel: 8))
  #expect((record.left, record.top) == (56, 170))

  let rect = player.spriteRect(record, spriteNumber: 8 - 5)
  #expect((rect.left, rect.top) == (36, 146))
  #expect((rect.width, rect.height) == (40, 49))
}

@MainActor
@Test func registrationOffsetScalesWithStretch() throws {
  let (player, score) = try player()
  // `door` registers at (28, 39) on a 57x79 member drawn at 436x426, so
  // the offset scales by the same factors rather than staying at (28, 39).
  let record = try #require(score.frames[8].spriteRecord(channel: 16))
  let rect = player.spriteRect(record, spriteNumber: 16 - 5)
  #expect(rect.left == 246 - 28 * 436 / 57)
  #expect(rect.top == 210 - 39 * 426 / 79)
}
