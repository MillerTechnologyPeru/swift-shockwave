import LingoRuntime
import ShockwaveFile

/// Owns every cast library in a movie and resolves member lookups across
/// them, mirroring Lingo's `member(number, castLib)` resolution order.
public final class CastManager {
  public private(set) var libraries: [CastLibrary]

  public init(libraries: [CastLibrary]) {
    self.libraries = libraries
  }

  public func library(number: Int) -> CastLibrary? {
    libraries.first { $0.number == number }
  }

  public func library(named name: String) -> CastLibrary? {
    libraries.first { $0.libraryName.caseInsensitiveEquals(name) }
  }

  /// Resolves the file-internal library numbering used by `Sord` entries and
  /// score behavior references (`CastLibrary.fileNumber`).
  public func library(fileNumber: Int) -> CastLibrary? {
    libraries.first { $0.fileNumber == fileNumber }
  }

  public func member(_ reference: ScoreChunk.BehaviorReference) -> CastMember? {
    library(fileNumber: reference.castLib)?.member(reference.member)
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
