import BinaryParsing

/// The `STXT` chunk: a field cast member's text with its style runs.
///
/// Always big-endian, independent of the container byte order. Layout
/// (validated against the junkbot sample's 18 `STXT` chunks): a 12-byte
/// header of text offset (always 12), text length, and style-data length,
/// then the text bytes, then the style runs. Only the text is decoded here;
/// styles wait until the renderer can use them.
public struct TextChunk: Sendable {
  /// The member's text, with Director's `\r` line separators preserved.
  public var text: String

  public init(text: String) {
    self.text = text
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let textOffset = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    let textLength = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    _ = try UInt32(parsingBigEndian: &input)  // style data length
    guard textOffset >= 12 else { throw ShockwaveFileError.invalidOffset(textOffset) }
    try input.seek(toRelativeOffset: textOffset - 12)
    let bytes = try [UInt8](parsing: &input, byteCount: textLength)
    text = String(decoding: bytes, as: UTF8.self)
  }
}

extension RIFXFile {
  public func textChunk(at entry: ChunkMapEntry) throws -> TextChunk {
    try withPayloadSpan(of: entry) { payload in
      try TextChunk(parsing: &payload)
    }
  }
}
