import Foundation
import ShockwaveFile

/// Draws text set in a font the movie carries with it (`PFRFont`).
///
/// Director movies that ship a font expect its exact artwork — the sample's
/// UI is set in a pixel font whose letters are five pixels tall — so the
/// glyph outlines are filled here rather than handed to the system's text
/// engine with a lookalike face. Filling is a plain even-odd scan with no
/// anti-aliasing, which is what makes a pixel font come out crisp: at its
/// design size every edge lands on a pixel boundary.
///
/// Layout is Director's: lines break on the member's own line breaks and
/// wrap at word boundaries, `fixedLineSpace` sets the pitch when the member
/// asks for one, and the text sits left, centred or right within the width.
public enum EmbeddedTextRasterizer {
  /// One pixel's worth of coverage: true where a glyph paints.
  public typealias Mask = [Bool]

  /// Renders `text` into a `width`×`height` coverage mask.
  public static func mask(
    text: String, font: PFRFont, size: Int, width: Int, height: Int, fixedLineSpace: Int,
    alignment: String
  ) -> Mask? {
    guard width > 0, height > 0, size > 0, !text.isEmpty else { return nil }
    var mask = Mask(repeating: false, count: width * height)
    let lines = layout(text: text, font: font, size: size, width: width)
    let pitch = lineHeight(font: font, size: size, fixedLineSpace: fixedLineSpace)
    let ascent = scale(font.ascent, font: font, size: size)
    for (index, line) in lines.enumerated() {
      let baseline = index * pitch + ascent
      guard baseline - ascent < height else { break }
      var pen = origin(of: line, font: font, size: size, width: width, alignment: alignment)
      for character in line.unicodeScalars {
        let code = Int(character.value)
        if let glyph = font.glyphs[code] {
          fill(glyph: glyph, at: pen, baseline: baseline, font: font, size: size,
            width: width, height: height, into: &mask)
          pen += advance(glyph.advance, font: font, size: size)
        } else {
          pen += size / 2
        }
      }
    }
    return mask
  }

  /// The height `text` needs at `width` — what an auto-sizing text sprite
  /// grows to.
  public static func height(
    text: String, font: PFRFont, size: Int, width: Int, fixedLineSpace: Int
  ) -> Int {
    guard width > 0, size > 0, !text.isEmpty else { return 0 }
    let lines = layout(text: text, font: font, size: size, width: width)
    return lines.count * lineHeight(font: font, size: size, fixedLineSpace: fixedLineSpace)
  }

  /// The width `text` occupies on one line.
  public static func width(of text: String, font: PFRFont, size: Int) -> Int {
    text.unicodeScalars.reduce(0) { total, character in
      guard let glyph = font.glyphs[Int(character.value)] else { return total + size / 2 }
      return total + advance(glyph.advance, font: font, size: size)
    }
  }

  // MARK: - Layout

  /// Splits `text` into drawn lines: the member's own breaks, each wrapped
  /// to `width` at word boundaries (and mid-word only when a single word
  /// is wider than the box).
  private static func layout(text: String, font: PFRFont, size: Int, width: Int) -> [String] {
    var lines: [String] = []
    // Director's line separator is a carriage return; movies authored on
    // either platform can also carry newlines.
    for paragraph in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
      var line = ""
      for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
        let candidate = line.isEmpty ? String(word) : line + " " + word
        if self.width(of: candidate, font: font, size: size) <= width || line.isEmpty {
          line = candidate
          continue
        }
        lines.append(line)
        line = String(word)
      }
      lines.append(line)
    }
    return lines
  }

  private static func lineHeight(font: PFRFont, size: Int, fixedLineSpace: Int) -> Int {
    if fixedLineSpace > 0 { return fixedLineSpace }
    let natural = scale(font.ascent + font.descent, font: font, size: size)
    return max(natural, size)
  }

  private static func origin(
    of line: String, font: PFRFont, size: Int, width: Int, alignment: String
  ) -> Int {
    switch alignment {
    case "center": return max(0, (width - self.width(of: line, font: font, size: size)) / 2)
    case "right": return max(0, width - self.width(of: line, font: font, size: size))
    default: return 0
    }
  }

  /// Outline units to pixels.
  private static func scale(_ value: Int, font: PFRFont, size: Int) -> Int {
    Int((Double(value) * Double(size) / Double(font.outlineResolution)).rounded())
  }

  /// Metrics units to pixels — a font measures advances against its own
  /// resolution, which needn't be the outline one.
  private static func advance(_ value: Int, font: PFRFont, size: Int) -> Int {
    Int((Double(value) * Double(size) / Double(font.metricsResolution)).rounded())
  }

  // MARK: - Filling

  /// Scan-converts one glyph. A pixel belongs to the glyph when its centre
  /// is inside an odd number of contours, so a counter (the hole in an
  /// `o`) drops out however the contours wind.
  private static func fill(
    glyph: PFRFont.Glyph, at pen: Int, baseline: Int, font: PFRFont, size: Int, width: Int,
    height: Int, into mask: inout Mask
  ) {
    guard !glyph.shapes.isEmpty else { return }
    for shape in glyph.shapes {
      fill(
        shape: shape, at: pen, baseline: baseline, font: font, size: size, width: width,
        height: height, into: &mask)
    }
  }

  /// Scan-converts one piece of a glyph, painting where its own contours
  /// enclose a pixel centre. Pieces are drawn one after another, so where
  /// two overlap the ink stays put.
  private static func fill(
    shape: PFRFont.Shape, at pen: Int, baseline: Int, font: PFRFont, size: Int, width: Int,
    height: Int, into mask: inout Mask
  ) {
    let scale = Double(size) / Double(font.outlineResolution)
    // Device space: x grows right from the pen, y grows down from the
    // baseline, so the outline's y is negated.
    var polygons: [[(x: Double, y: Double)]] = []
    var minimumY = Double.greatestFiniteMagnitude
    var maximumY = -Double.greatestFiniteMagnitude
    var minimumX = Double.greatestFiniteMagnitude
    var maximumX = -Double.greatestFiniteMagnitude
    for contour in shape.contours {
      var polygon: [(x: Double, y: Double)] = []
      polygon.reserveCapacity(contour.count)
      for point in contour {
        // Snapped to whole pixels, which is what hinting a font to the
        // grid amounts to for artwork drawn on one: every edge lands on a
        // pixel boundary, so stems come out an even width instead of
        // straddling and thinning at some sizes.
        let x = (Double(pen) + Double(point.x) * scale).rounded()
        let y = (Double(baseline) - Double(point.y) * scale).rounded()
        polygon.append((x, y))
        minimumX = Swift.min(minimumX, x)
        maximumX = Swift.max(maximumX, x)
        minimumY = Swift.min(minimumY, y)
        maximumY = Swift.max(maximumY, y)
      }
      polygons.append(polygon)
    }
    let firstRow = Swift.max(0, Int(minimumY.rounded(.down)))
    let lastRow = Swift.min(height - 1, Int(maximumY.rounded(.up)))
    let firstColumn = Swift.max(0, Int(minimumX.rounded(.down)))
    let lastColumn = Swift.min(width - 1, Int(maximumX.rounded(.up)))
    guard firstRow <= lastRow, firstColumn <= lastColumn else { return }

    for row in firstRow...lastRow {
      let y = Double(row) + 0.5
      // Where this scanline crosses the outline; pairs of crossings
      // bracket the painted spans.
      var crossings: [Double] = []
      for polygon in polygons {
        for index in polygon.indices {
          let a = polygon[index]
          let b = polygon[(index + 1) % polygon.count]
          guard (a.y > y) != (b.y > y) else { continue }
          crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
        }
      }
      guard crossings.count > 1 else { continue }
      crossings.sort()
      // A span covers the pixels whose centres fall inside it.
      var index = 0
      while index + 1 < crossings.count {
        let start = Swift.max(firstColumn, Int((crossings[index] - 0.5).rounded(.up)))
        let end = Swift.min(lastColumn, Int((crossings[index + 1] - 0.5).rounded(.up)) - 1)
        if start <= end {
          for column in start...end { mask[row * width + column] = true }
        }
        index += 2
      }
    }
  }
}
