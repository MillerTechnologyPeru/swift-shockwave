import BinaryParsing

/// The top-level 12-byte RIFX container header: byte-order magic, overall
/// file length, and a form type identifying the kind of Director file
/// (`MV93` for a movie, `FGDC`/`FGDM` for an external cast, ...).
///
/// `.dir`, `.cst` and their locked-from-editing `.dxr`/`.cxt` counterparts
/// carry plain chunks (form types like `MV93`/`MC93`) addressed by
/// `imap`/`mmap`. `.dcr`/`.cct` (Shockwave-for-web) share this header but
/// name the Afterburner form types `FGDM`/`FGDC`, and hold compressed
/// chunks behind `Fver`/`Fcdr`/`ABMP`/`FGEI` instead; `isAfterburner` says
/// which, and `RIFXFile.read(from:)` reads both.
public struct RIFXHeader: Sendable {
  public static let byteCount = 12

  public var byteOrder: Endianness
  /// The container length in bytes, not including this header.
  public var length: Int
  public var formatCode: FourCharCode

  public init(byteOrder: Endianness, length: Int, formatCode: FourCharCode) {
    self.byteOrder = byteOrder
    self.length = length
    self.formatCode = formatCode
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let magic = try UInt32(parsingBigEndian: &input)
    switch magic {
    case 0x5249_4658:  // "RIFX"
      byteOrder = .big
    case 0x5846_4952:  // "XFIR"
      byteOrder = .little
    default:
      throw ShockwaveFileError.invalidMagic
    }
    length = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)
    formatCode = try FourCharCode(parsing: &input, byteOrder: byteOrder)
  }

  /// Whether the chunks behind this header are Afterburner-compressed
  /// (`.dcr`/`.cct`) rather than plain (`.dir`/`.cst`).
  public var isAfterburner: Bool {
    formatCode == "FGDM" || formatCode == "FGDC"
  }
}
