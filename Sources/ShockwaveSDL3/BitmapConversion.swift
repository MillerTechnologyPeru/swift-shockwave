import Foundation
import ShockwaveFile

/// Converts decoded `BITD` pixel rows into RGBA8888 (byte order R,G,B,A)
/// for SDL textures.
enum BitmapConversion {
  /// - Parameter transparentWhite: substitute for background-transparent
  ///   and matte inks until real ink compositing exists — pixels matching
  ///   the palette's white (or pure white in direct color) become clear.
  static func rgba(
    pixels: [UInt8],
    properties: BitmapMemberProperties,
    palette: [PaletteChunk.Color],
    transparentWhite: Bool
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
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let bit = (pixels[row + x / 8] >> (7 - x % 8)) & 1
          if bit == 1 {
            write(x, y, 0, 0, 0, 255)
          } else {
            write(x, y, 255, 255, 255, transparentWhite ? 0 : 255)
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
          let clear =
            transparentWhite && color.red == 255 && color.green == 255 && color.blue == 255
          write(x, y, color.red, color.green, color.blue, clear ? 0 : 255)
        }
      }
    case 16:
      // Big-endian X1R5G5B5.
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let value = UInt16(pixels[row + x * 2]) << 8 | UInt16(pixels[row + x * 2 + 1])
          let r = UInt8((value >> 10) & 0x1F) << 3
          let g = UInt8((value >> 5) & 0x1F) << 3
          let b = UInt8(value & 0x1F) << 3
          let clear = transparentWhite && r >= 0xF8 && g >= 0xF8 && b >= 0xF8
          write(x, y, r, g, b, clear ? 0 : 255)
        }
      }
    case 32:
      // Rows are channel-planar: alpha, red, green, blue.
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let r = pixels[row + width + x]
          let g = pixels[row + width * 2 + x]
          let b = pixels[row + width * 3 + x]
          write(x, y, r, g, b, 255)
        }
      }
    default:
      return nil
    }
    return output
  }
}
