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
/// sprite means. `MoviePlayer.effectiveRecord(forSprite:)` folds them back
/// over the score record so drawing and hit-testing see the same sprite
/// Lingo does — including channels the score never populated, which is how
/// the sample's playfield manager shows a level: it pulls sprites 200–999
/// from a pool and gives each a member, a loc, a size and an ink.
public final class Sprite: LingoObject {
  public let spriteNumber: Int
  private weak var player: MoviePlayer?
  private var properties: [String: LingoValue] = [:]

  public init(spriteNumber: Int, player: MoviePlayer?, environment: LingoEnvironment) {
    self.spriteNumber = spriteNumber
    self.player = player
    super.init(environment: environment)
  }

  /// A property the running Lingo has explicitly set on this sprite, or
  /// `nil` when it hasn't — the score's value is not consulted.
  public func puppeted(_ name: String) -> LingoValue? {
    properties[name.asciiLowercased()]
  }

  /// The behaviors Lingo attached at runtime through
  /// `sprite.scriptInstanceList.add(...)`, in attachment order. Empty
  /// until something is added; the list is created on first read so
  /// `.add` has something to add to.
  public var scriptInstances: [LingoObject] {
    guard case .listType(let list) = getProperty("scriptInstanceList") else { return [] }
    return list.elements.compactMap {
      if case .object(let object) = $0 { return object }
      return nil
    }
  }

  public override func getProperty(_ name: String) -> LingoValue {
    let key = name.asciiLowercased()
    if key == "spritenum" { return .integer(spriteNumber) }
    if let value = properties[key] { return value }

    switch key {
    // Composite properties are views over locH/locV and the rect.
    case "loc":
      return .list([getProperty("locH"), getProperty("locV")])
    case "rect":
      return .list([
        getProperty("left"), getProperty("top"), getProperty("right"), getProperty("bottom"),
      ])
    case "scriptinstancelist":
      let list = LingoValue.list([])
      properties[key] = list
      return list
    default:
      break
    }

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
    let key = name.asciiLowercased()
    switch key {
    case "loc":
      // `sprite.loc = point(h, v)` (or an `[h, v]` list) sets both halves.
      properties["loch"] = value[.integer(1)]
      properties["locv"] = value[.integer(2)]
    case "member":
      // Scripts assign a member by object, name or number; store the
      // resolved member so every reader sees the same thing.
      if case .object = value {
        properties[key] = value
      } else if let player, let member = player.member(value, castLib: nil) {
        properties[key] = .object(member)
      } else {
        properties[key] = value
      }
    default:
      properties[key] = value
    }
  }
}
