import BinaryParsing

/// The 8-byte tag + length header that precedes every RIFX chunk's payload.
public struct ChunkHeader: Sendable {
  public var tag: FourCharCode
  /// The payload length in bytes, not including this header.
  public var length: Int

  public init(tag: FourCharCode, length: Int) {
    self.tag = tag
    self.length = length
  }

  public init(parsing input: inout ParserSpan, byteOrder: Endianness) throws(ParsingError) {
    tag = try FourCharCode(parsing: &input, byteOrder: byteOrder)
    length = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)
  }
}
