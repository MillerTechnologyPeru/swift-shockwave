import BinaryParsing
import Foundation
import LingoBytecode

/// A parsed RIFX container: the top-level header plus the flat chunk table
/// resolved by walking `imap` → `mmap`.
///
/// This covers the classic, uncompressed RIFX container used by `.dir`
/// (editable movie), `.cst` (external cast), and `.dxr`/`.cxt` (the same
/// formats with a "protected"/locked-from-editing flag set, but still plain
/// RIFX). It does not cover `.dcr`/`.cct` (Shockwave-for-web movie/cast),
/// which wrap an Afterburner-compressed envelope (`Fver`/`Fcdr`/`ABMP`/`FGEI`)
/// around a custom bitstream instead of RIFX — `RIFXHeader.init(parsing:)`
/// detects that envelope's `Fver` magic and throws
/// `ShockwaveFileError.compressedContainerUnsupported` rather than
/// misparsing it.
public struct RIFXFile: Sendable {
  public var header: RIFXHeader
  public var chunkMap: [ChunkMapEntry]
  public var data: Data

  public init(header: RIFXHeader, chunkMap: [ChunkMapEntry], data: Data) {
    self.header = header
    self.chunkMap = chunkMap
    self.data = data
  }

  public static func read(from data: Data) throws -> RIFXFile {
    let header = try data.withParserSpan { (span: inout ParserSpan) throws -> RIFXHeader in
      try RIFXHeader(parsing: &span)
    }

    let inputMap = try data.withParserSpan { (span: inout ParserSpan) throws -> InputMapChunk in
      var chunkSpan = try span.seeking(toAbsoluteOffset: RIFXHeader.byteCount)
      let chunkHeader = try ChunkHeader(parsing: &chunkSpan, byteOrder: header.byteOrder)
      guard chunkHeader.tag == "imap" else {
        throw ShockwaveFileError.unexpectedChunk(chunkHeader.tag, expected: "imap")
      }
      var payload = try chunkSpan.sliceSpan(byteCount: chunkHeader.length)
      return try InputMapChunk(parsing: &payload, byteOrder: header.byteOrder)
    }

    let chunkMap = try data.withParserSpan { (span: inout ParserSpan) throws -> [ChunkMapEntry] in
      var chunkSpan = try span.seeking(toAbsoluteOffset: inputMap.memoryMapOffset)
      let chunkHeader = try ChunkHeader(parsing: &chunkSpan, byteOrder: header.byteOrder)
      guard chunkHeader.tag == "mmap" else {
        throw ShockwaveFileError.unexpectedChunk(chunkHeader.tag, expected: "mmap")
      }
      var payload = try chunkSpan.sliceSpan(byteCount: chunkHeader.length)
      return try MemoryMapChunk(parsing: &payload, byteOrder: header.byteOrder).entries
    }

    return RIFXFile(header: header, chunkMap: chunkMap, data: data)
  }
}

extension RIFXFile {
  public func entries(fourCC: FourCharCode) -> [ChunkMapEntry] {
    chunkMap.filter { $0.fourCC == fourCC }
  }

  /// Runs `body` with a `ParserSpan` over `entry`'s payload only (its
  /// 8-byte tag+length header already consumed), with `startPosition` reset
  /// to zero. That reset matters beyond bookkeeping: `LingoBytecode`'s own
  /// chunk parsers (`ScriptChunk`, `ScriptContextChunk`) read internal
  /// pointers (`entriesOffset`, `handlersOffset`, ...) as offsets counted
  /// from this same zero, so this is also the span shape they expect.
  public func withPayloadSpan<T>(
    of entry: ChunkMapEntry,
    _ body: (inout ParserSpan) throws -> T
  ) throws -> T {
    try data.withParserSpan { (span: inout ParserSpan) throws -> T in
      var chunkSpan = try span.seeking(toAbsoluteOffset: entry.offset)
      let chunkHeader = try ChunkHeader(parsing: &chunkSpan, byteOrder: header.byteOrder)
      guard chunkHeader.tag == entry.fourCC else {
        throw ShockwaveFileError.unexpectedChunk(chunkHeader.tag, expected: entry.fourCC)
      }
      var payload = try chunkSpan.extract(byteCount: chunkHeader.length)
      return try body(&payload)
    }
  }

  public func keyTable() throws -> KeyTableChunk? {
    guard let entry = entries(fourCC: "KEY*").first else { return nil }
    return try withPayloadSpan(of: entry) { payload in
      try KeyTableChunk(parsing: &payload, byteOrder: header.byteOrder)
    }
  }

  public func nameTable() throws -> NameTableChunk? {
    guard let entry = entries(fourCC: "Lnam").first else { return nil }
    return try withPayloadSpan(of: entry) { payload in
      try NameTableChunk(parsing: &payload)
    }
  }

  public func movieConfig() throws -> MovieConfigChunk? {
    guard let entry = entries(fourCC: "VWCF").first ?? entries(fourCC: "DRCF").first else {
      return nil
    }
    return try withPayloadSpan(of: entry) { payload in
      MovieConfigChunk(rawData: Data(parsingRemainingBytes: &payload))
    }
  }

  public func scriptContext(at entry: ChunkMapEntry) throws -> ScriptContextChunk {
    try withPayloadSpan(of: entry) { payload in
      try ScriptContextChunk.read(from: payload)
    }
  }

  public func script(at entry: ChunkMapEntry) throws -> ScriptChunk {
    try withPayloadSpan(of: entry) { payload in
      try ScriptChunk.read(from: payload)
    }
  }

  public func castList() throws -> CastListChunk? {
    guard let entry = entries(fourCC: "MCsL").first else { return nil }
    return try withPayloadSpan(of: entry) { payload in
      try CastListChunk(parsing: &payload)
    }
  }

  public func castTable(at entry: ChunkMapEntry) throws -> CastTableChunk {
    try withPayloadSpan(of: entry) { payload in
      try CastTableChunk(parsing: &payload)
    }
  }

  public func castMember(at entry: ChunkMapEntry) throws -> CastMemberChunk {
    try withPayloadSpan(of: entry) { payload in
      try CastMemberChunk(parsing: &payload)
    }
  }
}
