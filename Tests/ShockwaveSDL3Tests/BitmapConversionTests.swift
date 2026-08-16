import Foundation
import ShockwaveFile
import Testing

@testable import ShockwaveSDL3

/// 8-bit test palette: index 0 white, index 1 black, index 2 red.
private let testPalette: [PaletteChunk.Color] = [
  PaletteChunk.Color(red: 255, green: 255, blue: 255),
  PaletteChunk.Color(red: 0, green: 0, blue: 0),
  PaletteChunk.Color(red: 255, green: 0, blue: 0),
]

private func properties(width: Int, height: Int, bitsPerPixel: Int = 8) -> BitmapMemberProperties {
  BitmapMemberProperties(
    rowBytes: bitsPerPixel == 8 ? width : width * bitsPerPixel / 8,
    bounds: DirectorRect(top: 0, left: 0, bottom: height, right: width),
    regY: 0, regX: 0, bitsPerPixel: bitsPerPixel,
    paletteCastLib: -1, paletteMember: -1)
}

private func alpha(_ rgba: [UInt8], _ x: Int, _ y: Int, width: Int) -> UInt8 {
  rgba[(y * width + x) * 4 + 3]
}

/// A 5×5 black ring on white: the white border is edge-connected, the
/// single white center pixel is enclosed by artwork.
///
///     0 0 0 0 0
///     0 1 1 1 0
///     0 1 0 1 0
///     0 1 1 1 0
///     0 0 0 0 0
private let ring: [UInt8] = [
  0, 0, 0, 0, 0,
  0, 1, 1, 1, 0,
  0, 1, 0, 1, 0,
  0, 1, 1, 1, 0,
  0, 0, 0, 0, 0,
]

@Test func matteClearsOnlyEdgeConnectedBackground() throws {
  let rgba = try #require(
    BitmapConversion.rgba(
      pixels: ring, properties: properties(width: 5, height: 5), palette: testPalette,
      ink: .matte, backColorIndex: 0, sourcePlanar: false))
  // Exterior white is keyed out...
  #expect(alpha(rgba, 0, 0, width: 5) == 0)
  #expect(alpha(rgba, 4, 4, width: 5) == 0)
  #expect(alpha(rgba, 0, 2, width: 5) == 0)
  // ...the ring itself stays opaque...
  #expect(alpha(rgba, 1, 1, width: 5) == 255)
  #expect(alpha(rgba, 2, 1, width: 5) == 255)
  // ...and so does the enclosed white center, matte's defining behavior.
  #expect(alpha(rgba, 2, 2, width: 5) == 255)
}

@Test func backgroundTransparentClearsEnclosedPixelsToo() throws {
  let rgba = try #require(
    BitmapConversion.rgba(
      pixels: ring, properties: properties(width: 5, height: 5), palette: testPalette,
      ink: .backgroundTransparent, backColorIndex: 0, sourcePlanar: false))
  #expect(alpha(rgba, 0, 0, width: 5) == 0)
  #expect(alpha(rgba, 2, 2, width: 5) == 0)
  #expect(alpha(rgba, 1, 1, width: 5) == 255)
}

@Test func copyKeepsEveryPixelOpaque() throws {
  let rgba = try #require(
    BitmapConversion.rgba(
      pixels: ring, properties: properties(width: 5, height: 5), palette: testPalette,
      ink: .copy, backColorIndex: 0, sourcePlanar: false))
  for y in 0..<5 {
    for x in 0..<5 {
      #expect(alpha(rgba, x, y, width: 5) == 255)
    }
  }
}

@Test func matteKeysWhiteNotBackColor() throws {
  // backColor names red (index 2); matte must still key against white.
  let pixels: [UInt8] = [
    0, 0, 0,
    0, 1, 2,
    0, 0, 0,
  ]
  let rgba = try #require(
    BitmapConversion.rgba(
      pixels: pixels, properties: properties(width: 3, height: 3), palette: testPalette,
      ink: .matte, backColorIndex: 2, sourcePlanar: false))
  #expect(alpha(rgba, 0, 0, width: 3) == 0)
  #expect(alpha(rgba, 1, 1, width: 3) == 255)
  // The red pixel is not the matte key even though it's the backColor.
  #expect(alpha(rgba, 2, 1, width: 3) == 255)
}

@Test func inkNumberMapping() {
  #expect(SpriteInk(inkNumber: 0) == .copy)
  #expect(SpriteInk(inkNumber: 8) == .matte)
  #expect(SpriteInk(inkNumber: 36) == .backgroundTransparent)
  // Unimplemented inks fall back to background transparent.
  #expect(SpriteInk(inkNumber: 3) == .backgroundTransparent)
}
