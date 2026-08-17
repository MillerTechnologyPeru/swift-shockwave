import CoreGraphics
import CoreText
import Foundation
import ShockwaveFile

/// Rasterizes a text member's string into RGBA8888 pixels for an SDL
/// texture, via CoreText.
///
/// A stand-in for real Director text: the member's leading font and size
/// are honored (from its `XMED` styling), but every run gets that one face,
/// and fonts embedded in the movie (Director marks them with a trailing
/// ` *`, like junkbot's `04b_08 *`) can't be used until the `PFR1` font
/// resources are rasterized — those fall back to a system face at the
/// same size, drawn without anti-aliasing to keep the pixel-font look.
enum TextRasterizer {
  /// Renders `text` into a `width`×`height` RGBA buffer, top-aligned and
  /// wrapped to the width, transparent background. Returns `nil` for empty
  /// text or degenerate sizes.
  static func rgba(
    text: String,
    width: Int,
    height: Int,
    color: PaletteChunk.Color,
    fontName: String? = nil,
    fontSize: Double
  ) -> [UInt8]? {
    guard width > 0, height > 0, !text.isEmpty else { return nil }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let (font, isEmbedded) = resolveFont(named: fontName, size: fontSize)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      if isEmbedded {
        context.setShouldAntialias(false)
        context.setShouldSmoothFonts(false)
      }

      let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(
          red: Double(color.red) / 255, green: Double(color.green) / 255,
          blue: Double(color.blue) / 255, alpha: 1),
      ]
      // Director's line separator is \r, which CoreText already treats as a
      // line break.
      let attributed = CFAttributedStringCreate(
        nil, text as CFString, attributes as CFDictionary)!
      let framesetter = CTFramesetterCreateWithAttributedString(attributed)
      let path = CGPath(
        rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
      let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: 0, length: 0), path, nil)
      CTFrameDraw(frame, context)
      return true
    }
    return drawn ? pixels : nil
  }

  /// The CoreText font for a Director font name, and whether that name
  /// denoted a font embedded in the movie. Installed families resolve by
  /// name; embedded ones (trailing ` *`) try the bare name and otherwise
  /// take a compact system face; anything else is Helvetica.
  private static func resolveFont(named name: String?, size: Double) -> (CTFont, Bool) {
    guard let name, !name.isEmpty else {
      return (CTFontCreateWithName("Helvetica" as CFString, size, nil), false)
    }
    let isEmbedded = name.hasSuffix("*")
    let bareName = isEmbedded ? String(name.dropLast()).trimmingCharacters(in: .whitespaces) : name
    if let installed = installedFont(named: bareName, size: size) {
      return (installed, isEmbedded)
    }
    if isEmbedded {
      // No rasterizer for the movie's own font yet: a compact face keeps
      // the layout close, and the caller draws it un-smoothed.
      let fallback = installedFont(named: "Verdana", size: size)
        ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
      return (fallback, true)
    }
    return (CTFontCreateWithName("Helvetica" as CFString, size, nil), false)
  }

  /// A font only if a family of that name is actually installed —
  /// `CTFontCreateWithName` otherwise silently hands back a substitute.
  private static func installedFont(named name: String, size: Double) -> CTFont? {
    let font = CTFontCreateWithName(name as CFString, size, nil)
    let family = CTFontCopyFamilyName(font) as String
    let postScript = CTFontCopyPostScriptName(font) as String
    let wanted = name.lowercased()
    guard family.lowercased() == wanted || postScript.lowercased().hasPrefix(wanted) else {
      return nil
    }
    return font
  }
}
