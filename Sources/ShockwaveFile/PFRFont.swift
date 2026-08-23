import Foundation

/// A font embedded in a movie: Bitstream's Portable Font Resource, in the
/// `PFR1` shape Director burns into a font cast member (the member's
/// `XMED` chunk is the font file, `PFR1` and all).
///
/// A glyph is a rectilinear-or-curved outline expressed against two tables
/// of coordinates — every distinct x and y the outline touches — which the
/// drawing commands then step through. For a pixel font like the sample's
/// 04b_08 those tables are the design grid (sixths of the em here) and the
/// commands only ever step along it, so decoding them reproduces the
/// artwork exactly rather than approximating it.
///
/// The container follows the published PFR layout (a header, a logical
/// font directory, a physical font); what differs from the `PFR0` files
/// FreeType reads is the character table, which is delta-coded, and the
/// glyph programs, which are a nibble stream rather than bytes.
public struct PFRFont: Sendable {
  public struct Point: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
      self.x = x
      self.y = y
    }
  }

  /// One independently filled piece of a glyph: a point inside an odd
  /// number of its contours is painted, which is what puts the counter in
  /// an `o`.
  public struct Shape: Sendable {
    public var contours: [[Point]]

    public init(contours: [[Point]]) {
      self.contours = contours
    }
  }

  public struct Glyph: Sendable {
    /// How far the pen moves after drawing, in metrics units.
    public var advance: Int
    /// The pieces the glyph is drawn from, each filled on its own and
    /// then laid over the others. A glyph written out directly is one
    /// piece; one built from components is several, and they overlap —
    /// the stair-steps of a diagonal share corners with the stem they
    /// meet — so filling them together would punch holes where they
    /// cross.
    public var shapes: [Shape]

    /// Every contour of every piece, for measuring and inspection.
    public var contours: [[Point]] { shapes.flatMap(\.contours) }
  }

  /// Outline units per em — the scale `contours` are expressed in.
  public let outlineResolution: Int
  /// Metrics units per em — the scale `advance` is expressed in.
  public let metricsResolution: Int
  public let ascent: Int
  public let descent: Int
  public let familyName: String?
  public let glyphs: [Int: Glyph]

  public init?(data: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= 58, bytes[0] == 0x50, bytes[1] == 0x46, bytes[2] == 0x52,
      bytes[3] == 0x31
    else { return nil }
    let reader = Reader(bytes)

    // Header: signature(4) version(2) signature2(2) headerSize(2)
    // logDirSize(2) logDirOffset(2) logFontMaxSize(2) logFontSectionSize(3)
    // logFontSectionOffset(3) phyFontMaxSize(2) phyFontSectionSize(3)
    // phyFontSectionOffset(3) gpsMaxSize(2) gpsSectionSize(3)
    // gpsSectionOffset(3) …
    let logDirOffset = reader.u16(12)
    let gpsSectionOffset = reader.u24(35)

    // Logical font directory: a count, then (size, offset) per font. Only
    // the first is read — a Director font member holds one.
    guard let logCount = reader.u16Checked(logDirOffset), logCount > 0,
      let logSize = reader.u16Checked(logDirOffset + 2),
      let logOffset = reader.u24Checked(logDirOffset + 4), logSize >= 13
    else { return nil }
    // Logical font record: a 12-byte matrix, flags, optional stroke and
    // bold thicknesses, optional extra items, then the physical font.
    var cursor = logOffset + 12
    guard let logFlags = reader.u8Checked(cursor) else { return nil }
    cursor += 1
    if logFlags & 0x04 != 0 {
      cursor += logFlags & 0x08 != 0 ? 2 : 1
      if logFlags & 0x03 == 0 { cursor += 3 }  // miter limit
    }
    if logFlags & 0x10 != 0 {
      cursor += logFlags & 0x20 != 0 ? 2 : 1
    }
    if logFlags & 0x40 != 0 {
      guard let next = reader.skipExtraItems(at: cursor) else { return nil }
      cursor = next
    }
    guard let physOffset = reader.u24Checked(cursor + 2) else { return nil }

    // Physical font: reference number, the two resolutions, the bounding
    // box, then flags saying which of the following fields are present.
    var p = physOffset
    guard let outlineResolution = reader.u16Checked(p + 2),
      let metricsResolution = reader.u16Checked(p + 4), outlineResolution > 0,
      metricsResolution > 0
    else { return nil }
    self.outlineResolution = outlineResolution
    self.metricsResolution = metricsResolution
    let boxTop = reader.i16(p + 8)
    let boxBottom = reader.i16(p + 12)
    let flags = reader.u8(p + 14)
    p += 15
    var standardAdvance = 0
    if flags & 0x04 == 0 {  // fixed pitch: one advance for every glyph
      standardAdvance = reader.i16(p)
      p += 2
    }
    if flags & 0x80 != 0 {
      guard let next = reader.skipExtraItems(at: p) else { return nil }
      p = next
    }

    // Auxiliary records: the family name, and vertical metrics.
    var ascent = boxBottom
    var descent = -boxTop
    var familyName: String?
    guard let auxLength = reader.u24Checked(p) else { return nil }
    p += 3
    let auxEnd = p + auxLength
    var q = p
    while q + 4 <= auxEnd, q + 4 <= bytes.count {
      let length = reader.u16(q)
      guard length >= 4, q + length <= auxEnd else { break }
      switch reader.u16(q + 2) {
      case 1:
        let raw = bytes[(q + 4)..<(q + length)]
        familyName = String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
      case 2 where length >= 20:
        ascent = reader.i16(q + 14)
        descent = reader.i16(q + 16)
      default:
        break
      }
      q += length
    }
    p = auxEnd
    self.ascent = ascent
    self.descent = descent
    self.familyName = familyName

    // Blue values and standard stem widths, none of which matter without
    // hinting, then the character table.
    let blueCount = reader.u8(p)
    p += 1 + blueCount * 2 + 2 + 2 + 2
    let charCount = reader.u16(p)
    p += 2

    // The character table is delta-coded: a flag byte per entry says how
    // each field changes from the last. Codes always advance by at least
    // one, and a glyph's program usually follows the previous one, so most
    // entries are a byte or two.
    var glyphs: [Int: Glyph] = [:]
    var code = -1
    var advance = standardAdvance
    var programLength = 0
    var programOffset = 0
    for _ in 0..<charCount {
      guard let entry = reader.u8Checked(p) else { break }
      p += 1
      let nextOffset = programOffset + programLength
      code += 1
      switch entry & 0x03 {
      case 1:
        code += reader.u8(p)
        p += 1
      case 2:
        code += reader.u16(p)
        p += 2
      default:
        break
      }
      switch (entry >> 2) & 0x03 {
      case 1:
        advance += reader.u8(p)
        p += 1
      case 2:
        advance -= reader.u8(p)
        p += 1
      case 3:
        advance = reader.i16(p)
        p += 2
      default:
        break
      }
      switch (entry >> 4) & 0x03 {
      case 0:
        programLength = reader.u8(p)
        p += 1
      case 1:
        programLength = reader.u8(p) + 256
        p += 1
      case 2:
        programLength = reader.u8(p) + 512
        p += 1
      default:
        programLength = reader.u16(p)
        p += 2
      }
      switch (entry >> 6) & 0x03 {
      case 0:
        programOffset = nextOffset
      case 1:
        programOffset = nextOffset + reader.u8(p)
        p += 1
      case 2:
        programOffset = reader.u16(p)
        p += 2
      default:
        programOffset = reader.u24(p)
        p += 3
      }
      let shapes = Self.decodeGlyph(
        reader: reader, gpsSection: gpsSectionOffset, offset: programOffset,
        length: programLength, depth: 0)
      glyphs[code] = Glyph(advance: advance, shapes: shapes)
    }
    self.glyphs = glyphs
    guard !glyphs.isEmpty else { return nil }
  }

  /// Decodes the glyph program at `offset` in the glyph section.
  ///
  /// A program is either simple — coordinate tables and drawing commands —
  /// or compound, placing scaled copies of other programs. A pixel font
  /// leans on the latter: its dots, bars and the stair-steps that make up
  /// diagonals are all one shape reused at different scales and offsets.
  private static func decodeGlyph(
    reader: Reader, gpsSection: Int, offset: Int, length: Int, depth: Int
  ) -> [Shape] {
    let start = gpsSection + offset
    guard depth < 8, length > 0, start >= 0, start + length <= reader.bytes.count else {
      return []
    }
    let flags = reader.u8(start)
    // The top two bits are the outline format; when they say compound, the
    // remaining six are how many components follow.
    let componentCount = flags & 0x3F
    guard flags >> 6 >= 2, componentCount > 0 else {
      var program = GlyphProgram(reader: reader, start: start, end: start + length)
      let contours = program.run()
      return contours.isEmpty ? [] : [Shape(contours: contours)]
    }

    var position = start + 1
    if flags & 0x40 != 0, let next = reader.skipExtraItems(at: position) { position = next }
    // Components address their programs backwards from this one's, each
    // saying how far back and how long.
    var previousOffset = offset
    var shapes: [Shape] = []
    for _ in 0..<componentCount {
      guard position < start + length else { break }
      let format = reader.u8(position)
      position += 1
      let (xScale, xOffset) = transform(reader: reader, format: format % 6, position: &position)
      let (yScale, yOffset) = transform(
        reader: reader, format: (format / 6) % 6, position: &position)
      guard
        let (componentOffset, componentLength) = componentProgram(
          reader: reader, format: format / 36, position: &position, previous: &previousOffset)
      else { break }
      let component = decodeGlyph(
        reader: reader, gpsSection: gpsSection, offset: componentOffset,
        length: componentLength, depth: depth + 1)
      for shape in component {
        shapes.append(
          Shape(
            contours: shape.contours.map { contour in
              contour.map {
                Point(
                  x: $0.x * xScale / Self.scaleOne + xOffset,
                  y: $0.y * yScale / Self.scaleOne + yOffset)
              }
            }))
      }
    }
    return shapes
  }

  /// One axis of a component's placement: a scale in 1/4096ths and a
  /// translation, both optional and sized by the format.
  private static func transform(reader: Reader, format: Int, position: inout Int) -> (Int, Int) {
    var scale = scaleOne
    var offset = 0
    if format == 5 {
      scale = 0
    } else if format > 2 {
      scale = reader.u16(position)
      position += 2
    }
    if format == 0 || format == 5 {
      offset = 0
    } else if format == 1 || format == 3 {
      offset = reader.i8(position)
      position += 1
    } else {
      offset = reader.i16(position)
      position += 2
    }
    return (scale, offset)
  }

  /// Where a component's program is and how long it is.
  ///
  /// The first three formats walk backwards from where the last component
  /// started, so a run of components that sit next to each other costs a
  /// byte apiece; the rest give a distance or an address outright and
  /// leave that walking position alone.
  private static func componentProgram(
    reader: Reader, format: Int, position: inout Int, previous: inout Int
  ) -> (offset: Int, length: Int)? {
    switch format {
    case 0, 1, 2:
      let length: Int
      switch format {
      case 0:
        length = reader.u8(position)
        position += 1
      case 1:
        length = reader.u8(position) + 256
        position += 1
      default:
        length = reader.u16(position)
        position += 2
      }
      previous -= length
      return (previous, length)
    case 3:
      let packed = reader.u24(position)
      position += 3
      return (previous - (packed & 0x7FFF), packed >> 15)
    case 4:
      let packed = reader.u24(position)
      position += 3
      return (packed & 0x7FFF, packed >> 15)
    default:
      let packed =
        reader.u8(position) << 24 | reader.u8(position + 1) << 16 | reader.u8(position + 2) << 8
        | reader.u8(position + 3)
      position += 4
      return (packed & 0x7F_FFFF, (packed >> 23) & 0x1FF)
    }
  }

  /// A component scale of 1.0.
  private static let scaleOne = 4096

  /// Decodes one glyph program: the coordinate tables it draws against,
  /// then a nibble stream of drawing commands.
  private struct GlyphProgram {
    let reader: Reader
    let end: Int
    var position: Int
    /// True when the next nibble to read is the low half of `position`.
    var lowNibble = false
    var xControls: [Int] = []
    var yControls: [Int] = []
    var x = 0
    var y = 0
    var previousX = 0
    var previousY = 0
    var contours: [[Point]] = []
    var contour: [Point] = []

    init(reader: Reader, start: Int, end: Int) {
      self.reader = reader
      self.end = end
      position = start
    }

    mutating func run() -> [[Point]] {
      guard position < end else { return [] }
      let flags = reader.u8(position)
      position += 1
      readControls(flags: flags)
      if flags & 0x08 != 0, let next = reader.skipExtraItems(at: position) { position = next }

      // The first command is an implied move; the rest come from the
      // stream, two per byte.
      var command = 6
      var guardCount = (end - position) * 2 + 2
      while guardCount > 0 {
        guardCount -= 1
        switch command {
        case 0:
          step()
        case 1:
          moveBy(x: signedByte(), y: 0)
        case 2:
          moveBy(x: 0, y: signedByte())
        case 3:
          moveBy(x: wordDelta(), y: 0)
        case 4:
          moveBy(x: 0, y: wordDelta())
        case 5, 6:
          if command == 6 { closeContour() }
          movePen(to: encodedPair())
          if command == 6 {
            contour = [Point(x: x, y: y)]
          } else {
            contour.append(Point(x: x, y: y))
          }
        default:
          // Curve commands: the control points are read and the curve is
          // flattened to its endpoint, which is exact for the rectilinear
          // fonts Director embeds and an approximation otherwise.
          let points = (command - 6) / 3 + 1
          for _ in 0..<points { movePen(to: encodedPair()) }
          contour.append(Point(x: x, y: y))
        }
        guard let next = nibble(), position <= end else { break }
        command = next
      }
      closeContour()
      return contours
    }

    /// The two coordinate tables. Values are cumulative deltas, each
    /// either a byte or a twelve-bit value; which one is said by a flag
    /// bit — from the header for the first value on each axis, and from a
    /// packed stream of flag nibbles for the rest.
    private mutating func readControls(flags: Int) {
      var xCount = 0
      var yCount = 0
      switch flags & 0x03 {
      case 0:
        break
      case 1:
        let packed = reader.u8(position)
        position += 1
        xCount = packed & 0x0F
        yCount = packed >> 4
      default:
        xCount = reader.u8(position)
        yCount = reader.u8(position + 1)
        position += 2
      }
      guard xCount > 0 || yCount > 0 else { return }
      let wide = flags & 0x03 == 3
      let perValueFlags = flags & 0x40 != 0
      var flagCache = 0
      var flagsLeft = 0
      var aligned = false

      func nextIsWide(first: Bool, headerBit: Int) -> Bool {
        if first { return headerBit != 0 }
        guard perValueFlags else { return false }
        if flagsLeft > 0 {
          flagCache = (flagCache >> 1) & 0x7F
          flagsLeft -= 1
          return flagCache & 1 != 0
        }
        let byte = reader.u8(position)
        if aligned {
          flagCache = byte & 0x0F
          position += 1
          aligned = false
        } else {
          flagCache = byte >> 4
          aligned = true
        }
        flagsLeft = 3
        return flagCache & 1 != 0
      }

      func nextValue(wideValue: Bool) -> Int {
        if !wideValue {
          // A byte, which may straddle a nibble boundary.
          if aligned {
            let low = reader.u8(position) & 0x0F
            position += 1
            return low << 4 | reader.u8(position) >> 4
          }
          let value = reader.u8(position)
          position += 1
          return value
        }
        if wide {
          // Sixteen bits, again possibly straddling.
          if aligned {
            let low = reader.u8(position - 1) & 0x0F
            let middle = reader.u8(position)
            position += 1
            return Int(Int16(truncatingIfNeeded: low << 12 | middle << 4 | reader.u8(position) >> 4))
          }
          let high = reader.u8(position)
          position += 1
          let low = reader.u8(position)
          position += 1
          return Int(Int16(truncatingIfNeeded: high << 8 | low))
        }
        // Twelve bits: a signed byte of whole steps plus a nibble.
        if aligned {
          let low = reader.i8(position) << 4
          position += 1
          let value = reader.u8(position) + 16 * Int(Int8(truncatingIfNeeded: low))
          position += 1
          aligned = false
          return value
        }
        let high = reader.i8(position)
        position += 1
        aligned = true
        return reader.u8(position) >> 4 + 16 * high
      }

      var total = 0
      for index in 0..<xCount {
        let wideValue = nextIsWide(first: index == 0, headerBit: Int(flags >> 4) & 1)
        total &+= nextValue(wideValue: wideValue)
        xControls.append(total)
      }
      total = 0
      for index in 0..<yCount {
        let wideValue = nextIsWide(first: index == 0, headerBit: Int(flags >> 5) & 1)
        total &+= nextValue(wideValue: wideValue)
        yControls.append(total)
      }
      if aligned { position += 1 }
      lowNibble = false
    }

    // MARK: - Commands

    /// Steps to a neighbouring line of one coordinate table: the nibble
    /// says which table and how many lines, forward or back.
    private mutating func step() {
      guard let value = nibble() else { return }
      let distance = value & 4 != 0 ? (value & 7) - 8 : (value & 7) + 1
      if value & 8 != 0 {
        movePen(to: (x, lookup(yControls, from: y, previous: previousY, distance: distance)))
      } else {
        movePen(to: (lookup(xControls, from: x, previous: previousX, distance: distance), y))
      }
      contour.append(Point(x: x, y: y))
    }

    private mutating func moveBy(x deltaX: Int, y deltaY: Int) {
      movePen(to: (x + deltaX, y + deltaY))
      contour.append(Point(x: x, y: y))
    }

    /// A coordinate pair, each half either unchanged, a small relative
    /// nibble, a byte that is either a table step or a delta, or a wide
    /// delta.
    private mutating func encodedPair() -> (Int, Int) {
      guard let encoding = nibble() else { return (x, y) }
      var newX = x
      var newY = y
      let xEncoding = encoding & 3
      let yEncoding = (encoding >> 2) & 3
      if xEncoding != 0 {
        newX = coordinate(
          encoding: xEncoding, table: xControls, current: x, previous: previousX)
      }
      previousX = x
      x = newX
      if yEncoding != 0 {
        newY = coordinate(
          encoding: yEncoding, table: yControls, current: y, previous: previousY)
      }
      previousY = y
      y = newY
      return (newX, newY)
    }

    private mutating func coordinate(
      encoding: Int, table: [Int], current: Int, previous: Int
    ) -> Int {
      switch encoding {
      case 1:
        guard let value = nibble() else { return current }
        return current + value - 8
      case 2:
        let byte = signedByte()
        // Small values step along the table; larger ones are deltas.
        if byte >= -8, byte < 8 {
          return lookup(table, from: current, previous: previous, distance: byte >= 0 ? byte + 1 : byte)
        }
        return current + byte
      default:
        return current + wordDelta()
      }
    }

    /// Finds the table entry `distance` lines away from `current`.
    private func lookup(_ table: [Int], from current: Int, previous: Int, distance: Int) -> Int {
      guard !table.isEmpty else { return current }
      var distance = distance
      if distance == 0 {
        if current == previous { return current }
        distance = current < previous ? -1 : 1
      }
      if distance > 0 {
        guard let first = table.firstIndex(where: { $0 > current }) else { return current }
        return table[min(first + distance - 1, table.count - 1)]
      }
      guard let last = table.lastIndex(where: { $0 < current }) else { return current }
      return table[max(last + distance + 1, 0)]
    }

    private mutating func movePen(to point: (Int, Int)) {
      previousX = x
      previousY = y
      x = point.0
      y = point.1
    }

    private mutating func closeContour() {
      if contour.count > 2 { contours.append(contour) }
      contour = []
    }

    // MARK: - Reading

    private mutating func nibble() -> Int? {
      guard position < end else { return nil }
      lowNibble.toggle()
      if !lowNibble {
        let value = reader.u8(position) & 0x0F
        position += 1
        return value
      }
      return reader.u8(position) >> 4
    }

    /// A byte from the stream, which straddles two bytes when the reader
    /// is halfway through one.
    private mutating func byte() -> Int {
      guard position < end else { return 0 }
      if lowNibble {
        let low = reader.u8(position) & 0x0F
        position += 1
        return low << 4 | reader.u8(position) >> 4
      }
      let value = reader.u8(position)
      position += 1
      return value
    }

    private mutating func signedByte() -> Int {
      Int(Int8(truncatingIfNeeded: byte()))
    }

    /// A twelve-bit delta, widened to sixteen when it would fit in a byte
    /// (which the encoder uses to mean "there is another byte").
    private mutating func wordDelta() -> Int {
      let high = Int(Int8(truncatingIfNeeded: byte()))
      guard let low = nibble() else { return high << 4 }
      let delta = high << 4 | low
      guard delta >= -128, delta < 128 else { return delta }
      return delta << 8 | byte()
    }
  }

  /// Big-endian byte access over the resource.
  private final class Reader {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func u8(_ offset: Int) -> Int { offset >= 0 && offset < bytes.count ? Int(bytes[offset]) : 0 }
    func i8(_ offset: Int) -> Int { Int(Int8(truncatingIfNeeded: u8(offset))) }
    func u16(_ offset: Int) -> Int { u8(offset) << 8 | u8(offset + 1) }
    func i16(_ offset: Int) -> Int { Int(Int16(truncatingIfNeeded: u16(offset))) }
    func u24(_ offset: Int) -> Int { u8(offset) << 16 | u8(offset + 1) << 8 | u8(offset + 2) }
    func u8Checked(_ offset: Int) -> Int? { offset < bytes.count ? u8(offset) : nil }
    func u16Checked(_ offset: Int) -> Int? { offset + 2 <= bytes.count ? u16(offset) : nil }
    func u24Checked(_ offset: Int) -> Int? { offset + 3 <= bytes.count ? u24(offset) : nil }

    /// Steps over a table of extra items: a count, then each item's size,
    /// type and body.
    func skipExtraItems(at offset: Int) -> Int? {
      guard let count = u8Checked(offset) else { return nil }
      var position = offset + 1
      for _ in 0..<count {
        guard let size = u8Checked(position) else { return nil }
        position += 2 + size
      }
      return position <= bytes.count ? position : nil
    }
  }
}
