import BinaryParsing

/// One parent/child relationship in the key table: `childChunkIndex` is owned
/// by `ownerChunkIndex` (e.g. a script chunk owned by a cast member chunk).
/// Both indices refer to positions in `MemoryMapChunk.entries`, not byte
/// offsets.
public struct KeyTableEntry: Equatable, Sendable {
  public var childChunkIndex: Int
  public var ownerChunkIndex: Int
  public var fourCC: FourCharCode

  public init(childChunkIndex: Int, ownerChunkIndex: Int, fourCC: FourCharCode) {
    self.childChunkIndex = childChunkIndex
    self.ownerChunkIndex = ownerChunkIndex
    self.fourCC = fourCC
  }
}

/// The `KEY*` chunk: the table of parent/child chunk relationships that ties,
/// e.g., a script chunk to the cast member that owns it.
public struct KeyTableChunk: Sendable {
  public var entries: [KeyTableEntry]

  public init(entries: [KeyTableEntry]) {
    self.entries = entries
  }

  public init(parsing input: inout ParserSpan, byteOrder: Endianness) throws(ParsingError) {
    let entrySize = try Int(parsing: &input, storedAs: UInt16.self, endianness: byteOrder)
    let _ = try Int(parsing: &input, storedAs: UInt16.self, endianness: byteOrder)  // unused
    let _ = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)  // entryCountMax
    let entryCountUsed = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)

    var entries: [KeyTableEntry] = []
    entries.reserveCapacity(entryCountUsed)
    for _ in 0..<entryCountUsed {
      var record = try input.sliceSpan(byteCount: entrySize)
      let childChunkIndex = try Int(parsing: &record, storedAs: UInt32.self, endianness: byteOrder)
      let ownerChunkIndex = try Int(parsing: &record, storedAs: UInt32.self, endianness: byteOrder)
      let fourCC = try FourCharCode(parsing: &record, byteOrder: byteOrder)
      entries.append(
        KeyTableEntry(
          childChunkIndex: childChunkIndex, ownerChunkIndex: ownerChunkIndex, fourCC: fourCC))
    }
    self.entries = entries
  }
}
