import CSDL3
import SDL3Swift
import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer

/// Composites the current frame's sprites into an SDL renderer: score
/// channel records first (already delta-decoded per frame), overridden by
/// any puppeted `Sprite` property bags the running Lingo has set.
@MainActor
final class StageRenderer {
  private let movie: Movie
  private let renderer: SDLRenderer
  /// Textures keyed by library, member, backColor, and ink mode.
  private var textures: [Int: SDLTexture?] = [:]

  init(movie: Movie, renderer: SDLRenderer) {
    self.movie = movie
    self.renderer = renderer
  }

  func renderFrame(_ frameNumber: Int, player: MoviePlayer) {
    for entry in player.drawOrder(forFrame: frameNumber) {
      guard player.isSpriteVisible(entry.owner) else { continue }
      drawSprite(entry.record, spriteNumber: entry.spriteNumber, player: player)
    }
  }

  private func drawSprite(_ record: SpriteChannelRecord, spriteNumber: Int, player: MoviePlayer) {

    // Member resolution (including any Lingo puppet override) and the
    // geometry both come from the player, so rendering and hit-testing
    // can't drift apart.
    let rect = player.spriteRect(record, spriteNumber: spriteNumber)
    let destination = SDL_FRect(
      x: Float(rect.left), y: Float(rect.top), w: Float(rect.width), h: Float(rect.height))

    guard let member = player.effectiveMember(record, spriteNumber: spriteNumber) else { return }

    let texture: SDLTexture?
    if let properties = member.chunk.bitmapProperties {
      texture = self.texture(
        for: member, properties: properties, ink: SpriteInk(inkNumber: record.ink),
        backColorIndex: record.backColor)
    } else {
      texture = textTexture(for: member, record: record, rect: rect)
    }
    guard let texture else { return }
    // Blend is per-sprite while textures are shared, so the modulation has
    // to be reapplied on every draw rather than baked into the texture.
    try? texture.setAlphaModulation(UInt8(record.blendPercent * 255 / 100))
    try? renderer.copy(texture, destination: destination)
  }

  /// A texture for a text-bearing member (field, text xtra, button) showing
  /// its current `text` — which scripts rewrite at runtime, so the cache
  /// invalidates on content or color change, not just member identity.
  private struct TextEntry {
    var text: String
    var colorIndex: Int
    var layout: CastMember.TextLayout
    var size: (Int, Int)
    var texture: SDLTexture?
  }
  private var textTextures: [Int: TextEntry] = [:]

  private func textTexture(
    for member: CastMember, record: SpriteChannelRecord, rect: SpriteRect
  ) -> SDLTexture? {
    guard member.isTextMember, let text = member.text, !text.isEmpty, rect.width > 0,
      rect.height > 0
    else { return nil }

    let layout = member.textLayout
    let key = (member.libraryNumber << 16) | member.memberNumber
    if let cached = textTextures[key], cached.text == text,
      cached.colorIndex == record.foreColor, cached.layout == layout,
      cached.size == (rect.width, rect.height)
    {
      return cached.texture
    }
    if let _ = textTextures.removeValue(forKey: key)?.texture {
      // SDLTexture is destroyed on deinit
    }

    // The sprite's foreColor is a palette index; junkbot is a Windows-built
    // movie, so System-Win is the palette its authored indices assume.
    let color = BuiltinPalette.systemWin[record.foreColor & 0xFF]
    var entry = TextEntry(
      text: text, colorIndex: record.foreColor, layout: layout, size: (rect.width, rect.height),
      texture: nil)
    defer { textTextures[key] = entry }
    guard
      let rgba = TextRasterizer.rgba(
        text: text, width: rect.width, height: rect.height, color: color,
        fontName: layout.fontName, fontSize: Double(layout.fontSize),
        fixedLineSpace: layout.fixedLineSpace, alignment: layout.alignment),
      let texture = try? SDLTexture(
        renderer: renderer, format: .init(rawValue: SDL_PIXELFORMAT_RGBA32.rawValue), access: .static,
        width: rect.width, height: rect.height)
    else { return nil }
    rgba.withUnsafeBytes { buffer in
      try? texture.update(pixels: UnsafeMutableRawPointer(mutating: buffer.baseAddress!), pitch: rect.width * 4)
    }
    try? texture.setBlendMode([.alpha])
    entry.texture = texture
    return texture
  }

  /// The height a text member's content needs at `width`, for the player's
  /// auto-sizing text sprites.
  static func textHeight(of member: CastMember, width: Int) -> Int {
    guard member.isTextMember, let text = member.text, !text.isEmpty else { return 0 }
    let layout = member.textLayout
    return TextRasterizer.height(
      text: text, width: width, fontName: layout.fontName, fontSize: Double(layout.fontSize),
      fixedLineSpace: layout.fixedLineSpace)
  }

  private func texture(
    for member: CastMember, properties: BitmapMemberProperties, ink: SpriteInk,
    backColorIndex: Int
  ) -> SDLTexture? {
    let key =
      (member.libraryNumber << 24) | (member.memberNumber << 10) | (backColorIndex & 0xFF) << 2
      | ink.cacheBits
    if let cached = textures[key] { return cached }

    var result: SDLTexture?
    defer { textures[key] = result }

    guard let rgba = member.rgba(ink: ink, backColorIndex: backColorIndex) else { return nil }

    let width = properties.bounds.width
    let height = properties.bounds.height
    guard
      let texture = try? SDLTexture(
        renderer: renderer, format: .init(rawValue: SDL_PIXELFORMAT_RGBA32.rawValue), access: .static, width: width, height: height)
    else { return nil }
    rgba.withUnsafeBytes { buffer in
      try? texture.update(pixels: UnsafeMutableRawPointer(mutating: buffer.baseAddress!), pitch: width * 4)
    }
    try? texture.setBlendMode([.alpha])
    // Point-scale, not bilinear: this is pixel art, and several sprites are
    // placed at many times their native size (e.g. a 12×15 icon stretched
    // to 136×30), where linear filtering smears into color noise.
    try? texture.setScaleMode(.nearest)
    result = texture
    return texture
  }

}
