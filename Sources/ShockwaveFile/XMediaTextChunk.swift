import Foundation

/// Plain-text extraction from an `XMED` chunk — the media payload of a text
/// xtra cast member (Director's rich-text engine, Paige).
///
/// The chunk is a sequence of sections, each headed by 20 bytes of ASCII
/// hex: a 4-digit section key, an 8-digit byte count, a 4-digit type, and a
/// 4-digit declared length, followed by exactly `count` bytes of payload.
/// The text itself lives in section `0x0002` (possibly split across several
/// such sections, concatenated in order), each payload shaped
/// `<hex length>,<text bytes>\x03`. Of the styling sections, only the font
/// table (`0x0008`) and the leading style's font and size (`0x0006`) are
/// read.
///
/// Validated against the junkbot sample's 122 `XMED` members — level
/// definitions, field text, and the loading screen's "READY TO PLAY" all
/// extract cleanly. The layout matches dirplayer-rs's independently
/// reverse-engineered parser.
public enum XMediaText {
  /// The concatenated text of every text section, or `nil` when `data`
  /// isn't styled-text media (fonts and 3D scenes ship as `XMED` too).
  public static func text(from data: Data) -> String? {
    guard let sections = sections(of: [UInt8](data)) else { return nil }
    let pieces = sections.filter { $0.key == 0x0002 }.map { textBlock($0.body) }
    guard !pieces.isEmpty else { return nil }
    return pieces.joined()
  }

  /// The typeface a text member is set in: the font and point size of the
  /// style its first style run selects.
  ///
  /// Only that one style is answered — the members this exists for (the
  /// sample's UI messages) are set in one font throughout. Per-run
  /// styling, colors and paragraph formats are left for a fuller Paige
  /// port.
  public struct Style: Equatable, Sendable {
    public var fontName: String
    public var fontSize: Int
    /// The first paragraph's fixed line pitch (`fixedLineSpace`), 0 when
    /// the font's own leading applies.
    public var fixedLineSpace: Int
    /// The first paragraph's alignment: `left`, `center` or `right`.
    public var alignment: String

    public init(
      fontName: String, fontSize: Int, fixedLineSpace: Int = 0, alignment: String = "left"
    ) {
      self.fontName = fontName
      self.fontSize = fontSize
      self.fixedLineSpace = fixedLineSpace
      self.alignment = alignment
    }
  }

  /// The font table of a styled-text `XMED` — every typeface the member's
  /// styles can refer to, in the order style records index them.
  public static func fontNames(from data: Data) -> [String] {
    guard let sections = sections(of: [UInt8](data)),
      let table = sections.first(where: { $0.key == 0x0008 })
    else { return [] }
    return fontNames(in: table.body)
  }

  /// Each font entry is a `<NUL><hex size>,<name>` block holding a Pascal
  /// string (length byte, then the name) padded with NULs to a fixed
  /// width, an optional second such block, then a packed properties
  /// record. Names are what we're after, so walk the section for
  /// size-prefixed blocks and keep the non-empty names.
  private static func fontNames(in bytes: ArraySlice<UInt8>) -> [String] {
    var names: [String] = []
    var index = bytes.startIndex
    while index < bytes.endIndex {
      guard bytes[index] == 0 else {
        index += 1
        continue
      }
      var cursor = index + 1
      var size = 0
      var digits = 0
      while cursor < bytes.endIndex, let digit = Character(UnicodeScalar(bytes[cursor])).hexDigitValue
      {
        size = size * 16 + digit
        digits += 1
        cursor += 1
      }
      guard digits > 0, cursor < bytes.endIndex, bytes[cursor] == UInt8(ascii: ","), size > 0,
        cursor + 1 + size <= bytes.endIndex
      else {
        index += 1
        continue
      }
      let block = bytes[(cursor + 1)..<(cursor + 1 + size)]
      let length = Int(block[block.startIndex])
      if length > 0, length < block.count {
        let raw = block[(block.startIndex + 1)..<(block.startIndex + 1 + length)]
        let name = String(decoding: raw, as: UTF8.self)
        if name.allSatisfy({ $0.isASCII && !$0.isNewline && $0 != "\0" }) {
          names.append(name)
        }
      }
      index = cursor + 1 + size
    }
    return names
  }

  /// The style the member's text is set in, or `nil` when the chunk isn't
  /// styled text or its style table can't be read.
  public static func style(from data: Data) -> Style? {
    let bytes = [UInt8](data)
    guard let sections = sections(of: bytes),
      let styleTable = sections.first(where: { $0.key == 0x0006 })
    else { return nil }
    let names = sections.first(where: { $0.key == 0x0008 }).map { fontNames(in: $0.body) } ?? []
    guard !names.isEmpty else { return nil }

    // The document header's first number is the Paige document version,
    // which decides which optional slots each style record carries.
    var version = 0
    if let header = sections.first(where: { $0.key == 0x0000 }) {
      var packer = Packer(bytes: header.body)
      version = packer.next()
    }
    let styles = styleRecords(in: styleTable.body, version: version)
    guard !styles.isEmpty else { return nil }

    // Style runs are (text offset, style index) pairs; the first run says
    // what the text starts in. Style 0 is Paige's template default.
    var chosen = 0
    if let runs = sections.first(where: { $0.key == 0x0004 }) {
      var packer = Packer(bytes: runs.body)
      _ = packer.next()  // offset 0
      let index = packer.next()
      if index >= 0, index < styles.count { chosen = index }
    }
    let record = styles[chosen]
    guard record.fontIndex >= 0, record.fontIndex < names.count, record.fontSize > 0,
      record.fontSize <= 200
    else { return nil }
    var style = Style(fontName: names[record.fontIndex], fontSize: record.fontSize)

    // Paragraph formats (key 0x0007) are chosen by the first paragraph run
    // (key 0x0005) the same way; they carry the fixed line pitch and the
    // alignment the level menu's number column is set with.
    if let table = sections.first(where: { $0.key == 0x0007 }) {
      let paragraphs = paragraphRecords(in: table.body, version: version)
      var index = 0
      if let runs = sections.first(where: { $0.key == 0x0005 }) {
        var packer = Packer(bytes: runs.body)
        _ = packer.next()
        let selected = packer.next()
        if selected >= 0, selected < paragraphs.count { index = selected }
      }
      if index < paragraphs.count {
        let paragraph = paragraphs[index]
        if paragraph.lineSpacing > 0, paragraph.lineSpacing < 1000 {
          style.fixedLineSpace = paragraph.lineSpacing
        }
        switch paragraph.justification {
        case 1: style.alignment = "center"
        case 2: style.alignment = "right"
        default: break
        }
      }
    }
    return style
  }

  private struct ParagraphRecord {
    var justification: Int
    var lineSpacing: Int
  }

  /// Walks Paige's packed `par_info` records, keeping the justification and
  /// line spacing; the rest is stepped over per Director's unpacker as
  /// documented by dirplayer-rs.
  private static func paragraphRecords(in bytes: ArraySlice<UInt8>, version: Int)
    -> [ParagraphRecord]
  {
    var packer = Packer(bytes: bytes)
    var records: [ParagraphRecord] = []
    while packer.remaining > 4, records.count < 32 {
      let start = packer.position
      let justification = packer.next()
      packer.skip(2)  // line height, box type
      packer.skip(3)  // indents
      packer.skip(2)  // border, margin
      let lineSpacing = packer.next()
      if version >= 65547 { packer.skip(1) }
      packer.skip(8)
      if version >= 65552 { packer.skip(1) }
      packer.skipRefcon(version: version)
      packer.skip(1 + 8)
      let tabCount = packer.next()
      if tabCount > 0 {
        for _ in 0..<min(tabCount, 32) {
          packer.skip(3)
          packer.skipRefcon(version: version)
        }
        if tabCount > 32 { packer.skip(tabCount - 32) }
      }
      if version >= 8 { packer.skip(1) }
      if version >= 65548 { packer.skip(1) }
      if version >= 65552 { packer.skip(4) }
      if version >= 65555 { packer.skip(1) }
      if version >= 131075 { packer.skip(9) }
      if version >= 131090 {
        packer.skip(5)
        if version >= 196614 { packer.skip(1) }
        if version >= 196615 { packer.skip(1) }
        if version >= 196616 { packer.skip(1) }
      }
      if packer.position == start { break }
      records.append(ParagraphRecord(justification: justification, lineSpacing: lineSpacing))
    }
    return records
  }

  /// The text member's own box: the width it wraps to and its height, from
  /// the document header — what a text sprite is sized from when the score
  /// record's size isn't authoritative (the sample's end-of-level messages
  /// sit in 23px score records that Director ignores in favor of the
  /// member's 300px box).
  public static func boxSize(from data: Data) -> (width: Int, height: Int)? {
    guard let sections = sections(of: [UInt8](data)),
      let header = sections.first(where: { $0.key == 0x0000 })
    else { return nil }
    var packer = Packer(bytes: header.body)
    let version = packer.next()
    // Only the Director 7-era layout (document version 0x40001) is known:
    // the box height sits at slot 10 and again at slot 28, the width right
    // after it at 29, ahead of the color triples. Other versions answer
    // nothing rather than a guess.
    guard version >= 0x40000, version < 0x50000 else { return nil }
    packer.skip(9)
    let height = packer.next()
    packer.skip(17)
    let heightAgain = packer.next()
    let width = packer.next()
    guard heightAgain == height, width > 0, width < 10000, height >= 0, height < 10000 else {
      return nil
    }
    return (width, height)
  }

  private struct StyleRecord {
    var fontIndex: Int
    var fontSize: Int
  }

  /// Walks Paige's packed `style_info` records: a count, then one record
  /// per style whose slot layout depends on the document version. The
  /// slots that matter here are the first (font index) and fourth (point
  /// size); the rest are stepped over so the next record lines up. The
  /// slot sequence follows Director's own unpacker as documented by
  /// dirplayer-rs.
  private static func styleRecords(in bytes: ArraySlice<UInt8>, version: Int) -> [StyleRecord] {
    var packer = Packer(bytes: bytes)
    _ = packer.next()  // declared count; the data is authoritative
    var records: [StyleRecord] = []
    while records.count < 100, packer.remaining > 4 {
      let fontIndex = packer.next()
      _ = packer.next()
      _ = packer.next()
      let fontSize = packer.next()
      records.append(StyleRecord(fontIndex: fontIndex, fontSize: fontSize))
      // word48 (wrap / HTML size class), four words, fore and back colors.
      packer.skip(1 + 4 + 4 + 4)
      if version < 65547 { packer.skip(1) }
      packer.skip(11)  // the fixed-point metrics block
      if version < 65547 { packer.skip(1) }
      if version >= 65551 { packer.skip(1) }
      packer.skipRefcon(version: version)
      packer.skip(1 + 8)
      packer.skip(version >= 257 ? 32 : 16)  // face flags
      if version >= 65536 { packer.skip(1) }
      if version >= 65552 { packer.skip(4) }
      if version >= 65555 { packer.skip(1) }
    }
    return records
  }

  private struct Section {
    var key: Int
    var body: ArraySlice<UInt8>
  }

  /// Splits the chunk into its sections, or `nil` when it lacks the
  /// styled-text `FFFF` lead-in.
  private static func sections(of bytes: [UInt8]) -> [Section]? {
    guard bytes.count >= 12,
      bytes[0] == UInt8(ascii: "F"), bytes[1] == UInt8(ascii: "F"),
      bytes[2] == UInt8(ascii: "F"), bytes[3] == UInt8(ascii: "F")
    else { return nil }
    var sections: [Section] = []
    var offset = 0
    while offset + 20 <= bytes.count {
      let header = bytes[offset..<(offset + 20)]
      guard header.allSatisfy(isASCIIHexDigit) else { break }
      guard let key = hexValue(bytes, offset, 4),
        let count = hexValue(bytes, offset + 4, 8)
      else { break }
      offset += 20
      let available = min(count, bytes.count - offset)
      sections.append(Section(key: key, body: bytes[offset..<(offset + available)]))
      offset += available
      if available < count { break }
    }
    return sections
  }

  /// Paige's packed-number stream: each value is a control byte followed
  /// by hex ASCII digits (with an optional leading `-`); a control byte
  /// with bit 7 set repeats the previous value instead, and bit 6 adds a
  /// repeat count. Only as much of the scheme as reading a style's leading
  /// fields needs.
  private struct Packer {
    let bytes: ArraySlice<UInt8>
    var position: Int
    private var lastValue = 0
    private var repeatCount = 0

    init(bytes: ArraySlice<UInt8>) {
      self.bytes = bytes
      position = bytes.startIndex
    }

    var remaining: Int { bytes.endIndex - position }

    mutating func skip(_ count: Int) {
      for _ in 0..<count { _ = next() }
    }

    /// Paige's `UnpackRefcon`: at document version 65547 exactly it is a
    /// `<NUL><size>,<bytes>` pointer block, otherwise one packed number.
    mutating func skipRefcon(version: Int) {
      guard version == 65547 else {
        _ = next()
        return
      }
      guard position < bytes.endIndex, bytes[position] == 0 else { return }
      position += 1
      var size = 0
      while position < bytes.endIndex, bytes[position] != UInt8(ascii: ","),
        let digit = Character(UnicodeScalar(bytes[position])).wholeNumberValue
      {
        size = size * 10 + digit
        position += 1
      }
      if position < bytes.endIndex, bytes[position] == UInt8(ascii: ",") { position += 1 }
      position = min(bytes.endIndex, position + size)
    }

    mutating func next() -> Int {
      if repeatCount > 0 {
        repeatCount -= 1
        return lastValue
      }
      guard position < bytes.endIndex else { return 0 }
      let control = bytes[position]
      position += 1
      var value = 0
      if control & 0x80 != 0 {
        value = lastValue
        if control & 0x40 != 0, position < bytes.endIndex {
          repeatCount = Int(bytes[position]) - 1
          position += 1
        }
      } else {
        var negative = false
        if position < bytes.endIndex, bytes[position] == UInt8(ascii: "-") {
          negative = true
          position += 1
        }
        var digits = 0
        while position < bytes.endIndex,
          let digit = Character(UnicodeScalar(bytes[position])).hexDigitValue
        {
          value = value * 16 + digit
          digits += 1
          position += 1
        }
        if digits == 0 { value = 0 }
        if negative { value = -value }
        if control & 0x0F == 1 { value = Int(UInt16(truncatingIfNeeded: value)) }
      }
      lastValue = value
      return value
    }
  }

  /// Decodes one `<hex length>,<text bytes>\x03` block: everything between
  /// the length prefix's comma and the terminator, cut at the first NUL.
  private static func textBlock(_ block: ArraySlice<UInt8>) -> String {
    guard let comma = block.prefix(10).firstIndex(of: UInt8(ascii: ",")) else { return "" }
    var end = block.endIndex
    if end > comma + 1, block[end - 1] == 0x03 {
      end -= 1
    }
    var body = block[(comma + 1)..<end]
    if let nul = body.firstIndex(of: 0) {
      body = body[body.startIndex..<nul]
    }
    return String(decoding: body, as: UTF8.self)
  }

  private static func isASCIIHexDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
      || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
      || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
  }

  private static func hexValue(_ bytes: [UInt8], _ offset: Int, _ digits: Int) -> Int? {
    var value = 0
    for i in offset..<(offset + digits) {
      guard let digit = Character(UnicodeScalar(bytes[i])).hexDigitValue else { return nil }
      value = value * 16 + digit
    }
    return value
  }
}
