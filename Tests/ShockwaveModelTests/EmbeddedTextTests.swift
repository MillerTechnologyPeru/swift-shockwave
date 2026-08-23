import Foundation
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

private func junkbotMovie() throws -> Movie {
  try Movie.load(from: RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL)))
}

/// Renders a mask as text, one character per pixel, trimmed to the rows
/// that have something in them.
private func lines(_ mask: [Bool], width: Int) -> [String] {
  let rows: [String] = stride(from: 0, to: mask.count, by: width)
    .map { row in String(mask[row..<(row + width)].map { $0 ? "#" : "." }) }
  guard let first = rows.firstIndex(where: { $0.contains("#") }),
    let last = rows.lastIndex(where: { $0.contains("#") })
  else { return [] }
  return Array(rows[first...last])
}

/// The movie carries the face its interface is set in, so it is loaded
/// with the cast and found by the name the text members' styling gives.
@Test func fontMembersCarryTheirTypeface() throws {
  let movie = try junkbotMovie()
  let member = try #require(movie.castManager.member(named: "04b_08 *"))
  #expect(member.embeddedFont != nil)
  #expect(movie.castManager.embeddedFont(named: "04b_08 *") != nil)
  #expect(movie.castManager.embeddedFont(named: "Arial") == nil)
  // The loading screen's caption is set in it — that is what makes this
  // font worth carrying.
  let caption = try #require(movie.castManager.member(named: "download_msg"))
  #expect(caption.textLayout.fontName == "04b_08 *")
  #expect(caption.textLayout.fontSize == 10)
}

/// Text is drawn from the font's own outlines, filled without smoothing,
/// so a pixel font comes out as the artwork its designer drew.
@Test func embeddedTextDrawsTheFontsOwnPixels() throws {
  let movie = try junkbotMovie()
  let font = try #require(movie.castManager.embeddedFont(named: "04b_08 *"))
  let mask = try #require(
    EmbeddedTextRasterizer.mask(
      text: "HI!", font: font, size: 6, width: 20, height: 10, fixedLineSpace: 0,
      alignment: "left"))
  #expect(
    lines(mask, width: 20) == [
      "#...#.###.#.........",
      "#...#..#..#.........",
      "#####..#..#.........",
      "#...#..#............",
      "#...#.###.#.........",
    ])
}

/// Lines break where the member says and wrap at word boundaries, and the
/// text sits where the alignment puts it.
@Test func embeddedTextLaysOutLikeDirector() throws {
  let movie = try junkbotMovie()
  let font = try #require(movie.castManager.embeddedFont(named: "04b_08 *"))
  // Four characters at four pixels apiece.
  #expect(EmbeddedTextRasterizer.width(of: "IIII", font: font, size: 6) == 16)

  // Too wide for the box, so it wraps onto a second line, which the fixed
  // pitch places seven pixels down.
  let wrapped = try #require(
    EmbeddedTextRasterizer.mask(
      text: "II II", font: font, size: 6, width: 12, height: 20, fixedLineSpace: 7,
      alignment: "left"))
  #expect(lines(wrapped, width: 12).count == 12)

  // Right alignment pushes a short line to the far edge.
  let right = try #require(
    EmbeddedTextRasterizer.mask(
      text: "I", font: font, size: 6, width: 12, height: 10, fixedLineSpace: 0,
      alignment: "right"))
  let painted = lines(right, width: 12)
  #expect(!painted.isEmpty)
  #expect(painted.allSatisfy { $0.hasPrefix("........") })

  // A fixed line pitch is the pitch, whatever the glyphs need.
  #expect(
    EmbeddedTextRasterizer.height(
      text: "A\rB\rC", font: font, size: 6, width: 40, fixedLineSpace: 21) == 63)
}
