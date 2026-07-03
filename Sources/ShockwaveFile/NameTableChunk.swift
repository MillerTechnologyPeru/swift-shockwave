import BinaryParsing

/// The `Lnam` chunk: the movie's flat name table. Every name id referenced
/// elsewhere in the file (property/global/handler names in a script chunk,
/// `LingoBytecode`'s `names:` parameter) is an index into this array.
///
/// Like the other Lingo chunks (`Lscr`, `Lctx`), the payload is always
/// big-endian regardless of the container's byte order.
public struct NameTableChunk: Sendable {
  public var names: [String]

  public init(names: [String]) {
    self.names = names
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let payloadStart = input.startPosition
    let _ = try UInt32(parsingBigEndian: &input)  // unknown0
    let _ = try UInt32(parsingBigEndian: &input)  // unknown1
    let _ = try UInt32(parsingBigEndian: &input)  // payload length
    let _ = try UInt32(parsingBigEndian: &input)  // payload length (repeated)
    let namesOffset = try Int(parsing: &input, storedAsBigEndian: UInt16.self)
    let count = try Int(parsing: &input, storedAsBigEndian: UInt16.self)

    let consumed = input.startPosition - payloadStart
    if namesOffset > consumed {
      try input.seek(toRelativeOffset: namesOffset - consumed)
    } else if namesOffset < consumed {
      throw ShockwaveFileError.invalidOffset(namesOffset)
    }

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
