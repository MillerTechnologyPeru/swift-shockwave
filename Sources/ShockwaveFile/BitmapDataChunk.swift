import Foundation

/// Decodes a `BITD` chunk's pixel data. Two storage forms exist: raw (the
/// chunk is exactly `rowBytes × height` bytes) and byte-run compression
/// (a control byte `n ≥ 128` repeats the following byte `257 - n` times;
/// `n < 128` copies the next `n + 1` bytes literally). Validated against
/// every bitmap in the junkbot sample: all 1085 decode to exactly the
/// expected size, consuming exactly the whole chunk.
public enum BitmapData {
  /// One decode call's result: the row-major pixel bytes, plus whether the
  /// source chunk was actually byte-run compressed. That matters for
  /// 16-bit-per-pixel images: a compressed source stores each row's pixels
  /// **planar** (every high byte, then every low byte), while a raw/
  /// uncompressed source stores them interleaved (high, low, high, low...).
  /// Callers decoding 16bpp pixel data need to know which layout they got.
  public struct Decoded {
    public var pixels: [UInt8]
    public var wasCompressed: Bool
  }

  /// Decodes `data` to exactly `expectedByteCount`
  /// (`BitmapMemberProperties.decodedByteCount`) bytes of row-major pixel
  /// data, or `nil` if the data doesn't decode cleanly to that size.
  public static func decode(_ data: Data, expectedByteCount: Int) -> Decoded? {
    let source = [UInt8](data)
    if source.count == expectedByteCount {
      return Decoded(pixels: source, wasCompressed: false)
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
    return Decoded(pixels: output, wasCompressed: true)
  }
}
