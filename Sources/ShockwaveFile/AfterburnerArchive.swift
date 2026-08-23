import BinaryParsing
import Foundation

/// The Afterburner envelope `.dcr`/`.cct` files wrap their chunks in —
/// Shockwave's shipping format, as opposed to the plain RIFX of a `.dir`.
///
/// After the container header (`XFIR`/`RIFX` + length + `FGDM`/`FGDC`) come
/// four envelope chunks, each a tag followed by a *variable-length* size
/// rather than the fixed `UInt32` of plain RIFX:
///
/// - `Fver`: the version this was burned with.
/// - `Fcdr`: the compression types used, as GUIDs and names (zlib-compressed).
/// - `ABMP`: the map — for every chunk, its resource id, where its bytes
///   are, their compressed and decompressed sizes, and which compression
///   applies (itself zlib-compressed).
/// - `FGEI`: a marker and one more variable-length field; the chunk bytes
///   follow, addressed by the map's offsets counted from there. The map's resource 2 is the "initial load segment",
///   a single compressed blob holding the chunks the player needs up front,
///   concatenated with their ids.
///
/// Reading one produces the same `RIFXFile` a plain movie does: every chunk
/// is decompressed into one buffer laid out with ordinary tag+length
/// headers, and the chunk map indexes it by resource id, so nothing above
/// this layer has to know which format the movie arrived in.
enum AfterburnerArchive {
  /// The compression a chunk is stored with. Only zlib and "none" appear
  /// in practice; anything else is left compressed and reported.
  enum Compression {
    case none
    case zlib
    /// Shockwave Audio: the burner re-encoded a sound to MP3. The bytes
    /// are already the finished stream, so they pass through — the sound
    /// layer decodes them like any other Shockwave Audio media.
    case shockwaveAudio
    case unknown
  }

  struct Resource {
    var id: Int
    var fourCC: FourCharCode
    /// Offset of the chunk's bytes, relative to the end of `FGEI`'s tag.
    var offset: Int
    var compressedLength: Int
    var length: Int
    var compression: Compression
  }

  static func read(_ data: Data, header: RIFXHeader) throws -> RIFXFile {
    let bytes = [UInt8](data)
    var cursor = RIFXHeader.byteCount

    // Envelope chunks, in order, up to the `FGEI` marker.
    var compressions: [Compression] = []
    var resources: [Resource] = []
    var bodyOffset: Int?
    while cursor + 4 <= bytes.count {
      let tag = try fourCC(bytes, at: cursor, byteOrder: header.byteOrder)
      cursor += 4
      if tag == "FGEI" {
        // One more variable-length field follows the tag; the map's
        // offsets are counted from just past it.
        guard let (_, next) = varint(bytes, at: cursor) else {
          throw ShockwaveFileError.invalidOffset(cursor)
        }
        bodyOffset = next
        break
      }
      guard let (size, next) = varint(bytes, at: cursor), next + size <= bytes.count else {
        throw ShockwaveFileError.invalidOffset(cursor)
      }
      let body = Array(bytes[next..<(next + size)])
      switch tag {
      case "Fcdr":
        compressions = compressionTypes(body)
      case "ABMP":
        resources = try map(body, byteOrder: header.byteOrder, compressions: compressions)
      default:
        break  // Fver and anything else the burner added
      }
      cursor = next + size
    }
    guard let bodyOffset, !resources.isEmpty else {
      throw ShockwaveFileError.compressedContainerUnsupported
    }

    // The initial load segment (resource 2) carries its own chunks inline:
    // each is a resource id followed by that resource's bytes.
    var inlined: [Int: [UInt8]] = [:]
    if let segment = resources.first(where: { $0.id == 2 }) {
      let start = bodyOffset + segment.offset
      guard start + segment.compressedLength <= bytes.count else {
        throw ShockwaveFileError.invalidOffset(start)
      }
      let raw = Array(bytes[start..<(start + segment.compressedLength)])
      guard let contents = decompress(raw, of: segment) else {
        throw ShockwaveFileError.compressedContainerUnsupported
      }
      let lengths = Dictionary(resources.map { ($0.id, $0.compressedLength) }) { first, _ in first }
      var position = 0
      while position < contents.count {
        guard let (id, next) = varint(contents, at: position), let length = lengths[id],
          next + length <= contents.count
        else { break }
        inlined[id] = Array(contents[next..<(next + length)])
        position = next + length
      }
    }

    // Lay every chunk out as plain RIFX: an 8-byte tag+length header, then
    // the decompressed payload, in resource-id order.
    var payload = Data()
    let highestId = resources.map(\.id).max() ?? 0
    var chunkMap = [ChunkMapEntry](
      repeating: ChunkMapEntry(fourCC: "free", length: 0, offset: 0, flags: 0),
      count: highestId + 1)
    for resource in resources.sorted(by: { $0.id < $1.id }) {
      guard let contents = self.contents(of: resource, bytes: bytes, bodyOffset: bodyOffset, inlined: inlined)
      else { continue }
      let offset = payload.count
      payload.append(contentsOf: tagBytes(resource.fourCC, byteOrder: header.byteOrder))
      payload.append(contentsOf: lengthBytes(contents.count, byteOrder: header.byteOrder))
      payload.append(contentsOf: contents)
      chunkMap[resource.id] = ChunkMapEntry(
        fourCC: resource.fourCC, length: contents.count, offset: offset, flags: 0)
    }
    return RIFXFile(header: header, chunkMap: chunkMap, data: payload)
  }

  /// A resource's decompressed bytes: from the initial load segment when
  /// it's there, otherwise from its own place in the file.
  private static func contents(
    of resource: Resource, bytes: [UInt8], bodyOffset: Int, inlined: [Int: [UInt8]]
  ) -> [UInt8]? {
    if let contents = inlined[resource.id] {
      return decompress(contents, of: resource)
    }
    // 0xFFFFFFFF marks a resource that only exists inside the initial
    // load segment; there is nothing to read at its own offset.
    guard resource.id != 2, resource.compressedLength > 0, resource.offset != 0xFFFF_FFFF else {
      return nil
    }
    let start = bodyOffset + resource.offset
    guard start >= 0, start + resource.compressedLength <= bytes.count else { return nil }
    return decompress(Array(bytes[start..<(start + resource.compressedLength)]), of: resource)
  }

  /// A chunk's bytes, decompressed when they are compressed.
  ///
  /// The map's compression type isn't the last word: chunks the burner
  /// left alone (everything inside the initial load segment, and any chunk
  /// compression wouldn't have shrunk) are stored as-is while still naming
  /// a compression type. Inflating is therefore attempted and, since the
  /// zlib decoder verifies the stream's checksum, a stored chunk falls
  /// through to itself rather than being mistaken for a compressed one.
  private static func decompress(_ bytes: [UInt8], of resource: Resource) -> [UInt8]? {
    switch resource.compression {
    case .none:
      return bytes
    case .zlib:
      if let inflated = Inflate.zlib(bytes) { return inflated }
      return resource.compressedLength == resource.length ? bytes : nil
    case .shockwaveAudio:
      return bytes
    case .unknown:
      return resource.compressedLength == resource.length ? bytes : nil
    }
  }

  // MARK: - Envelope pieces

  /// `Fcdr`: a compressed count, that many 16-byte GUIDs, then the
  /// matching names ("Macromedia ziplib compression", ...) which nothing
  /// needs. Only zlib is recognized by GUID; the "no compression" entry is
  /// all zeroes.
  private static func compressionTypes(_ body: [UInt8]) -> [Compression] {
    guard let table = Inflate.zlib(body), table.count >= 2 else { return [] }
    let count = Int(table[0]) | Int(table[1]) << 8
    var types: [Compression] = []
    for index in 0..<count {
      let start = 2 + index * 16
      guard start + 16 <= table.count else { break }
      let guid = Array(table[start..<(start + 16)])
      if guid.allSatisfy({ $0 == 0 }) {
        types.append(.none)
      } else if guid == zlibGUID {
        types.append(.zlib)
      } else if guid == shockwaveAudioGUID {
        types.append(.shockwaveAudio)
      } else {
        types.append(.unknown)
      }
    }
    return types
  }

  /// Macromedia's zlib compression GUID, in the byte order it is stored
  /// in (`{AC99E904-0070-0B36-0000-080007377A34}`, first fields
  /// little-endian).
  /// The SWA Compressor Xtra's GUID, as stored.
  private static let shockwaveAudioGUID: [UInt8] = [
    0x89, 0xA8, 0x04, 0x72, 0xD0, 0xAF, 0xCF, 0x11, 0xA2, 0x22, 0x00, 0xA0, 0x24, 0x53, 0x44, 0x4C,
  ]

  private static let zlibGUID: [UInt8] = [
    0x04, 0xE9, 0x99, 0xAC, 0x70, 0x00, 0x36, 0x0B, 0x00, 0x00, 0x08, 0x00, 0x07, 0x37, 0x7A, 0x34,
  ]

  /// `ABMP`: a compression type, the decompressed size, then the
  /// zlib-compressed map itself.
  private static func map(
    _ body: [UInt8], byteOrder: Endianness, compressions: [Compression]
  ) throws -> [Resource] {
    guard let (_, afterType) = varint(body, at: 0),
      let (_, afterLength) = varint(body, at: afterType),
      let table = Inflate.zlib(Array(body[afterLength...]))
    else { throw ShockwaveFileError.compressedContainerUnsupported }

    var position = 0
    func next() -> Int? {
      guard let (value, after) = varint(table, at: position) else { return nil }
      position = after
      return value
    }
    guard next() != nil, next() != nil, let count = next() else {
      throw ShockwaveFileError.compressedContainerUnsupported
    }
    var resources: [Resource] = []
    resources.reserveCapacity(count)
    for _ in 0..<count {
      guard let id = next(), let offset = next(), let compressedLength = next(),
        let length = next(), let type = next(), position + 4 <= table.count
      else { break }
      let tag = (try? fourCC(table, at: position, byteOrder: byteOrder)) ?? "free"
      position += 4
      resources.append(
        Resource(
          id: id, fourCC: tag, offset: offset, compressedLength: compressedLength, length: length,
          compression: type < compressions.count ? compressions[type] : .unknown))
    }
    return resources
  }

  // MARK: - Bytes

  /// Afterburner's variable-length integer: seven bits per byte, most
  /// significant group first, high bit set on every byte but the last.
  private static func varint(_ bytes: [UInt8], at offset: Int) -> (value: Int, next: Int)? {
    var value = 0
    var position = offset
    while position < bytes.count {
      let byte = bytes[position]
      position += 1
      value = value << 7 | Int(byte & 0x7F)
      if byte & 0x80 == 0 { return (value, position) }
      guard position - offset < 5 else { return nil }
    }
    return nil
  }

  private static func fourCC(_ bytes: [UInt8], at offset: Int, byteOrder: Endianness) throws
    -> FourCharCode
  {
    guard offset + 4 <= bytes.count else { throw ShockwaveFileError.invalidOffset(offset) }
    let raw = Array(bytes[offset..<(offset + 4)])
    let ordered = byteOrder == .big ? raw : raw.reversed()
    return FourCharCode(rawValue: ordered.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
  }

  private static func tagBytes(_ tag: FourCharCode, byteOrder: Endianness) -> [UInt8] {
    let raw = [
      UInt8(tag.rawValue >> 24 & 0xFF), UInt8(tag.rawValue >> 16 & 0xFF),
      UInt8(tag.rawValue >> 8 & 0xFF), UInt8(tag.rawValue & 0xFF),
    ]
    return byteOrder == .big ? raw : raw.reversed()
  }

  private static func lengthBytes(_ length: Int, byteOrder: Endianness) -> [UInt8] {
    let value = UInt32(truncatingIfNeeded: length)
    let raw = [
      UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF),
      UInt8(value & 0xFF),
    ]
    return byteOrder == .big ? raw : raw.reversed()
  }
}
