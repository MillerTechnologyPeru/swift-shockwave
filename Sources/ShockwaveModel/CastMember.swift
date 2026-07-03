import LingoBytecode
import LingoRuntime
import ShockwaveFile

/// How a script cast member is scoped, from the `CASt` chunk's type-specific
/// data (`1` = score/behavior, `3` = movie, `7` = parent).
public enum ScriptMemberType: Int, Sendable {
  case score = 1
  case movie = 3
  case parent = 7
}

/// A single cast member: its parsed `CASt` chunk plus, if it carries one
/// (scripts, and cast members with a behavior attached), its compiled Lingo
/// script from the cast's `Lctx`/`Lscr` chunks.
public final class CastMember: LingoObject {
  public let libraryNumber: Int
  public let memberNumber: Int
  public let chunk: CastMemberChunk
  public let scriptChunk: ScriptChunk?
  /// The name table of the cast's `Lnam` chunk — the one `scriptChunk`'s
  /// name ids index into for `LingoVM.call`/`LingoBytecode.decompile`.
  public let scriptNames: [String]
  /// Whether the cast's script context is the newer `LctX` form, which
  /// addresses variables directly (`capitalX` in `LingoVM.call` terms).
  public let scriptUsesCapitalContext: Bool

  private var nameOverride: String?
  private var scriptTextOverride: String?
  private var dynamicProperties: [String: LingoValue] = [:]

  public init(
    libraryNumber: Int,
    memberNumber: Int,
    chunk: CastMemberChunk,
    scriptChunk: ScriptChunk?,
    scriptNames: [String] = [],
    scriptUsesCapitalContext: Bool = false,
    environment: LingoEnvironment
  ) {
    self.libraryNumber = libraryNumber
    self.memberNumber = memberNumber
    self.chunk = chunk
    self.scriptChunk = scriptChunk
    self.scriptNames = scriptNames
    self.scriptUsesCapitalContext = scriptUsesCapitalContext
    super.init(environment: environment)
  }

  /// `castLibIndex - 1` in the high 16 bits, member number in the low 16 —
  /// the encoding the XDK's `number` property documents.
  public var number: Int {
    ((libraryNumber - 1) << 16) | memberNumber
  }

  public var name: String? {
    nameOverride ?? chunk.name
  }

  /// The script scope for script members (`nil` for every other member
  /// type, or when the stored value is unrecognized).
  public var scriptType: ScriptMemberType? {
    guard chunk.type == .script, chunk.specificData.count >= 2 else { return nil }
    let raw =
      Int(chunk.specificData[chunk.specificData.startIndex]) << 8
      | Int(chunk.specificData[chunk.specificData.startIndex + 1])
    return ScriptMemberType(rawValue: raw)
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "name": return .string(self.name ?? "")
    case "number": return .integer(number)
    case "membernum": return .integer(memberNumber)
    case "castlibnum": return .integer(libraryNumber)
    case "type", "casttype": return .symbol(chunk.type.lingoSymbolName)
    case "scripttext": return .string(scriptTextOverride ?? chunk.scriptText ?? "")
    default:
      if let value = dynamicProperties[name.asciiLowercased()] {
        return value
      }
      return super.getProperty(name)
    }
  }

  public override func setProperty(_ name: String, value: LingoValue) {
    switch name.asciiLowercased() {
    case "name": nameOverride = value.asString()
    case "scripttext": scriptTextOverride = value.asString()
    default: dynamicProperties[name.asciiLowercased()] = value
    }
  }
}
