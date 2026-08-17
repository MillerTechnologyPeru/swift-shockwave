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
    if case .object(let memberObject)? = existingSprite(spriteNumber)?.puppeted("member"),
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

  /// The record a sprite channel is drawn from: the score's record for the
  /// current frame with every property the running Lingo has puppeted
  /// folded over it — member, ink, blend, colors, size (which turns on
  /// stretch, as setting `width`/`height` does in Director) and position.
  ///
  /// A channel the score leaves empty still yields a record once Lingo has
  /// given it a member; that is what lets a puppet-only sprite exist at
  /// all. `nil` means there is nothing to draw on this channel.
  public func effectiveRecord(forSprite spriteNumber: Int) -> SpriteChannelRecord? {
    let scored = currentRecord(forSprite: spriteNumber)
    guard let sprite = existingSprite(spriteNumber) else { return scored }
    var record: SpriteChannelRecord
    if let scored {
      record = scored
    } else if case .object(let object)? = sprite.puppeted("member"),
      object is CastMember
    {
      record = .empty
    } else {
      return nil
    }
    if case .object(let object)? = sprite.puppeted("member"), let member = object as? CastMember {
      record.castLib = member.libraryNumber
      record.member = member.memberNumber
    }
    if let ink = sprite.puppeted("ink")?.asInteger() { record.ink = ink }
    if let foreColor = sprite.puppeted("foreColor")?.asInteger() { record.foreColor = foreColor }
    if let backColor = sprite.puppeted("backColor")?.asInteger() { record.backColor = backColor }
    if let blend = sprite.puppeted("blend")?.asInteger() {
      record.blendEnabled = true
      record.blendAmount = 255 - Swift.max(0, Swift.min(100, blend)) * 255 / 100
    }
    if let width = sprite.puppeted("width")?.asInteger() {
      record.width = width
      record.stretch = true
    }
    if let height = sprite.puppeted("height")?.asInteger() {
      record.height = height
      record.stretch = true
    }
    if let locH = sprite.puppeted("locH")?.asInteger() { record.left = locH }
    if let locV = sprite.puppeted("locV")?.asInteger() { record.top = locV }
    return record
  }

  /// Whether a sprite channel is currently showing.
  ///
  /// Scripts hide and reveal whole groups of sprites by setting
  /// `the visible of sprite`, so a channel with a score record isn't
  /// necessarily on screen. An untouched channel has no `visible` property
  /// at all, which means visible — only an explicit false hides it.
  public func isSpriteVisible(_ spriteNumber: Int) -> Bool {
    guard let visible = existingSprite(spriteNumber)?.puppeted("visible") else { return true }
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
    } else if let properties = effectiveMember(record, spriteNumber: spriteNumber)?
      .chunk.filmLoopProperties
    {
      // A film loop registers at the center of its bounds.
      if !record.stretch {
        width = properties.bounds.width
        height = properties.bounds.height
      }
      regX = width / 2
      regY = height / 2
    }

    if !record.stretch, let measure = textHeightMeasurer,
      let member = effectiveMember(record, spriteNumber: spriteNumber), member.isTextMember
    {
      // Text grows to its content; the score's height is only where it
      // started.
      height = max(height, measure(member, width))
    }

    var locH = record.left
    var locV = record.top
    if let sprite = existingSprite(spriteNumber) {
      if let puppetH = sprite.puppeted("locH")?.asInteger() { locH = puppetH }
      if let puppetV = sprite.puppeted("locV")?.asInteger() { locV = puppetV }
    }
    return SpriteRect(left: locH - regX, top: locV - regY, width: width, height: height)
  }

  /// One thing to draw: a sprite channel's record, or one frame-channel of
  /// a film loop playing on a sprite. `owner` is the stage sprite it
  /// belongs to (itself, for an ordinary sprite; the hosting sprite, for a
  /// film loop's inner channel, whose `spriteNumber` is then a synthetic
  /// negative id with no puppet state of its own).
  public struct DrawEntry {
    public var spriteNumber: Int
    public var owner: Int
    public var record: SpriteChannelRecord
  }

  /// The populated sprite channels of a frame, back to front: the order
  /// they draw in, and the reverse of the order they take a hit in.
  ///
  /// Director stacks by `locZ`, which defaults to the sprite number, so an
  /// untouched score draws in channel order — but a behavior that sets
  /// `locZ` (the sample's "set my locZ", which lifts the loading screen's
  /// buttons above the black panel in a lower channel) reorders. Ties fall
  /// back to channel order.
  ///
  /// Channels the score populates on the frame are joined by any sprite
  /// Lingo has puppeted a member onto (`effectiveRecord(forSprite:)`), so a
  /// level built entirely from pool sprites draws too. Only the current
  /// frame carries puppet state. A sprite showing a film loop is replaced
  /// by that loop's current frame, laid over the sprite's rect.
  public func drawOrder(forFrame frameNumber: Int) -> [DrawEntry] {
    guard let score = movieModel.score, frameNumber >= 1,
      frameNumber <= score.chunk.frames.count
    else { return [] }
    let frame = score.chunk.frames[frameNumber - 1]
    var numbers = Set(frame.channels.keys.filter { $0 >= 6 }.map { $0 - 5 })
    if frameNumber == currentFrame {
      numbers.formUnion(puppetedSpriteNumbers())
    }
    var entries: [(entry: DrawEntry, z: Int, order: Int)] = []
    for spriteNumber in numbers {
      let record: SpriteChannelRecord?
      if frameNumber == currentFrame {
        record = effectiveRecord(forSprite: spriteNumber)
      } else {
        record = frame.spriteRecord(channel: spriteNumber + 5)
      }
      guard let record else { continue }
      let z = existingSprite(spriteNumber)?.puppeted("locZ")?.asInteger() ?? spriteNumber
      let inner = filmLoopEntries(record: record, spriteNumber: spriteNumber)
      if inner.isEmpty {
        entries.append((DrawEntry(spriteNumber: spriteNumber, owner: spriteNumber, record: record), z, 0))
      } else {
        for (index, entry) in inner.enumerated() {
          entries.append((entry, z, index + 1))
        }
      }
    }
    return entries
      .sorted { ($0.z, $0.entry.owner, $0.order) < ($1.z, $1.entry.owner, $1.order) }
      .map(\.entry)
  }

  /// The channels of the frame a film loop sprite is currently showing,
  /// translated onto the stage — empty for anything that isn't a film
  /// loop with frames. Inner records name members in the loop's own cast
  /// as `castLib 65535`; positions are relative to the loop's bounds,
  /// which sit centered on the sprite's loc (and scale with a stretched
  /// sprite). One level only: a loop inside a loop draws as nothing.
  private func filmLoopEntries(record: SpriteChannelRecord, spriteNumber: Int) -> [DrawEntry] {
    guard spriteNumber >= 0, let member = effectiveMember(record, spriteNumber: spriteNumber),
      let loop = member.filmLoopScore, !loop.frames.isEmpty,
      let properties = member.chunk.filmLoopProperties, properties.bounds.width > 0,
      properties.bounds.height > 0
    else { return [] }
    let host = spriteRect(record, spriteNumber: spriteNumber)
    let frameIndex = filmLoopFrames[spriteNumber, default: 0] % loop.frames.count
    let frame = loop.frames[frameIndex]
    let bounds = properties.bounds
    var entries: [DrawEntry] = []
    for channel in frame.channels.keys.sorted() where channel >= 6 {
      guard var inner = frame.spriteRecord(channel: channel) else { continue }
      if inner.castLib == 65535 { inner.castLib = member.libraryNumber }
      inner.left = host.left + (inner.left - bounds.left) * host.width / bounds.width
      inner.top = host.top + (inner.top - bounds.top) * host.height / bounds.height
      if record.stretch {
        inner.width = inner.width * host.width / bounds.width
        inner.height = inner.height * host.height / bounds.height
        inner.stretch = true
      }
      entries.append(
        DrawEntry(spriteNumber: -(spriteNumber * 1024 + channel), owner: spriteNumber, record: inner))
    }
    return entries
  }

  /// The topmost sprite (Lingo sprite number) under `(x, y)` at the
  /// current frame, or `nil` if none. Sprites are tested front to back, so
  /// whatever draws on top wins the hit.
  ///
  /// A bitmap drawn with a transparent ink only takes the hit where it
  /// actually paints: Director lets the pointer fall through the keyed
  /// pixels, which is what makes the sample's bricks reachable under its
  /// full-stage, background-transparent title. Copy-ink bitmaps and every
  /// other member type are tested by rect. Rotation/skew aren't modeled.
  public func spriteAt(x: Int, y: Int) -> Int? {
    for entry in drawOrder(forFrame: currentFrame).reversed() where isSpriteVisible(entry.owner) {
      let rect = spriteRect(entry.record, spriteNumber: entry.spriteNumber)
      guard rect.contains(x: x, y: y) else { continue }
      if paints(entry.record, spriteNumber: entry.spriteNumber, rect: rect, x: x, y: y) {
        return entry.owner
      }
    }
    return nil
  }

  /// Whether a transparent-ink text sprite paints at `(x, y)`: only its
  /// glyph pixels take the hit. Without a coverage provider the whole rect
  /// does.
  private func textPaints(_ member: CastMember, rect: SpriteRect, x: Int, y: Int) -> Bool {
    guard let textCoverage, let text = member.text, !text.isEmpty else { return true }
    let key = (member.libraryNumber << 16) | member.memberNumber
    let layout = member.textLayout
    let mask: [Bool]
    if let cached = textMasks[key], cached.text == text, cached.layout == layout,
      cached.size == (rect.width, rect.height)
    {
      mask = cached.mask
    } else {
      guard let computed = textCoverage(member, rect.width, rect.height) else { return true }
      mask = computed
      textMasks[key] = (text, layout, (rect.width, rect.height), computed)
    }
    guard mask.count == rect.width * rect.height else { return true }
    return mask[(y - rect.top) * rect.width + (x - rect.left)]
  }

  /// Whether the sprite puts a pixel at stage point `(x, y)`, known to be
  /// inside `rect`. Anything without decodable bitmap coverage under a
  /// transparent ink counts as painting its whole rect.
  private func paints(
    _ record: SpriteChannelRecord, spriteNumber: Int, rect: SpriteRect, x: Int, y: Int
  ) -> Bool {
    let ink = SpriteInk(inkNumber: record.ink)
    guard ink != .copy, let member = effectiveMember(record, spriteNumber: spriteNumber) else {
      return true
    }
    if member.isTextMember {
      return textPaints(member, rect: rect, x: x, y: y)
    }
    guard let properties = member.chunk.bitmapProperties else { return true }
    let width = properties.bounds.width
    let height = properties.bounds.height
    guard width > 0, height > 0, rect.width > 0, rect.height > 0 else { return true }
    let key = HitMaskKey(
      library: member.libraryNumber, member: member.memberNumber, ink: ink,
      backColor: record.backColor)
    let mask: [Bool]
    if let cached = hitMasks[key] {
      mask = cached
    } else {
      guard let rgba = member.rgba(ink: ink, backColorIndex: record.backColor) else {
        hitMasks[key] = []
        return true
      }
      mask = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] != 0 }
      hitMasks[key] = mask
    }
    guard mask.count == width * height else { return true }
    // Map the stage point back into the member's own pixels, undoing any
    // stretch.
    let sourceX = min(width - 1, (x - rect.left) * width / rect.width)
    let sourceY = min(height - 1, (y - rect.top) * height / rect.height)
    return mask[sourceY * width + sourceX]
  }
}
