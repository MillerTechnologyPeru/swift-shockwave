import LingoRuntime

/// The movie: the root Lingo object exposing the cast libraries loaded from
/// a `RIFXFile`. Score/sprite state and `LingoVMHost` conformance are later
/// phases.
public final class Movie: LingoObject {
  public let castManager: CastManager

  public init(castManager: CastManager, environment: LingoEnvironment) {
    self.castManager = castManager
    super.init(environment: environment)
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "castcount": return .integer(castManager.libraries.count)
    default: return super.getProperty(name)
    }
  }
}
