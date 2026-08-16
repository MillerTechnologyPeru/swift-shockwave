import Foundation
import ShockwaveFile

/// Converts decoded `BITD` pixel rows into RGBA8888 (byte order R,G,B,A)
/// for SDL textures.
enum BitmapConversion {
  /// - Parameters:
  ///   - ink: how the keyed pixels are treated. `.copy` composites every
  ///     pixel opaque; `.backgroundTransparent` clears every keyed pixel;
  ///     `.matte` clears only the keyed region connected to the bitmap's
  ///     edges; `.ghost` clears keyed pixels and inverts the rest.
  ///   - backColorIndex: the sprite record's own `backColor` — the palette
  ///     index Director keys transparency against for indexed bitmaps, and
  ///     the same key for all three transparent inks. Ignored for
  ///     direct-color depths (16/32-bit), where near-white is keyed instead
  ///     since there is no palette index to compare; that remains an
  ///     approximation pending real matte/mask support.
  ///   - sourcePlanar: whether the 16-bit source stores each row as two
  ///     separate byte planes (every high byte, then every low byte) rather
  ///     than interleaved high/low pairs per pixel. Byte-run-compressed BITD
  ///     chunks store 16-bit rows planar; raw/uncompressed ones store them
  ///     interleaved. Ignored for every other bit depth.
  static func rgba(
    pixels: [UInt8],
    properties: BitmapMemberProperties,
    palette: [PaletteChunk.Color],
    ink: SpriteInk,
    backColorIndex: Int,
    sourcePlanar: Bool
  ) -> [UInt8]? {
    let width = properties.bounds.width
    let height = properties.bounds.height
    let rowBytes = properties.rowBytes
    guard width > 0, height > 0, pixels.count >= rowBytes * height else { return nil }
    var output = [UInt8](repeating: 0, count: width * height * 4)
    // Pixels that match the ink's key color. For `.backgroundTransparent`
    // they all clear; for `.matte` only the edge-connected region clears.
    var keyed = [Bool](repeating: false, count: ink == .copy ? 0 : width * height)

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
      let keyBit = backColorIndex & 1
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let bit = Int((pixels[row + x / 8] >> (7 - x % 8)) & 1)
          if ink != .copy, bit == keyBit { keyed[y * width + x] = true }
          if bit == 1 {
            write(x, y, 0, 0, 0, 255)
          } else {
            write(x, y, 255, 255, 255, 255)
          }
        }
      }
    case 8:
      let keyIndex = backColorIndex
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let index = Int(pixels[row + x])
          guard index < palette.count else { continue }
          let color = palette[index]
          if ink != .copy, index == keyIndex { keyed[y * width + x] = true }
          write(x, y, color.red, color.green, color.blue, 255)
        }
      }
    case 16:
      // Big-endian X1R5G5B5. No indexed backColor to key against at this
      // depth; key near-white for both transparent inks.
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let high: UInt8
          let low: UInt8
          if sourcePlanar {
            // Compressed rows store every high byte, then every low byte.
            high = pixels[row + x]
            low = pixels[row + width + x]
          } else {
            high = pixels[row + x * 2]
            low = pixels[row + x * 2 + 1]
          }
          let value = UInt16(high) << 8 | UInt16(low)
          let r = UInt8((value >> 10) & 0x1F) << 3
          let g = UInt8((value >> 5) & 0x1F) << 3
          let b = UInt8(value & 0x1F) << 3
          if ink != .copy, r >= 0xF8, g >= 0xF8, b >= 0xF8 { keyed[y * width + x] = true }
          write(x, y, r, g, b, 255)
        }
      }
    case 32:
      // Rows are channel-planar: alpha, red, green, blue. The embedded
      // alpha wins; transparent inks additionally key near-white.
      for y in 0..<height {
        let row = y * rowBytes
        for x in 0..<width {
          let a = pixels[row + x]
          let r = pixels[row + width + x]
          let g = pixels[row + width * 2 + x]
          let b = pixels[row + width * 3 + x]
          if ink != .copy, r >= 0xF8, g >= 0xF8, b >= 0xF8 { keyed[y * width + x] = true }
          write(x, y, r, g, b, a)
        }
      }
    default:
      return nil
    }

    switch ink {
    case .copy:
      break
    case .backgroundTransparent:
      for index in 0..<keyed.count where keyed[index] {
        output[index * 4 + 3] = 0
      }
    case .matte:
      clearEdgeConnectedRegion(keyed: keyed, width: width, height: height, output: &output)
    case .ghost:
      for index in 0..<keyed.count {
        if keyed[index] {
          output[index * 4 + 3] = 0
        } else {
          output[index * 4] = 255 - output[index * 4]
          output[index * 4 + 1] = 255 - output[index * 4 + 1]
          output[index * 4 + 2] = 255 - output[index * 4 + 2]
        }
      }
    }
    return output
  }

  /// Matte ink's defining behavior: flood-fills inward from every keyed
  /// border pixel across 4-connected keyed neighbors, and clears the alpha
  /// of only that exterior region. Keyed pixels fully enclosed by artwork
  /// are never reached, so they stay opaque.
  private static func clearEdgeConnectedRegion(
    keyed: [Bool], width: Int, height: Int, output: inout [UInt8]
  ) {
    var visited = [Bool](repeating: false, count: width * height)
    var stack = [Int]()
    func seed(_ index: Int) {
      if keyed[index], !visited[index] {
        visited[index] = true
        stack.append(index)
      }
    }
    for x in 0..<width {
      seed(x)
      seed((height - 1) * width + x)
    }
    for y in 0..<height {
      seed(y * width)
      seed(y * width + width - 1)
    }
    while let index = stack.popLast() {
      output[index * 4 + 3] = 0
      let x = index % width
      let y = index / width
      if x > 0 { seed(index - 1) }
      if x < width - 1 { seed(index + 1) }
      if y > 0 { seed(index - width) }
      if y < height - 1 { seed(index + width) }
    }
  }
}
