import BinaryParsing

/// The `imap` chunk: a small, fixed chunk right after the RIFX header whose
/// only job is pointing at the `mmap` chunk that holds the real chunk table.
public struct InputMapChunk: Sendable {
  public var entryCount: Int
  /// Absolute file offset of the `mmap` chunk's tag+length header.
  public var memoryMapOffset: Int

  public init(entryCount: Int, memoryMapOffset: Int) {
    self.entryCount = entryCount
    self.memoryMapOffset = memoryMapOffset
  }

  public init(parsing input: inout ParserSpan, byteOrder: Endianness) throws(ParsingError) {
    entryCount = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)
    memoryMapOffset = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)
  }
}
