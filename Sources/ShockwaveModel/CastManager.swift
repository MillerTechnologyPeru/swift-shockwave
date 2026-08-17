import LingoRuntime
import ShockwaveFile

/// Owns every cast library in a movie and resolves member lookups across
/// them, mirroring Lingo's `member(number, castLib)` resolution order.
public final class CastManager {
  public private(set) var libraries: [CastLibrary]

  /// Members by lowercased name, first library first — the resolution
  /// order `member("name")` follows. Built once at load: every by-name
  /// lookup (and `new(script("name"))`) otherwise walks every member of
  /// every library, which in a movie with ~1400 members is the dominant
  /// cost of running any script that names a member.
  private let membersByName: [String: CastMember]
  /// Script members by lowercased name, parent scripts winning over other
  /// script types — the preference `new(script(...))` needs.
  private let scriptsByName: [String: CastMember]

  public init(libraries: [CastLibrary]) {
    self.libraries = libraries

    var byName: [String: CastMember] = [:]
    var scripts: [String: CastMember] = [:]
    for library in libraries {
      for member in library.members.values.sorted(by: { $0.memberNumber < $1.memberNumber }) {
        guard let name = member.name?.asciiLowercased(), !name.isEmpty else { continue }
        if byName[name] == nil { byName[name] = member }
        guard member.chunk.type == .script else { continue }
        if member.scriptType == .parent {
          // A parent script wins outright; otherwise first one seen.
          if scripts[name]?.scriptType != .parent { scripts[name] = member }
        } else if scripts[name] == nil {
          scripts[name] = member
        }
      }
    }
    self.membersByName = byName
    self.scriptsByName = scripts
  }

  /// The member a `member("name")` lookup resolves to, or `nil`.
  public func member(named name: String) -> CastMember? {
    membersByName[name.asciiLowercased()]
  }

  /// The script member `new(script("name"))` instantiates, preferring a
  /// parent script when several share the name.
  public func scriptMember(named name: String) -> CastMember? {
    scriptsByName[name.asciiLowercased()]
  }

  public func library(number: Int) -> CastLibrary? {
    libraries.first { $0.number == number }
  }

  public func library(named name: String) -> CastLibrary? {
    libraries.first { $0.libraryName.caseInsensitiveEquals(name) }
  }

  /// Resolves the file-internal owner-id numbering (`CastLibrary.fileNumber`,
  /// the high 16 bits of a cast's key-table owner id). Note the score does
  /// NOT use this numbering: sprite records and behavior references carry
  /// Lingo's library number — the cast's 1-based `MCsL` position — which
  /// diverges from the owner id wherever ids are skipped (junkbot skips 8).
  public func library(fileNumber: Int) -> CastLibrary? {
    libraries.first { $0.fileNumber == fileNumber }
  }

  /// The library a score record's or behavior reference's `castLib` names:
  /// Lingo's library number, i.e. `MCsL` position.
  public func library(scoreCastLib castLib: Int) -> CastLibrary? {
    library(number: castLib)
  }

  public func member(_ reference: ScoreChunk.BehaviorReference) -> CastMember? {
    library(scoreCastLib: reference.castLib)?.member(reference.member)
  }

  /// Looks up a member by number, optionally scoped to one library. With no
  /// library specified, searches every library in order and returns the
  /// first match — mirroring Lingo's `member(number)` behavior when the
  /// cast library is left implicit.
  public func member(number: Int, libraryNumber: Int? = nil) -> CastMember? {
    if let libraryNumber {
      return library(number: libraryNumber)?.member(number)
    }
    for library in libraries {
      if let member = library.member(number) { return member }
    }
    return nil
  }
}
