import LingoRuntime

/// A sprite channel as Lingo sees it. Headless: a permissive property bag
/// (`puppet`, `member`, `locH`, ...) plus its channel number — no geometry
/// or rendering behavior.
public final class Sprite: LingoObject {
  public let spriteNumber: Int
  private var properties: [String: LingoValue] = [:]

  public init(spriteNumber: Int, environment: LingoEnvironment) {
    self.spriteNumber = spriteNumber
    super.init(environment: environment)
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "spritenum": return .integer(spriteNumber)
    default:
      if let value = properties[name.asciiLowercased()] {
        return value
      }
      return super.getProperty(name)
    }
  }

  public override func setProperty(_ name: String, value: LingoValue) {
    properties[name.asciiLowercased()] = value
  }
}
