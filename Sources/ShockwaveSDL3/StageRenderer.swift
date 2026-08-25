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
    // A font the movie carries is drawn from its own outlines; anything
    // else goes through the system's text engine.
    let embedded = Self.embeddedMask(
      of: member, width: rect.width, height: rect.height, movie: movie
    ).map { mask -> [UInt8] in
      var pixels = [UInt8](repeating: 0, count: rect.width * rect.height * 4)
      for (index, painted) in mask.enumerated() where painted {
        pixels[index * 4] = color.red
        pixels[index * 4 + 1] = color.green
        pixels[index * 4 + 2] = color.blue
        pixels[index * 4 + 3] = 255
      }
      return pixels
    }
    guard
      let rgba = embedded
        ?? TextRasterizer.rgba(
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

  /// Which pixels a text member paints when drawn into `width`×`height`,
  /// for the player's pointer hit-testing.
  static func textCoverage(of member: CastMember, width: Int, height: Int, movie: Movie) -> [Bool]? {
    guard member.isTextMember, let text = member.text, !text.isEmpty else { return nil }
    if let mask = embeddedMask(of: member, width: width, height: height, movie: movie) {
      return mask
    }
    let layout = member.textLayout
    guard
      let rgba = TextRasterizer.rgba(
        text: text, width: width, height: height,
        color: PaletteChunk.Color(red: 0, green: 0, blue: 0),
        fontName: layout.fontName, fontSize: Double(layout.fontSize),
        fixedLineSpace: layout.fixedLineSpace, alignment: layout.alignment)
    else { return nil }
    return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] != 0 }
  }

  /// The height a text member's content needs at `width`, for the player's
  /// auto-sizing text sprites.
  /// Where a text member set in a font the movie carries paints, or `nil`
  /// when its font isn't one.
  static func embeddedMask(
    of member: CastMember, width: Int, height: Int, movie: Movie
  ) -> [Bool]? {
    guard member.isTextMember, let text = member.text, !text.isEmpty else { return nil }
    let layout = member.textLayout
    guard let name = layout.fontName, let font = movie.castManager.embeddedFont(named: name)
    else { return nil }
    return EmbeddedTextRasterizer.mask(
      text: text, font: font, size: layout.fontSize, width: width, height: height,
      fixedLineSpace: layout.fixedLineSpace, alignment: layout.alignment)
  }

  static func textHeight(of member: CastMember, width: Int, movie: Movie) -> Int {
    guard member.isTextMember, let text = member.text, !text.isEmpty else { return 0 }
    let layout = member.textLayout
    if let name = layout.fontName, let font = movie.castManager.embeddedFont(named: name) {
      return EmbeddedTextRasterizer.height(
        text: text, font: font, size: layout.fontSize, width: width,
        fixedLineSpace: layout.fixedLineSpace)
    }
    return TextRasterizer.height(
      text: text, width: width, fontName: layout.fontName, fontSize: Double(layout.fontSize),
      fixedLineSpace: layout.fixedLineSpace)
  }

  private func texture(
    for member: CastMember, properties: BitmapMemberProperties, ink: SpriteInk,
    backColorIndex: Int
  ) -> SDLTexture? {
    let key =
      (member.libraryNumber << 26) | (member.memberNumber << 12) | (backColorIndex & 0xFF) << 4
      | ink.cacheBits
    if let cached = textures[key] { return cached }

    var result: SDLTexture?
    defer { textures[key] = result }

    guard var rgba = member.rgba(ink: ink, backColorIndex: backColorIndex) else { return nil }
    if ink == .mask {
      applyMaskMember(to: &rgba, member: member, properties: properties)
    }

    let width = properties.bounds.width
    let height = properties.bounds.height
    guard
      let texture = try? SDLTexture(
        renderer: renderer, format: .init(rawValue: SDL_PIXELFORMAT_RGBA32.rawValue), access: .static, width: width, height: height)
    else { return nil }
    rgba.withUnsafeBytes { buffer in
      try? texture.update(pixels: UnsafeMutableRawPointer(mutating: buffer.baseAddress!), pitch: width * 4)
    }
    try? texture.setBlendMode(Self.blendMode(for: ink))
    // Point-scale, not bilinear: this is pixel art, and several sprites are
    // placed at many times their native size (e.g. a 12×15 icon stretched
    // to 136×30), where linear filtering smears into color noise.
    try? texture.setScaleMode(.nearest)
    result = texture
    return texture
  }

  /// How an ink combines with what's already on the stage. The keyed and
  /// inverted inks are baked into the texture's pixels and composite
  /// normally; the arithmetic inks are the blend equation itself.
  private static func blendMode(for ink: SpriteInk) -> BitMaskOptionSet<SDLBlendMode> {
    let mode: SDL_BlendMode
    switch ink {
    case .add:
      mode = SDL_BLENDMODE_ADD
    case .subtract:
      // The stage minus the sprite: reverse subtract with both at full
      // weight, alpha left alone.
      mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_REV_SUBTRACT,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD)
    case .lightest:
      mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_MAXIMUM,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD)
    case .darkest:
      mode = SDL_ComposeCustomBlendMode(
        SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_MINIMUM,
        SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD)
    case .darken:
      mode = SDL_BLENDMODE_MUL
    default:
      mode = SDL_BLENDMODE_BLEND
    }
    return .init(rawValue: SDLBlendMode.RawValue(mode))
  }

  /// Mask ink: the next cast member's artwork is the stencil. Dark mask
  /// pixels keep the sprite, light ones clear it — Director's 1-bit mask
  /// convention — sampled at each sprite pixel, so a mask smaller than the
  /// artwork clips to its own extent.
  private func applyMaskMember(
    to rgba: inout [UInt8], member: CastMember, properties: BitmapMemberProperties
  ) {
    let width = properties.bounds.width
    let height = properties.bounds.height
    guard
      let maskMember = movie.castManager.library(number: member.libraryNumber)?
        .member(member.memberNumber + 1),
      let maskProperties = maskMember.chunk.bitmapProperties,
      let mask = maskMember.rgba(ink: .copy, backColorIndex: 0)
    else { return }
    let maskWidth = maskProperties.bounds.width
    let maskHeight = maskProperties.bounds.height
    for y in 0..<height {
      for x in 0..<width {
        let index = y * width + x
        guard x < maskWidth, y < maskHeight else {
          rgba[index * 4 + 3] = 0
          continue
        }
        let maskIndex = (y * maskWidth + x) * 4
        let luminance =
          Int(mask[maskIndex]) + Int(mask[maskIndex + 1]) + Int(mask[maskIndex + 2])
        if luminance >= 3 * 128 { rgba[index * 4 + 3] = 0 }
      }
    }
  }

}
