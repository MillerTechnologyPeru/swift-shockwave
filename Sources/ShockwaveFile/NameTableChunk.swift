import BinaryParsing

/// The `Lnam` chunk: the movie's flat name table. Every name id referenced
/// elsewhere in the file (property/global/handler names in a script chunk,
/// `LingoBytecode`'s `names:` parameter) is an index into this array.
public struct NameTableChunk: Sendable {
  public var names: [String]

  public init(names: [String]) {
    self.names = names
  }

  public init(parsing input: inout ParserSpan, byteOrder: Endianness) throws(any Error) {
    let _ = try UInt32(parsing: &input, endianness: byteOrder)  // unknown0
    let _ = try UInt32(parsing: &input, endianness: byteOrder)  // unknown1
    let count = try Int(parsing: &input, storedAs: UInt16.self, endianness: byteOrder)
    let _ = try UInt16(parsing: &input, endianness: byteOrder)  // unknown2

    var names: [String] = []
    names.reserveCapacity(count)
    for _ in 0..<count {
      let length = try Int(parsing: &input, storedAs: UInt8.self)
      let bytes = try [UInt8](parsing: &input, byteCount: length)
      names.append(String(decoding: bytes, as: UTF8.self))
    }
    self.names = names
  }
}
