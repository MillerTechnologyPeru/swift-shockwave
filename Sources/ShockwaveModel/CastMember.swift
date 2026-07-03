import LingoBytecode
import LingoRuntime
import ShockwaveFile

/// A single cast member: its parsed `CASt` chunk plus, if it carries one
/// (scripts, and cast members with a behavior attached), its compiled Lingo
/// script from the cast's `Lctx`/`Lscr` chunks.
public final class CastMember: LingoObject {
  public let libraryNumber: Int
  public let memberNumber: Int
  public let chunk: CastMemberChunk
  public let scriptChunk: ScriptChunk?

  private var nameOverride: String?
  private var scriptTextOverride: String?

  public init(
    libraryNumber: Int,
    memberNumber: Int,
    chunk: CastMemberChunk,
    scriptChunk: ScriptChunk?,
    environment: LingoEnvironment
  ) {
    self.libraryNumber = libraryNumber
    self.memberNumber = memberNumber
    self.chunk = chunk
    self.scriptChunk = scriptChunk
    super.init(environment: environment)
  }

  /// `castLibIndex - 1` in the high 16 bits, member number in the low 16 —
  /// the encoding the XDK's `number` property documents.
  public var number: Int {
    ((libraryNumber - 1) << 16) | memberNumber
  }

  public override func getProperty(_ name: String) -> LingoValue {
    switch name.asciiLowercased() {
    case "name": return .string(nameOverride ?? chunk.name ?? "")
    case "number": return .integer(number)
    case "type", "casttype": return .symbol(chunk.type.lingoSymbolName)
    case "scripttext": return .string(scriptTextOverride ?? chunk.scriptText ?? "")
    default: return super.getProperty(name)
    }
  }

  public override func setProperty(_ name: String, value: LingoValue) {
    switch name.asciiLowercased() {
    case "name": nameOverride = value.asString()
    case "scripttext": scriptTextOverride = value.asString()
    default: super.setProperty(name, value: value)
    }
  }
}
