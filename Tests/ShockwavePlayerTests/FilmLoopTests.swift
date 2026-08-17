import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

/// A film loop member carries its own score (`SCVW`) and a bounds rect; on
/// stage the sprite shows the loop's current frame with those bounds
/// centered on its loc, advancing one loop frame per movie frame. The
/// levels screen's portrait (sprite 1, `portrait_1`) is one: 23 frames of
/// Junkbot in a "DANGER" frame, sitting at (492, 23).
@MainActor
@Test func filmLoopSpritesExpandToTheirCurrentFrame() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let portrait = try #require(movie.castManager.member(named: "portrait_1"))
  let loop = try #require(portrait.filmLoopScore)
  #expect(loop.frames.count == 23)
  let bounds = try #require(portrait.chunk.filmLoopProperties?.bounds)
  #expect((bounds.width, bounds.height) == (148, 130))
  // The other loops parse too, padding and all.
  #expect(movie.castManager.member(named: "intro_frame")?.filmLoopScore != nil)
  #expect(movie.castManager.member(named: "xl-box")?.filmLoopScore != nil)

  // Reach the levels screen the way the game does (skip intro, PLAY), so
  // the portrait behavior picks the new-employee portrait.
  let player = MoviePlayer(movie: movie)
  player.start()
  let loading = try #require(movie.score?.frame(labeled: "loading"))
  var deadline = Date().addingTimeInterval(20)
  while player.currentFrame != loading && Date() < deadline {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }
  player.pressMouse(x: 553, y: 379)
  player.releaseMouse(x: 553, y: 379)
  deadline = Date().addingTimeInterval(20)
  // The play button appears once the download manager reports loaded.
  while player.existingSprite(8)?.puppeted("visible")?.asBool() != true, Date() < deadline {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }
  player.pressMouse(x: 197, y: 170)
  player.releaseMouse(x: 197, y: 170)
  for _ in 0..<3 {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }
  #expect(movie.score?.label(at: player.currentFrame) == "levels")
  let record = try #require(player.effectiveRecord(forSprite: 1))
  let rect = player.spriteRect(record, spriteNumber: 1)
  #expect(rect == SpriteRect(left: 492, top: 23, width: 148, height: 130))

  let inner = player.drawOrder(forFrame: 18).filter { $0.owner == 1 }
  #expect(inner.count >= 5)
  #expect(inner.allSatisfy { $0.spriteNumber < 0 })
  // Inner records resolve to members of the loop's own cast, translated
  // into the sprite's rect.
  let backdrop = try #require(inner.first)
  #expect(backdrop.record.castLib == portrait.libraryNumber)
  #expect(player.effectiveMember(backdrop.record, spriteNumber: backdrop.spriteNumber) != nil)
  let backdropRect = player.spriteRect(backdrop.record, spriteNumber: backdrop.spriteNumber)
  #expect(backdropRect.left >= rect.left && backdropRect.right <= rect.right + 1)
  #expect(backdropRect.top >= rect.top && backdropRect.bottom <= rect.bottom + 1)
  // A hit inside the loop belongs to the hosting sprite.
  #expect(player.spriteAt(x: rect.left + 40, y: rect.top + 60) == 1)

  // Playing advances the loop.
  let before = player.filmLoopFrames[1, default: 0]
  player.step()
  #expect(player.filmLoopFrames[1, default: 0] == before + 1)
}
