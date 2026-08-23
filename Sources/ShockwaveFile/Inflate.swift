/// A DEFLATE decompressor (RFC 1951), and the zlib wrapper around it
/// (RFC 1950) that Shockwave's Afterburner archives store their chunks in.
///
/// Written out rather than taken from a system library so the file layer
/// stays dependency-free and behaves the same on every platform. Only
/// decompression is implemented — nothing here needs to write archives.
public enum Inflate {
  /// Decompresses a zlib stream: a two-byte header, the deflate data, and
  /// an Adler-32 checksum. `nil` when the header isn't zlib-with-deflate
  /// or the data is malformed. The checksum is verified.
  public static func zlib(_ bytes: [UInt8]) -> [UInt8]? {
    guard bytes.count >= 6 else { return nil }
    let method = bytes[0] & 0x0F
    let info = bytes[0] >> 4
    // CM 8 is deflate; the two header bytes together must be a multiple of
    // 31; a preset dictionary (FDICT) is never used by these archives.
    guard method == 8, info <= 7, (Int(bytes[0]) << 8 | Int(bytes[1])) % 31 == 0,
      bytes[1] & 0x20 == 0
    else { return nil }
    guard let (output, end) = rawWithEnd(bytes, from: 2), end + 4 <= bytes.count else {
      return nil
    }
    // A big-endian Adler-32 of the output closes the stream. Checking it
    // is what makes "try inflating and fall back" safe for callers that
    // can't tell compressed bytes from stored ones up front.
    let stored =
      UInt32(bytes[end]) << 24 | UInt32(bytes[end + 1]) << 16 | UInt32(bytes[end + 2]) << 8
      | UInt32(bytes[end + 3])
    guard adler32(output) == stored else { return nil }
    return output
  }

  /// Decompresses a bare deflate stream starting at `offset`.
  public static func raw(_ bytes: [UInt8], from offset: Int = 0) -> [UInt8]? {
    rawWithEnd(bytes, from: offset)?.output
  }

  /// The decompressed bytes and the offset just past the stream, which the
  /// zlib wrapper needs to find its trailing checksum.
  private static func rawWithEnd(_ bytes: [UInt8], from offset: Int) -> (output: [UInt8], end: Int)? {
    var reader = BitReader(bytes: bytes, position: offset)
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count * 4)

    while true {
      guard let final = reader.bit(), let type = reader.bits(2) else { return nil }
      switch type {
      case 0:
        reader.alignToByte()
        guard let length = reader.bits(16), let check = reader.bits(16),
          length ^ 0xFFFF == check, reader.copyBytes(length, into: &output)
        else { return nil }
      case 1:
        guard decodeBlock(&reader, HuffmanTable.fixedLiterals, HuffmanTable.fixedDistances, &output)
        else { return nil }
      case 2:
        guard let (literals, distances) = readDynamicTables(&reader),
          decodeBlock(&reader, literals, distances, &output)
        else { return nil }
      default:
        return nil  // reserved block type
      }
      if final == 1 {
        reader.alignToByte()
        return (output, reader.position)
      }
    }
  }

  /// RFC 1950's checksum: two 16-bit running sums of the bytes.
  private static func adler32(_ bytes: [UInt8]) -> UInt32 {
    var low: UInt32 = 1
    var high: UInt32 = 0
    for byte in bytes {
      low = (low + UInt32(byte)) % 65521
      high = (high + low) % 65521
    }
    return high << 16 | low
  }

  // MARK: - Blocks

  /// Decodes one block's symbols: literals go straight out, a length
  /// symbol pairs with a distance and copies from what's already been
  /// written (which may overlap the output's own tail).
  private static func decodeBlock(
    _ reader: inout BitReader, _ literals: HuffmanTable, _ distances: HuffmanTable,
    _ output: inout [UInt8]
  ) -> Bool {
    while true {
      guard let symbol = literals.decode(&reader) else { return false }
      if symbol < 256 {
        output.append(UInt8(symbol))
        continue
      }
      if symbol == 256 { return true }  // end of block
      let lengthIndex = symbol - 257
      guard lengthIndex < lengthBases.count, let extra = reader.bits(lengthExtraBits[lengthIndex])
      else { return false }
      let length = lengthBases[lengthIndex] + extra
      guard let distanceSymbol = distances.decode(&reader), distanceSymbol < distanceBases.count,
        let distanceExtra = reader.bits(distanceExtraBits[distanceSymbol])
      else { return false }
      let distance = distanceBases[distanceSymbol] + distanceExtra
      guard distance > 0, distance <= output.count else { return false }
      var source = output.count - distance
      for _ in 0..<length {
        output.append(output[source])
        source += 1
      }
    }
  }

  /// Reads a dynamic block's two Huffman tables, which are themselves
  /// coded with a third (the code-length alphabet).
  private static func readDynamicTables(_ reader: inout BitReader) -> (HuffmanTable, HuffmanTable)? {
    guard let literalCount = reader.bits(5), let distanceCount = reader.bits(5),
      let codeLengthCount = reader.bits(4)
    else { return nil }
    let literals = literalCount + 257
    let distances = distanceCount + 1
    var codeLengths = [Int](repeating: 0, count: codeLengthOrder.count)
    for index in 0..<(codeLengthCount + 4) {
      guard let value = reader.bits(3) else { return nil }
      codeLengths[codeLengthOrder[index]] = value
    }
    guard let codeLengthTable = HuffmanTable(lengths: codeLengths) else { return nil }

    var lengths = [Int]()
    lengths.reserveCapacity(literals + distances)
    while lengths.count < literals + distances {
      guard let symbol = codeLengthTable.decode(&reader) else { return nil }
      switch symbol {
      case 0..<16:
        lengths.append(symbol)
      case 16:
        // Repeat the previous length 3–6 times.
        guard let last = lengths.last, let extra = reader.bits(2) else { return nil }
        lengths.append(contentsOf: repeatElement(last, count: 3 + extra))
      case 17:
        guard let extra = reader.bits(3) else { return nil }
        lengths.append(contentsOf: repeatElement(0, count: 3 + extra))
      case 18:
        guard let extra = reader.bits(7) else { return nil }
        lengths.append(contentsOf: repeatElement(0, count: 11 + extra))
      default:
        return nil
      }
    }
    guard lengths.count == literals + distances,
      let literalTable = HuffmanTable(lengths: Array(lengths[0..<literals])),
      let distanceTable = HuffmanTable(lengths: Array(lengths[literals...]))
    else { return nil }
    return (literalTable, distanceTable)
  }

  // MARK: - Bits

  /// Deflate's bit order: least-significant bit of each byte first.
  private struct BitReader {
    let bytes: [UInt8]
    var position: Int
    var bitOffset = 0

    mutating func bit() -> Int? {
      guard position < bytes.count else { return nil }
      let value = Int(bytes[position] >> UInt8(bitOffset)) & 1
      bitOffset += 1
      if bitOffset == 8 {
        bitOffset = 0
        position += 1
      }
      return value
    }

    mutating func bits(_ count: Int) -> Int? {
      var value = 0
      for index in 0..<count {
        guard let bit = bit() else { return nil }
        value |= bit << index
      }
      return value
    }

    mutating func alignToByte() {
      if bitOffset > 0 {
        bitOffset = 0
        position += 1
      }
    }

    /// Copies `count` whole bytes — a stored block's payload.
    mutating func copyBytes(_ count: Int, into output: inout [UInt8]) -> Bool {
      guard bitOffset == 0, position + count <= bytes.count else { return false }
      output.append(contentsOf: bytes[position..<(position + count)])
      position += count
      return true
    }
  }

  /// A canonical Huffman table, decoded bit by bit: at each length, the
  /// codes are consecutive, so a running comparison against the first code
  /// of that length identifies the symbol without building a lookup tree.
  private struct HuffmanTable {
    /// How many codes there are of each bit length.
    private var counts: [Int]
    /// Symbols ordered by (length, symbol) — canonical order.
    private var symbols: [Int]

    init?(lengths: [Int]) {
      var counts = [Int](repeating: 0, count: 16)
      for length in lengths {
        guard length >= 0, length < 16 else { return nil }
        counts[length] += 1
      }
      counts[0] = 0
      var offsets = [Int](repeating: 0, count: 16)
      for length in 1..<16 {
        offsets[length] = offsets[length - 1] + counts[length - 1]
      }
      var symbols = [Int](repeating: 0, count: lengths.count)
      for (symbol, length) in lengths.enumerated() where length > 0 {
        symbols[offsets[length]] = symbol
        offsets[length] += 1
      }
      self.counts = counts
      self.symbols = symbols
    }

    func decode(_ reader: inout BitReader) -> Int? {
      var code = 0
      var first = 0
      var index = 0
      for length in 1..<16 {
        guard let bit = reader.bit() else { return nil }
        code |= bit
        let count = counts[length]
        if code - first < count {
          return symbols[index + (code - first)]
        }
        index += count
        first = (first + count) << 1
        code <<= 1
      }
      return nil
    }

    /// The fixed tables blocks of type 1 use, from RFC 1951 §3.2.6.
    static let fixedLiterals: HuffmanTable = {
      var lengths = [Int](repeating: 8, count: 288)
      for symbol in 144..<256 { lengths[symbol] = 9 }
      for symbol in 256..<280 { lengths[symbol] = 7 }
      return HuffmanTable(lengths: lengths)!
    }()

    static let fixedDistances = HuffmanTable(lengths: [Int](repeating: 5, count: 30))!
  }

  // MARK: - Tables

  private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
  private static let lengthBases = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
  ]
  private static let lengthExtraBits = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
  ]
  private static let distanceBases = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ]
  private static let distanceExtraBits = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
    13,
  ]
}
