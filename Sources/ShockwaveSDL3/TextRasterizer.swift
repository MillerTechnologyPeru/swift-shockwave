import CoreGraphics
import CoreText
import Foundation
import ShockwaveFile

/// Rasterizes a text member's string into RGBA8888 pixels for an SDL
/// texture, via CoreText.
///
/// A placeholder for real Director text: every run gets one face and size
/// (the `STXT`/`XMED` style runs aren't decoded yet), anti-aliased rather
/// than bitmap-font crisp. It exists so fields and runtime-set `.text`
/// members appear at all.
enum TextRasterizer {
  /// Renders `text` into a `width`×`height` RGBA buffer, top-aligned and
  /// wrapped to the width, transparent background. Returns `nil` for empty
  /// text or degenerate sizes.
  static func rgba(
    text: String,
    width: Int,
    height: Int,
    color: PaletteChunk.Color,
    fontSize: Double
  ) -> [UInt8]? {
    guard width > 0, height > 0, !text.isEmpty else { return nil }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }

      let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
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
}
