import BinaryParsing

/// A four-character chunk tag, e.g. `RIFX`, `imap`, `mmap`.
///
/// RIFX chunk tags are stored as literal ASCII bytes in file order regardless
/// of the container's numeric byte order, so this always reads as big-endian.
public struct FourCharCode: RawRepresentable, Hashable, Sendable {
  public var rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  public init(_ string: some StringProtocol) {
    let bytes = Array(string.utf8)
    precondition(bytes.count == 4, "FourCharCode requires exactly 4 ASCII characters")
    rawValue = bytes.reduce(0) { ($0 << 8) | UInt32($1) }
  }
}

extension FourCharCode: ExpressibleByStringLiteral {
  public init(stringLiteral value: StaticString) {
    self.init(value.description)
  }
}

extension FourCharCode: CustomStringConvertible {
  public var description: String {
    let bytes = [
      UInt8((rawValue >> 24) & 0xFF),
      UInt8((rawValue >> 16) & 0xFF),
      UInt8((rawValue >> 8) & 0xFF),
      UInt8(rawValue & 0xFF),
    ]
    return String(decoding: bytes, as: UTF8.self)
  }
}

extension FourCharCode {
  public init(parsing input: inout ParserSpan) throws(ParsingError) {
    rawValue = try UInt32(parsingBigEndian: &input)
  }
}
