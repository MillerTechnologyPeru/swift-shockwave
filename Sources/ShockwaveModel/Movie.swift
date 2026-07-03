import LingoRuntime

/// The movie: the root Lingo object exposing the cast libraries and score
/// loaded from a `RIFXFile`. The frame loop and `LingoVMHost` conformance
/// are later phases.
public final class Movie: LingoObject {
  public let castManager: CastManager
  public let score: Score?
  /// The config chunk's file-format version code (e.g. `0x640` for a
  /// Director 7-era file), or 0 when the movie has no config chunk.
  public let fileVersion: Int

  // `the actorList`, `the exitLock`, `the itemDelimiter`, ... — movie
  // properties scripts read and write freely. Stored permissively rather
  // than enumerated, matching Lingo's own tolerance.
  private var dynamicProperties: [String: LingoValue] = [:]

  public init(
    castManager: CastManager, score: Score?, fileVersion: Int = 0,
    environment: LingoEnvironment
  ) {
    self.castManager = castManager
    self.score = score
    self.fileVersion = fileVersion
    super.init(environment: environment)
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "castcount": return .integer(castManager.libraries.count)
    case "lastframe": return .integer(score?.frameCount ?? 0)
    default:
      if let value = dynamicProperties[name.asciiLowercased()] {
        return value
      }
      return super.getProperty(name)
    }
  }

  public override func setProperty(_ name: String, value: LingoValue) {
    dynamicProperties[name.asciiLowercased()] = value
  }
}
