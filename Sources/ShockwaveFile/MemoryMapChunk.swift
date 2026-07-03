import BinaryParsing

/// One entry in the `mmap` chunk table: a chunk's tag, size, and absolute
/// file offset.
public struct ChunkMapEntry: Equatable, Sendable {
  public var fourCC: FourCharCode
  public var length: Int
  /// Absolute file offset of the chunk's tag+length header.
  public var offset: Int
  public var flags: UInt32

  public init(fourCC: FourCharCode, length: Int, offset: Int, flags: UInt32) {
    self.fourCC = fourCC
    self.length = length
    self.offset = offset
    self.flags = flags
  }
}

/// The `mmap` chunk: the authoritative directory of every chunk in the file,
/// including itself and the `imap`/`RIFX` chunks that precede it.
public struct MemoryMapChunk: Sendable {
  public var entries: [ChunkMapEntry]

  public init(entries: [ChunkMapEntry]) {
    self.entries = entries
  }

  public init(parsing input: inout ParserSpan, byteOrder: Endianness) throws(any Error) {
    let headerStart = input.startPosition
    let headerLength = try Int(parsing: &input, storedAs: UInt16.self, endianness: byteOrder)
    let entrySize = try Int(parsing: &input, storedAs: UInt16.self, endianness: byteOrder)
    let _ = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)  // entryCountMax
    let entryCountUsed = try Int(parsing: &input, storedAs: UInt32.self, endianness: byteOrder)

    // `headerLength` is self-describing, so seeking past it (rather than
    // assuming a fixed count of trailing reserved fields) stays correct
    // even if this format has extra header fields this doesn't parse.
    let remainingHeaderBytes = headerLength - (input.startPosition - headerStart)
    guard remainingHeaderBytes >= 0 else {
      throw ShockwaveFileError.invalidOffset(headerLength)
    }
    if remainingHeaderBytes > 0 {
      try input.seek(toRelativeOffset: remainingHeaderBytes)
    }

    var entries: [ChunkMapEntry] = []
    entries.reserveCapacity(entryCountUsed)
    for _ in 0..<entryCountUsed {
      var record = try input.sliceSpan(byteCount: entrySize)
      let fourCC = try FourCharCode(parsing: &record, byteOrder: byteOrder)
      let length = try Int(parsing: &record, storedAs: UInt32.self, endianness: byteOrder)
      let offset = try Int(parsing: &record, storedAs: UInt32.self, endianness: byteOrder)
      let flags = try UInt32(parsing: &record, endianness: byteOrder)
      entries.append(ChunkMapEntry(fourCC: fourCC, length: length, offset: offset, flags: flags))
    }
    self.entries = entries
  }
}
