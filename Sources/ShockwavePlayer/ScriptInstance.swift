import LingoBytecode
import LingoRuntime
import LingoVM
import ShockwaveModel

/// A live instance of a parent script (or behavior): the `me` object Lingo
/// code sees. Properties live in a case-insensitive bag seeded from the
/// script's declared property defaults; methods dispatch into `LingoVM`
/// against the member's compiled `ScriptChunk`.
public final class ScriptInstance: LingoObject {
  public let member: CastMember
  private unowned let player: MoviePlayer
  private var properties: [String: LingoValue]

  init(member: CastMember, player: MoviePlayer) {
    self.member = member
    self.player = player
    var properties: [String: LingoValue] = [:]
    if let chunk = member.scriptChunk {
      for nameId in chunk.propertyNameIDs {
        guard let name = member.scriptNames[safe: Int(nameId)] else { continue }
        let value = chunk.propertyDefaults[nameId].map(LingoValue.init(literal:)) ?? .void
        properties[name.asciiLowercased()] = value
      }
    }
    self.properties = properties
    super.init(environment: player.movieModel.lingoEnvironment)
  }

  public func handler(named name: String) -> HandlerDef? {
    guard let chunk = member.scriptChunk else { return nil }
    return chunk.handlers.first {
      member.scriptNames[safe: Int($0.nameId)]?.caseInsensitiveEquals(name) ?? false
    }
  }

  public override func getProperty(_ name: String) -> LingoValue {
    if let value = properties[name.asciiLowercased()] {
      return value
    }
    return super.getProperty(name)
  }

  public override func setProperty(_ name: String, value: LingoValue) {
    properties[name.asciiLowercased()] = value
  }

  public override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
    if let handler = handler(named: name), let chunk = member.scriptChunk {
      let result = try? LingoVM.call(
        handler: handler, chunk: chunk, names: member.scriptNames, args: args, receiver: self,
        host: player, environment: lingoEnvironment, version: player.lingoVersion,
        capitalX: member.scriptUsesCapitalContext)
      return result ?? .void
    }
    return super.callMethod(name, args: args)
  }
}

extension LingoValue {
  init(literal: LiteralValue) {
    switch literal {
    case .int(let value): self = .integer(Int(value))
    case .double(let value): self = .float(value)
    case .string(let value): self = .string(value)
    case .invalid, .javascript: self = .void
    }
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
