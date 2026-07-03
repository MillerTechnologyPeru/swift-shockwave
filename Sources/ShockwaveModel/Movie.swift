import LingoRuntime

/// The movie: the root Lingo object exposing the cast libraries and score
/// loaded from a `RIFXFile`. The frame loop and `LingoVMHost` conformance
/// are later phases.
public final class Movie: LingoObject {
  public let castManager: CastManager
  public let score: Score?

  public init(castManager: CastManager, score: Score?, environment: LingoEnvironment) {
    self.castManager = castManager
    self.score = score
    super.init(environment: environment)
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "castcount": return .integer(castManager.libraries.count)
    case "lastframe": return .integer(score?.frameCount ?? 0)
    default: return super.getProperty(name)
    }
  }
}
