import LingoRuntime
import ShockwaveFile
import ShockwaveModel

/// A sprite's on-stage rectangle, in movie (unscaled) coordinates.
public struct SpriteRect: Equatable, Sendable {
  public var left: Int
  public var top: Int
  public var width: Int
  public var height: Int

  public var right: Int { left + width }
  public var bottom: Int { top + height }

  public func contains(x: Int, y: Int) -> Bool {
    x >= left && x < right && y >= top && y < bottom
  }
}

extension MoviePlayer {
  /// The cast member a sprite channel actually shows: the score record's
  /// own reference, unless the running Lingo has puppeted a different
  /// member onto the channel.
  public func effectiveMember(_ record: SpriteChannelRecord, spriteNumber: Int) -> CastMember? {
    if let sprite = sprite(.integer(spriteNumber)),
      case .object(let memberObject) = sprite.getProperty("member"),
      let castMember = memberObject as? CastMember
    {
      return castMember
    }
    return movieModel.castManager.library(scoreCastLib: record.castLib)?.member(record.member)
  }

  /// The score record covering a sprite channel on the current frame, or
  /// `nil` when the channel is empty there.
  public func currentRecord(forSprite spriteNumber: Int) -> SpriteChannelRecord? {
    guard let score = movieModel.score, currentFrame >= 1,
      currentFrame <= score.chunk.frames.count
    else { return nil }
    return score.chunk.frames[currentFrame - 1].spriteRecord(channel: spriteNumber + 5)
  }

  /// Whether a sprite channel is currently showing.
  ///
  /// Scripts hide and reveal whole groups of sprites by setting
  /// `the visible of sprite`, so a channel with a score record isn't
  /// necessarily on screen. An untouched channel has no `visible` property
  /// at all, which means visible — only an explicit false hides it.
  public func isSpriteVisible(_ spriteNumber: Int) -> Bool {
    guard let sprite = sprite(.integer(spriteNumber)) else { return true }
    let visible = sprite.getProperty("visible")
    if case .void = visible { return true }
    return visible.asBool()
  }

  /// The on-stage rect for a sprite channel record, with any puppeted
  /// `locH`/`locV` override applied — the same geometry `StageRenderer`
  /// draws with, factored out so hit-testing and rendering can't drift.
  ///
  /// Two things make this more than the record's own numbers. The record's
  /// `locH`/`locV` locate the member's *registration point*, not its
  /// top-left corner, so the registration offset comes back off to get the
  /// corner. And the record's `width`/`height` are only the drawn size when
  /// the sprite is stretched; otherwise the member's natural bounds win,
  /// and the record's stale values are ignored.
  public func spriteRect(_ record: SpriteChannelRecord, spriteNumber: Int) -> SpriteRect {
    var width = record.width
    var height = record.height
    var regX = 0
    var regY = 0
    if let properties = effectiveMember(record, spriteNumber: spriteNumber)?
      .chunk.bitmapProperties
    {
      let natural = properties.bounds
      if !record.stretch {
        width = natural.width
        height = natural.height
      }
      // Stretching scales the registration offset along with the artwork.
      regX = natural.width > 0 ? properties.regX * width / natural.width : properties.regX
      regY = natural.height > 0 ? properties.regY * height / natural.height : properties.regY
    }

    var locH = record.left
    var locV = record.top
    if let sprite = sprite(.integer(spriteNumber)),
      let puppetH = sprite.getProperty("locH").asInteger(),
      let puppetV = sprite.getProperty("locV").asInteger()
    {
      locH = puppetH
      locV = puppetV
    }
    return SpriteRect(left: locH - regX, top: locV - regY, width: width, height: height)
  }

  /// The populated sprite channels of a frame, back to front: the order
  /// they draw in, and the reverse of the order they take a hit in.
  ///
  /// Director stacks by `locZ`, which defaults to the sprite number, so an
  /// untouched score draws in channel order — but a behavior that sets
  /// `locZ` (the sample's "set my locZ", which lifts the loading screen's
  /// buttons above the black panel in a lower channel) reorders. Ties fall
  /// back to channel order.
  public func drawOrder(forFrame frameNumber: Int) -> [(spriteNumber: Int, record: SpriteChannelRecord)] {
    guard let score = movieModel.score, frameNumber >= 1,
      frameNumber <= score.chunk.frames.count
    else { return [] }
    let frame = score.chunk.frames[frameNumber - 1]
    var entries: [(spriteNumber: Int, record: SpriteChannelRecord, z: Int)] = []
    for channel in frame.channels.keys where channel >= 6 {
      guard let record = frame.spriteRecord(channel: channel) else { continue }
      let spriteNumber = channel - 5
      let z = sprite(.integer(spriteNumber))?.getProperty("locZ").asInteger() ?? spriteNumber
      entries.append((spriteNumber, record, z))
    }
    return entries
      .sorted { ($0.z, $0.spriteNumber) < ($1.z, $1.spriteNumber) }
      .map { ($0.spriteNumber, $0.record) }
  }

  /// The topmost sprite (Lingo sprite number) whose rect contains
  /// `(x, y)` at the current frame, or `nil` if none. Sprites are tested
  /// front to back, so whatever draws on top wins the hit. Ink-based
  /// matte/per-pixel testing, rotation/skew, and click-transparent text
  /// pass-through aren't modeled yet — this is a bounding-box-only
  /// approximation.
  public func spriteAt(x: Int, y: Int) -> Int? {
    for (spriteNumber, record) in drawOrder(forFrame: currentFrame).reversed()
    where isSpriteVisible(spriteNumber) {
      if spriteRect(record, spriteNumber: spriteNumber).contains(x: x, y: y) {
        return spriteNumber
      }
    }
    return nil
  }
}
