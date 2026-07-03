import BinaryParsing

/// The `VWLB` chunk: the score's frame labels, in frame order.
///
/// Always big-endian, independent of the container byte order.
public struct FrameLabelsChunk: Sendable {
  public struct Label: Equatable, Sendable {
    public var frame: Int
    public var name: String

    public init(frame: Int, name: String) {
      self.frame = frame
      self.name = name
    }
  }

  public var labels: [Label]

  public init(labels: [Label]) {
    self.labels = labels
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let count = try Int(parsing: &input, storedAsBigEndian: UInt16.self)
    // count+1 (frame, string offset) pairs: the last is a fence carrying the
    // total string-data length, with string offsets relative to the string
    // area that follows the pairs.
    var frames: [Int] = []
    var offsets: [Int] = []
    for _ in 0..<(count + 1) {
      frames.append(try Int(parsing: &input, storedAsBigEndian: UInt16.self))
      offsets.append(try Int(parsing: &input, storedAsBigEndian: UInt16.self))
    }
    let stringData = try [UInt8](parsing: &input, byteCount: offsets[count])

    var labels: [Label] = []
    labels.reserveCapacity(count)
    for k in 0..<count {
      let start = offsets[k]
      let end = offsets[k + 1]
      guard start >= 0, start <= end, end <= stringData.count else {
        throw ShockwaveFileError.invalidOffset(start)
      }
      labels.append(
        Label(frame: frames[k], name: String(decoding: stringData[start..<end], as: UTF8.self)))
    }
    self.labels = labels
  }
}
