import LingoRuntime
import ShockwaveFile

/// One cast library: its `MCsL` metadata plus its members, keyed by member
/// number (not necessarily 0- or 1-based — `minMember` can skip leading
/// blank slots).
public final class CastLibrary: LingoObject {
  public let number: Int
  /// The file-internal library number (`CastListEntry.resourceId >> 16`) that
  /// `Sord` and score behavior references use as their `castLib`, or `nil`
  /// for the internal cast, which has no resource id. Distinct from `number`,
  /// the 1-based `MCsL` position that Lingo's `castLib` numbering follows.
  public let fileNumber: Int?
  public let libraryName: String
  public let filePath: String
  public let preloadMode: Int
  public private(set) var members: [Int: CastMember]

  public init(
    number: Int,
    entry: CastListEntry,
    members: [Int: CastMember],
    environment: LingoEnvironment
  ) {
    self.number = number
    self.fileNumber = entry.resourceId.map { $0 >> 16 }
    self.libraryName = entry.name
    self.filePath = entry.filePath
    self.preloadMode = Int(entry.preloadMode ?? 0)
    self.members = members
    super.init(environment: environment)
  }

  public var memberCount: Int { members.count }
  public var minMember: Int { members.keys.min() ?? 0 }
  public var maxMember: Int { members.keys.max() ?? 0 }

  public func member(_ number: Int) -> CastMember? {
    members[number]
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "name": return .string(libraryName)
    case "filename", "pathname": return .string(filePath)
    case "preloadmode": return .integer(preloadMode)
    case "membercount": return .integer(memberCount)
    case "minmember": return .integer(minMember)
    case "maxmember": return .integer(maxMember)
    default: return super.getProperty(name)
    }
  }
}
