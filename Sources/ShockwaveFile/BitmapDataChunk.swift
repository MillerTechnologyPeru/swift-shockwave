import Foundation

/// Decodes a `BITD` chunk's pixel data. Two storage forms exist: raw (the
/// chunk is exactly `rowBytes × height` bytes) and byte-run compression
/// (a control byte `n ≥ 128` repeats the following byte `257 - n` times;
/// `n < 128` copies the next `n + 1` bytes literally). Validated against
/// every bitmap in the junkbot sample: all 1085 decode to exactly the
/// expected size, consuming exactly the whole chunk.
public enum BitmapData {
  /// Decodes `data` to exactly `expectedByteCount`
  /// (`BitmapMemberProperties.decodedByteCount`) bytes of row-major pixel
  /// data, or `nil` if the data doesn't decode cleanly to that size.
  public static func decode(_ data: Data, expectedByteCount: Int) -> [UInt8]? {
    let source = [UInt8](data)
    if source.count == expectedByteCount {
      return source
    }
    var output = [UInt8]()
    output.reserveCapacity(expectedByteCount)
    var index = 0
    while index < source.count, output.count < expectedByteCount {
      let control = Int(source[index])
      index += 1
      if control >= 128 {
        guard index < source.count else { return nil }
        output.append(contentsOf: repeatElement(source[index], count: 257 - control))
        index += 1
      } else {
        let literalCount = control + 1
        guard index + literalCount <= source.count else { return nil }
        output.append(contentsOf: source[index..<(index + literalCount)])
        index += literalCount
      }
    }
    guard output.count == expectedByteCount, index == source.count else { return nil }
    return output
  }
}
