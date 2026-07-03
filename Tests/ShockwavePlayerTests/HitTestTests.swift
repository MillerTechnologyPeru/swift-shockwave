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

@Test func spriteAtPicksHighestOverlappingChannel() throws {
  let player = try realPlayer()
  player.start()
  player.jump(to: 26)

  // Frame 26 has two channels covering (600, 100): channel 6 (sprite 1,
  // rect 566,88,148,130) and channel 7 (sprite 2, rect 0,0,650,420, the
  // full-stage backdrop). Channel 7 is higher, and higher channels draw
  // on top, so sprite 2 wins even though sprite 1's smaller rect also
  // contains the point.
  #expect(player.spriteAt(x: 600, y: 100) == 2)

  // (100, 320) additionally falls inside channel 64 (sprite 59, rect
  // 78,305,44,29) and channel 16 (sprite 11, rect 92,39,215,324), both
  // above the backdrop. Channel 64 is the highest of the three, so it
  // should win over both the backdrop and channel 16.
  #expect(player.spriteAt(x: 100, y: 320) == 59)
}

@Test func spriteAtReturnsNilOutsideEveryRect() throws {
  let player = try realPlayer()
  player.start()
  player.jump(to: 26)

  // Outside the stage entirely (stage is 650x420 here) — no channel,
  // including the full-stage backdrop, can contain this point.
  #expect(player.spriteAt(x: 700, y: 500) == nil)
}

@Test func spriteAtUsesPuppetedLocOverride() throws {
  let player = try realPlayer()
  player.start()
  player.jump(to: 26)

  // Sprite 2 (channel 7, the full-stage backdrop) normally wins the hit
  // at (600, 100) over sprite 1 (channel 6) underneath it. Puppeting
  // sprite 2 away uncovers sprite 1 at that spot, and sprite 2 itself
  // becomes hittable at its new puppeted location instead.
  let sprite2 = try #require(player.sprite(.integer(2)))
  sprite2.setProperty("locH", value: .integer(1000))
  sprite2.setProperty("locV", value: .integer(1000))

  #expect(player.spriteAt(x: 600, y: 100) == 1)
  #expect(player.spriteAt(x: 1000, y: 1000) == 2)
}
