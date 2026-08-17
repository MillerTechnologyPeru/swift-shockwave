import LingoRuntime
import ShockwaveModel

/// A sprite channel as Lingo sees it.
///
/// Reads fall back to the score: a channel the running Lingo has never
/// touched still has the position, size, and member the movie authored, so
/// `sprite(21).locV` answers where the sprite actually is rather than VOID.
/// That matters because scripts routinely read a property, adjust it, and
/// write it back (`sprite(i).locV = sprite(i).locV - 80`) — starting from
/// VOID makes the whole expression VOID and the sprite never moves.
///
/// Writes are stored here and win from then on, which is what puppeting a
/// sprite means.
public final class Sprite: LingoObject {
  public let spriteNumber: Int
  private weak var player: MoviePlayer?
  private var properties: [String: LingoValue] = [:]

  public init(spriteNumber: Int, player: MoviePlayer?, environment: LingoEnvironment) {
    self.spriteNumber = spriteNumber
    self.player = player
    super.init(environment: environment)
  }

  public override func getProperty(_ name: String) -> LingoValue {
    let key = name.asciiLowercased()
    if key == "spritenum" { return .integer(spriteNumber) }
    if let value = properties[key] { return value }

    guard let player, let record = player.currentRecord(forSprite: spriteNumber) else {
      return super.getProperty(name)
    }
    switch key {
    // `locH`/`locV` are where the member's registration point sits, which
    // is exactly what the score record stores.
    case "loch": return .integer(record.left)
    case "locv": return .integer(record.top)
    case "width": return .integer(player.spriteRect(record, spriteNumber: spriteNumber).width)
    case "height": return .integer(player.spriteRect(record, spriteNumber: spriteNumber).height)
    case "left": return .integer(player.spriteRect(record, spriteNumber: spriteNumber).left)
    case "top": return .integer(player.spriteRect(record, spriteNumber: spriteNumber).top)
    case "right": return .integer(player.spriteRect(record, spriteNumber: spriteNumber).right)
    case "bottom": return .integer(player.spriteRect(record, spriteNumber: spriteNumber).bottom)
    case "ink": return .integer(record.ink)
    case "forecolor": return .integer(record.foreColor)
    case "backcolor": return .integer(record.backColor)
    case "blend": return .integer(record.blendPercent)
    case "visible": return .integer(1)
    case "member", "castnum":
      // Resolved straight from the record rather than through
      // `effectiveMember`, which asks the sprite for a puppeted member and
      // would come back here.
      guard
        let member = player.movieModel.castManager.library(scoreCastLib: record.castLib)?
          .member(record.member)
      else { return super.getProperty(name) }
      return key == "member" ? .object(member) : .integer(member.memberNumber)
    default:
      return super.getProperty(name)
    }
  }

  public override func setProperty(_ name: String, value: LingoValue) {
    properties[name.asciiLowercased()] = value
  }
}
