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

/// Director performs a `go`'s frame change inside the call — the new
/// frame's `beginSprite`s have run by the time the calling handler's next
/// line executes. The download manager relies on that: it does
/// `go("loading")` and then sets the loading frame's bricks visible over
/// the top of a behavior whose `beginSprite` hides them, then drops them
/// into place from `stepFrame`. Deferring the transition would leave every
/// brick hidden.
@MainActor
@Test func loadingBricksSurviveTheirHidingBehavior() throws {
  let player = try startedPlayer()
  let loading = try #require(player.movieModel.score?.frame(labeled: "loading"))
  let deadline = Date().addingTimeInterval(20)
  // Run until the bricks (sprites 21–34) have all landed on their score
  // positions, or give up.
  var landed = false
  while !landed && Date() < deadline {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
    guard player.currentFrame == loading else { continue }
    landed = (21...34).allSatisfy { number in
      guard let sprite = player.sprite(.integer(number)),
        let record = player.currentRecord(forSprite: number)
      else { return false }
      return sprite.getProperty("locV").asInteger() == record.top
    }
  }
  #expect(landed)
  #expect((21...34).allSatisfy { player.isSpriteVisible($0) })
}

/// A behavior's authored parameters (`[#mylocz: 10000001]` in the score)
/// are applied to the instance before `beginSprite`, so "set my locZ" can
/// lift the loading screen's buttons above the black panel that sits in a
/// lower channel, and the generic buttons know which message they send.
@MainActor
@Test func behaviorParametersReachTheInstance() throws {
  let player = try startedPlayer()
  let loading = try #require(player.movieModel.score?.frame(labeled: "loading"))
  player.jump(to: loading)
  // Sprite 8 (play button) is under sprite 11 (the panel) in channel order
  // but both carry locZ 10000001, so channel order still decides — while
  // sprite 21 (a brick, locZ 10000010) now draws above them all.
  #expect(player.sprite(.integer(8))?.getProperty("locZ").asInteger() == 10_000_001)
  #expect(player.sprite(.integer(21))?.getProperty("locZ").asInteger() == 10_000_010)
  let order = player.drawOrder(forFrame: loading).map(\.spriteNumber)
  let index8 = try #require(order.firstIndex(of: 8))
  let index11 = try #require(order.firstIndex(of: 11))
  let index21 = try #require(order.firstIndex(of: 21))
  #expect(index8 < index11)
  #expect(index11 < index21)
  // Sprite 1 sets no locZ, so it keeps its channel number and stays at the
  // very back.
  #expect(order.first == 1)
}

/// Skipping the intro hands the loading screen to the play manager, which
/// builds the demo level out of pool sprites (200–999) that have no score
/// record at all — each gets a member, a loc, a size and an ink from
/// Lingo. Those puppet-only sprites must reach the renderer's draw order
/// with the puppeted values folded into their record.
@MainActor
@Test func skippingTheIntroPlacesTheDemoLevelOnPoolSprites() throws {
  let player = try startedPlayer()
  let loading = try #require(player.movieModel.score?.frame(labeled: "loading"))
  let deadline = Date().addingTimeInterval(20)
  while player.currentFrame != loading && Date() < deadline {
    player.step()
    Thread.sleep(forTimeInterval: 0.02)
  }
  // SKIP INTRO (sprite 16, "loading generic button" with #skip_movie).
  #expect(player.spriteAt(x: 553, y: 379) == 16)
  player.dispatch("mouseUp", toSprite: 16)

  let poolSprites = player.drawOrder(forFrame: loading).map(\.spriteNumber).filter { $0 >= 200 }
  #expect(poolSprites.count > 100)
  // Every placed piece is a stretched bitmap, and the bricks land on the
  // stage — the level spans all of it, under the title (a few pieces the
  // level erased again are parked off-stage at -100,-100, so not all).
  var onStage = 0
  for number in poolSprites {
    let record = try #require(player.effectiveRecord(forSprite: number))
    #expect(record.isPopulated)
    #expect(record.stretch)
    #expect(player.effectiveMember(record, spriteNumber: number)?.chunk.type == .bitmap)
    let rect = player.spriteRect(record, spriteNumber: number)
    if rect.left >= 0 && rect.top >= 0 && rect.right <= 650 && rect.bottom <= 420 { onStage += 1 }
  }
  #expect(onStage > 100)
  // The panel that covered the intro area is gone.
  #expect(!player.isSpriteVisible(11))
}
