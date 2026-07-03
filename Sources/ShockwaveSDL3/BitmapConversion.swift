import Foundation
import ShockwaveFile

/// Converts decoded `BITD` pixel rows into RGBA8888 (byte order R,G,B,A)
/// for SDL textures.
enum BitmapConversion {
  /// - Parameters:
  ///   - transparent: whether this sprite's ink mode keys out a background
  ///     color (Director's "matte"/"background transparent" inks) rather
  ///     than compositing every pixel opaque ("copy").
  ///   - backColorIndex: the sprite record's own `backColor` — the palette
  ///     index Director actually keys transparency against for indexed
  ///     bitmaps, not necessarily white. Ignored for direct-color depths
  ///     (16/32-bit), where a plain white-detection heuristic is used
  ///     instead pending real matte/mask support.
  static func rgba(
    pixels: [UInt8],
    properties: BitmapMemberProperties,
    palette: [PaletteChunk.Color],
    transparent: Bool,
    backColorIndex: Int
  ) -> [UInt8]? {
    let width = properties.bounds.width
    let height = properties.bounds.height
    let rowBytes = properties.rowBytes
    guard width > 0, height > 0, pixels.count >= rowBytes * height else { return nil }
    var output = [UInt8](repeating: 0, count: width * height * 4)

    func write(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) {
      let base = (y * width + x) * 4
      output[base] = r
      output[base + 1] = g
      output[base + 2] = b
      output[base + 3] = a
    }

    switch properties.bitsPerPixel {
    case 1:
      // A 1-bit image's implicit 2-entry palette is {white, black} at
      // indices {0, 1}; key against whichever index backColor names.
      let backBit = backColorIndex & 1
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let bit = Int((pixels[row + x / 8] >> (7 - x % 8)) & 1)
          let clear = transparent && bit == backBit
          if bit == 1 {
            write(x, y, 0, 0, 0, clear ? 0 : 255)
          } else {
            write(x, y, 255, 255, 255, clear ? 0 : 255)
          }
        }
      }
    case 8:
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let index = Int(pixels[row + x])
          guard index < palette.count else { continue }
          let color = palette[index]
          let clear = transparent && index == backColorIndex
          write(x, y, color.red, color.green, color.blue, clear ? 0 : 255)
        }
      }
    case 16:
      // Big-endian X1R5G5B5. No indexed backColor to key against at this
      // depth; approximate with white-detection pending real matte/mask
      // support.
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let value = UInt16(pixels[row + x * 2]) << 8 | UInt16(pixels[row + x * 2 + 1])
          let r = UInt8((value >> 10) & 0x1F) << 3
          let g = UInt8((value >> 5) & 0x1F) << 3
          let b = UInt8(value & 0x1F) << 3
          let clear = transparent && r >= 0xF8 && g >= 0xF8 && b >= 0xF8
          write(x, y, r, g, b, clear ? 0 : 255)
        }
      }
    case 32:
      // Rows are channel-planar: alpha, red, green, blue.
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let a = pixels[row + x]
          let r = pixels[row + width + x]
          let g = pixels[row + width * 2 + x]
          let b = pixels[row + width * 3 + x]
          write(x, y, r, g, b, a)
        }
      }
    default:
      return nil
    }
    return output
  }
}
