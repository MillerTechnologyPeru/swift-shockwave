import Foundation
import ShockwaveFile
import ShockwaveTestSupport
import Testing

/// The font the sample carries with it: a `PFR1` resource in a font cast
/// member's media.
private func junkbotFont() throws -> PFRFont {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  guard let keyTable = try file.keyTable() else { throw PFRFontTestError.noFont }
  for entry in keyTable.entries where entry.fourCC == "XMED" {
    let data = try file.chunkData(at: file.chunkMap[entry.childChunkIndex])
    if let font = PFRFont(data: data) { return font }
  }
  throw PFRFontTestError.noFont
}

private enum PFRFontTestError: Error { case noFont }

/// Draws a glyph on the font's own design grid — the sample's face is a
/// pixel font drawn in sixths of the em, so one cell per sixth is exactly
/// its artwork.
private func render(_ glyph: PFRFont.Glyph, font: PFRFont, columns: Int = 6, rows: Int = 6)
  -> [String]
{
  let unit = Double(font.outlineResolution) / 6
  return (0..<rows).reversed().map { row in
    String(
      (0..<columns).map { column -> Character in
        let x = Double(column) * unit + unit / 2
        let y = Double(row) * unit + unit / 2
        var crossings = 0
        for contour in glyph.contours {
          for index in contour.indices {
            let a = contour[index]
            let b = contour[(index + 1) % contour.count]
            guard (Double(a.y) > y) != (Double(b.y) > y) else { continue }
            let t = (y - Double(a.y)) / Double(b.y - a.y)
            if Double(a.x) + t * Double(b.x - a.x) > x { crossings += 1 }
          }
        }
        return crossings % 2 == 1 ? "#" : "."
      })
  }
}

@Test func embeddedFontDescribesItself() throws {
  let font = try junkbotFont()
  #expect(font.familyName == "04b_08 *")
  #expect(font.outlineResolution == 2048)
  #expect(font.metricsResolution == 2048)
  // Caps stand five sixths of the em tall, on a baseline at zero.
  #expect(font.ascent == 1707)
  #expect(font.descent == 0)
  // Every printable ASCII character, plus a non-breaking space.
  #expect(font.glyphs.count == 97)
  #expect(Set(32...126).isSubset(of: Set(font.glyphs.keys)))
  // Only the two spaces draw nothing.
  #expect(font.glyphs.filter { $0.value.contours.isEmpty }.keys.sorted() == [32, 160])
  // A proportional font: `!` is a third the width of `A`.
  #expect(font.glyphs[65]?.advance == 2048)
  #expect(font.glyphs[33]?.advance == 683)
}

/// Glyphs whose outline is written out directly.
@Test func simpleGlyphsDecodeToTheirArtwork() throws {
  let font = try junkbotFont()
  #expect(
    render(try #require(font.glyphs[65]), font: font) == [
      "......",
      "#####.",
      "#...#.",
      "#####.",
      "#...#.",
      "#...#.",
    ])
  #expect(
    render(try #require(font.glyphs[111]), font: font) == [
      "......",
      "#####.",
      "#...#.",
      "#...#.",
      "#...#.",
      "#####.",
    ])
  // Lowercase repeats the capitals: this face has one case.
  #expect(font.glyphs[97]?.contours.map { $0.map(\.x) } == font.glyphs[65]?.contours.map { $0.map(\.x) })
}

/// Glyphs built by placing scaled copies of other glyphs — how this font
/// draws dots, bars and the stair-steps of a diagonal.
@Test func compoundGlyphsPlaceTheirComponents() throws {
  let font = try junkbotFont()
  #expect(
    render(try #require(font.glyphs[86]), font: font) == [
      "......",
      "#...#.",
      "#...#.",
      "#...#.",
      ".#.#..",
      "..#...",
    ])
  #expect(
    render(try #require(font.glyphs[61]), font: font) == [
      "......",
      "......",
      "#####.",
      "......",
      "#####.",
      "......",
    ])
  #expect(
    render(try #require(font.glyphs[90]), font: font) == [
      "......",
      "#####.",
      "...#..",
      "..#...",
      ".#....",
      "#####.",
    ])
}
