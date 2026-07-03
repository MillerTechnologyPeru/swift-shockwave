import BinaryParsing

/// The variable-length item list layout shared by `MCsL` and the `CASt` info
/// block: a big-endian item count, a table of item start offsets, the total
/// items length, then the packed item data. Item `k` spans
/// `offsets[k]..<offsets[k+1]` (the last item ends at the total length), so
/// zero-length items are how absent values are encoded.
struct ListItems {
  var items: [[UInt8]]

  init(parsing input: inout ParserSpan) throws(any Error) {
    let count = try Int(parsing: &input, storedAsBigEndian: UInt16.self)
    var offsets: [Int] = []
    offsets.reserveCapacity(count + 1)
    for _ in 0..<count {
      offsets.append(try Int(parsing: &input, storedAsBigEndian: UInt32.self))
    }
    let itemsLength = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    offsets.append(itemsLength)

    let itemData = try [UInt8](parsing: &input, byteCount: itemsLength)
    var items: [[UInt8]] = []
    items.reserveCapacity(count)
    for k in 0..<count {
      let start = offsets[k]
      let end = offsets[k + 1]
      guard start >= 0, start <= end, end <= itemData.count else {
        throw ShockwaveFileError.invalidOffset(start)
      }
      items.append(Array(itemData[start..<end]))
    }
    self.items = items
  }
}

extension ListItems {
  /// Decodes an item holding a Pascal string (length byte + bytes); empty
  /// items decode as `nil`.
  static func pascalString(_ item: [UInt8]) -> String? {
    guard let length = item.first, item.count >= 1 + Int(length) else { return nil }
    return String(decoding: item[1...Int(length)], as: UTF8.self)
  }
}
