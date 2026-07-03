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
  /// The on-stage rect for a sprite channel record, with any puppeted
  /// `locH`/`locV` override applied — the same geometry `StageRenderer`
  /// draws with, factored out so hit-testing and rendering can't drift.
  /// Registration-point offsetting for scaled/non-bitmap members isn't
  /// modeled yet.
  public func spriteRect(_ record: SpriteChannelRecord, spriteNumber: Int) -> SpriteRect {
    var rect = SpriteRect(
      left: record.left, top: record.top, width: record.width, height: record.height)
    if let sprite = sprite(.integer(spriteNumber)),
      let locH = sprite.getProperty("locH").asInteger(),
      let locV = sprite.getProperty("locV").asInteger()
    {
      rect.left = locH
      rect.top = locV
    }
    return rect
  }

  /// The topmost sprite (Lingo sprite number) whose rect contains
  /// `(x, y)` at the current frame, or `nil` if none. Channels are tested
  /// highest-number-first, since higher channels draw on top and win the
  /// hit. Ink-based matte/per-pixel testing, rotation/skew, and
  /// click-transparent text pass-through aren't modeled yet — this is a
  /// bounding-box-only approximation.
  public func spriteAt(x: Int, y: Int) -> Int? {
    guard let score = movieModel.score, currentFrame >= 1,
      currentFrame <= score.chunk.frames.count
    else { return nil }
    let frame = score.chunk.frames[currentFrame - 1]
    for channel in frame.channels.keys.sorted(by: >) where channel >= 6 {
      guard let record = frame.spriteRecord(channel: channel) else { continue }
      let spriteNumber = channel - 5
      if spriteRect(record, spriteNumber: spriteNumber).contains(x: x, y: y) {
        return spriteNumber
      }
    }
    return nil
  }
}
