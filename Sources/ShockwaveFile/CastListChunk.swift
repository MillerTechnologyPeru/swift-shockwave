import BinaryParsing

/// One cast library in the `MCsL` cast list.
public struct CastListEntry: Equatable, Sendable {
  public var name: String
  public var filePath: String
  public var preloadMode: UInt16?
  public var minMember: Int?
  public var maxMember: Int?
  /// The owner id this library's chunks (`CAS*`, `Cinf`, `Lctx`) carry in
  /// the key table: `libraryNumber << 16 | 1024`. `nil` for the internal
  /// cast, whose metadata item is empty.
  public var resourceId: Int?

  public init(
    name: String,
    filePath: String,
    preloadMode: UInt16?,
    minMember: Int?,
    maxMember: Int?,
    resourceId: Int?
  ) {
    self.name = name
    self.filePath = filePath
    self.preloadMode = preloadMode
    self.minMember = minMember
    self.maxMember = maxMember
    self.resourceId = resourceId
  }
}

/// The `MCsL` chunk (Director 5+): the movie's cast libraries — names,
/// external file paths, member number ranges, and the key-table owner ids
/// that tie each library to its `CAS*`/`Cinf`/`Lctx` chunks.
///
/// Always big-endian, independent of the container byte order.
public struct CastListChunk: Sendable {
  public var entries: [CastListEntry]

  public init(entries: [CastListEntry]) {
    self.entries = entries
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let payloadStart = input.startPosition
    let dataOffset = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    let _ = try UInt16(parsingBigEndian: &input)  // unknown
    let castCount = try Int(parsing: &input, storedAsBigEndian: UInt16.self)
    let itemsPerCast = try Int(parsing: &input, storedAsBigEndian: UInt16.self)

    let consumed = input.startPosition - payloadStart
    guard dataOffset >= consumed else {
      throw ShockwaveFileError.invalidOffset(dataOffset)
    }
    try input.seek(toRelativeOffset: dataOffset - consumed)
    let list = try ListItems(parsing: &input)

    var entries: [CastListEntry] = []
    entries.reserveCapacity(castCount)
    for cast in 0..<castCount {
      func item(_ k: Int) -> [UInt8] {
        let index = cast * itemsPerCast + k
        return index < list.items.count ? list.items[index] : []
      }
      let metadata = item(0)
      var minMember: Int?
      var maxMember: Int?
      var resourceId: Int?
      if metadata.count >= 8 {
        minMember = Int(metadata[0]) << 8 | Int(metadata[1])
        maxMember = Int(metadata[2]) << 8 | Int(metadata[3])
        resourceId =
          Int(metadata[4]) << 24 | Int(metadata[5]) << 16
          | Int(metadata[6]) << 8 | Int(metadata[7])
      }
      let preloadItem = item(3)
      let preloadMode: UInt16? =
        preloadItem.count >= 2 ? UInt16(preloadItem[0]) << 8 | UInt16(preloadItem[1]) : nil
      entries.append(
        CastListEntry(
          name: ListItems.pascalString(item(1)) ?? "",
          filePath: ListItems.pascalString(item(2)) ?? "",
          preloadMode: preloadMode,
          minMember: minMember,
          maxMember: maxMember,
          resourceId: resourceId
        ))
    }
    self.entries = entries
  }
}
