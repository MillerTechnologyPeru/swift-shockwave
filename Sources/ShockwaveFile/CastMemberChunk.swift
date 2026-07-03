import BinaryParsing
import Foundation

/// The built-in cast member types stored in a `CASt` chunk's type field.
public enum CastMemberType: RawRepresentable, Equatable, Sendable {
  case bitmap
  case filmLoop
  case field
  case palette
  case picture
  case sound
  case button
  case shape
  case movie
  case digitalVideo
  case script
  case richText
  case ole
  case transition
  case xtra
  case unknown(UInt32)

  public init(rawValue: UInt32) {
    switch rawValue {
    case 1: self = .bitmap
    case 2: self = .filmLoop
    case 3: self = .field
    case 4: self = .palette
    case 5: self = .picture
    case 6: self = .sound
    case 7: self = .button
    case 8: self = .shape
    case 9: self = .movie
    case 10: self = .digitalVideo
    case 11: self = .script
    case 12: self = .richText
    case 13: self = .ole
    case 14: self = .transition
    case 15: self = .xtra
    default: self = .unknown(rawValue)
    }
  }

  public var rawValue: UInt32 {
    switch self {
    case .bitmap: return 1
    case .filmLoop: return 2
    case .field: return 3
    case .palette: return 4
    case .picture: return 5
    case .sound: return 6
    case .button: return 7
    case .shape: return 8
    case .movie: return 9
    case .digitalVideo: return 10
    case .script: return 11
    case .richText: return 12
    case .ole: return 13
    case .transition: return 14
    case .xtra: return 15
    case .unknown(let value): return value
    }
  }
}

/// The `CASt` chunk (Director 5+ layout): one cast member's shared
/// properties (name, script source text) plus a type-specific data blob
/// preserved raw — decoding per-type media geometry is rendering territory
/// and out of scope here.
///
/// Always big-endian, independent of the container byte order.
public struct CastMemberChunk: Sendable {
  public var type: CastMemberType
  public var name: String?
  /// The member script's Lingo source text, when present. Compiled bytecode
  /// lives separately in the cast's `Lctx`/`Lscr` chunks; protected movies
  /// strip this text and keep only the bytecode.
  public var scriptText: String?
  /// The info header's trailing field, nonzero only for members with a
  /// script: the 1-based section id of the member's script in the cast's
  /// `Lctx` section map.
  public var scriptId: Int
  /// All info-list items, including the ones `name`/`scriptText` decode.
  public var infoItems: [[UInt8]]
  public var specificData: Data

  public init(
    type: CastMemberType,
    name: String?,
    scriptText: String?,
    scriptId: Int,
    infoItems: [[UInt8]],
    specificData: Data
  ) {
    self.type = type
    self.name = name
    self.scriptText = scriptText
    self.scriptId = scriptId
    self.infoItems = infoItems
    self.specificData = specificData
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let type = try CastMemberType(
      rawValue: UInt32(parsingBigEndian: &input))
    let infoLength = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    let dataLength = try Int(parsing: &input, storedAsBigEndian: UInt32.self)

    var name: String?
    var scriptText: String?
    var scriptId = 0
    var infoItems: [[UInt8]] = []
    if infoLength > 0 {
      var info = try input.sliceSpan(byteCount: infoLength)
      let infoStart = info.startPosition
      let dataOffset = try Int(parsing: &info, storedAsBigEndian: UInt32.self)
      let _ = try UInt32(parsingBigEndian: &info)  // unknown
      let _ = try UInt32(parsingBigEndian: &info)  // unknown
      let _ = try UInt32(parsingBigEndian: &info)  // flags
      scriptId = try Int(parsing: &info, storedAsBigEndian: UInt32.self)
      let consumed = info.startPosition - infoStart
      guard dataOffset >= consumed else {
        throw ShockwaveFileError.invalidOffset(dataOffset)
      }
      try info.seek(toRelativeOffset: dataOffset - consumed)
      let list = try ListItems(parsing: &info)
      infoItems = list.items
      if let textItem = infoItems.first, !textItem.isEmpty {
        scriptText = String(decoding: textItem, as: UTF8.self)
      }
      if infoItems.count > 1 {
        name = ListItems.pascalString(infoItems[1])
      }
    }

    var data = try input.sliceSpan(byteCount: dataLength)
    let specificData = Data(parsingRemainingBytes: &data)

    self.init(
      type: type,
      name: name,
      scriptText: scriptText,
      scriptId: scriptId,
      infoItems: infoItems,
      specificData: specificData
    )
  }
}
