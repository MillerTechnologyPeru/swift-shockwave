import Foundation

/// Plain-text extraction from an `XMED` chunk — the media payload of a text
/// xtra cast member (Director's rich-text engine, Paige).
///
/// The chunk is a sequence of sections, each headed by 20 bytes of ASCII
/// hex: a 4-digit section key, an 8-digit byte count, a 4-digit type, and a
/// 4-digit declared length, followed by exactly `count` bytes of payload.
/// The text itself lives in section `0x0002` (possibly split across several
/// such sections, concatenated in order), each payload shaped
/// `<hex length>,<text bytes>\x03`. Styling sections are ignored here.
///
/// Validated against the junkbot sample's 122 `XMED` members — level
/// definitions, field text, and the loading screen's "READY TO PLAY" all
/// extract cleanly. The layout matches dirplayer-rs's independently
/// reverse-engineered parser.
public enum XMediaText {
  /// The concatenated text of every text section, or `nil` when `data`
  /// isn't styled-text media (fonts and 3D scenes ship as `XMED` too).
  public static func text(from data: Data) -> String? {
    let bytes = [UInt8](data)
    guard bytes.count >= 12,
      bytes[0] == UInt8(ascii: "F"), bytes[1] == UInt8(ascii: "F"),
      bytes[2] == UInt8(ascii: "F"), bytes[3] == UInt8(ascii: "F")
    else { return nil }

    var pieces: [String] = []
    var offset = 0
    while offset + 20 <= bytes.count {
      let header = bytes[offset..<(offset + 20)]
      guard header.allSatisfy(isASCIIHexDigit) else { break }
      guard let key = hexValue(bytes, offset, 4),
        let count = hexValue(bytes, offset + 4, 8)
      else { break }
      offset += 20
      let available = min(count, bytes.count - offset)
      if key == 0x0002 {
        pieces.append(textBlock(bytes[offset..<(offset + available)]))
      }
      offset += available
      if available < count { break }
    }
    guard !pieces.isEmpty else { return nil }
    return pieces.joined()
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
