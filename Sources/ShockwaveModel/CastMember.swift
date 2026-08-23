import Foundation
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
  /// The index of this member's `CASt` chunk in the file's chunk map — the
  /// owner id its media (`BITD`, `STXT`, `XMED`) hangs off in the key
  /// table. `nil` for members not backed by the file.
  public let chunkId: Int?
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

  /// The member's authored text (from its `STXT` chunk), or `nil` for
  /// members without one. Scripts overwrite it through the `text` property;
  /// this keeps the movie's original.
  public let authoredText: String?
  /// The typeface a text xtra member is set in (from its `XMED` styling),
  /// or `nil` for members that carry none.
  public let textStyle: XMediaText.Style?
  /// A text xtra member's own box (from its `XMED` header): the width its
  /// text wraps to, and its height. Sprites showing it take this size
  /// unless the score stretches them — the score record's size can be
  /// stale for text.
  public let textBox: (width: Int, height: Int)?
  /// A bitmap member's raw `BITD` payload (compressed or not), or `nil`
  /// for members that have none. Decoded on demand by whoever draws or
  /// hit-tests it.
  public let bitmapData: Data?
  /// A font member's embedded typeface — the movie ships the font itself,
  /// so text set in it draws the same everywhere.
  public let embeddedFont: PFRFont?
  /// A film loop member's own score — the frames it plays — or `nil` for
  /// every other member type (and for a loop whose score didn't parse).
  public let filmLoopScore: ScoreChunk?
  /// A sound member's raw `snd ` resource, or `nil` for every other type.
  public let soundData: Data?
  /// A compressed (Shockwave Audio) sound member's media, or `nil`.
  public let shockwaveAudio: ShockwaveAudioMedia?
  private var decodedSound: SoundResource??

  public init(
    libraryNumber: Int,
    memberNumber: Int,
    chunkId: Int? = nil,
    chunk: CastMemberChunk,
    scriptChunk: ScriptChunk?,
    scriptNames: [String] = [],
    scriptUsesCapitalContext: Bool = false,
    authoredText: String? = nil,
    textStyle: XMediaText.Style? = nil,
    textBox: (width: Int, height: Int)? = nil,
    embeddedFont: PFRFont? = nil,
    bitmapData: Data? = nil,
    filmLoopScore: ScoreChunk? = nil,
    soundData: Data? = nil,
    shockwaveAudio: ShockwaveAudioMedia? = nil,
    environment: LingoEnvironment
  ) {
    self.libraryNumber = libraryNumber
    self.memberNumber = memberNumber
    self.chunkId = chunkId
    self.chunk = chunk
    self.scriptChunk = scriptChunk
    self.scriptNames = scriptNames
    self.scriptUsesCapitalContext = scriptUsesCapitalContext
    self.authoredText = authoredText
    self.textStyle = textStyle
    self.textBox = textBox
    self.embeddedFont = embeddedFont
    self.bitmapData = bitmapData
    self.filmLoopScore = filmLoopScore
    self.soundData = soundData
    self.shockwaveAudio = shockwaveAudio
    super.init(environment: environment)
  }

  /// How a text member lays out: what the movie authored, overridden by
  /// whatever the running Lingo has set on it (`member("x").fixedLineSpace
  /// = 21`, `.alignment = #right`, `.font`, `.fontSize`).
  public struct TextLayout: Equatable, Sendable {
    public var fontName: String?
    public var fontSize: Int
    /// A fixed line pitch in pixels, or 0 for the font's natural leading.
    public var fixedLineSpace: Int
    /// `left`, `center` or `right`.
    public var alignment: String
  }

  /// Whether the member shows text (field, text xtra, rich text, button).
  public var isTextMember: Bool {
    switch chunk.type {
    case .field, .button, .richText, .xtra: return true
    default: return false
    }
  }

  public var textLayout: TextLayout {
    let fontName = dynamicProperties["font"]?.asString() ?? textStyle?.fontName
    let fontSize = dynamicProperties["fontsize"]?.asInteger() ?? textStyle?.fontSize ?? 12
    let spacing = dynamicProperties["fixedlinespace"]?.asInteger() ?? textStyle?.fixedLineSpace ?? 0
    let alignment =
      dynamicProperties["alignment"]?.asString().lowercased() ?? textStyle?.alignment ?? "left"
    return TextLayout(
      fontName: fontName, fontSize: fontSize, fixedLineSpace: spacing, alignment: alignment)
  }

  /// A sound member's decoded samples, or `nil` when it has none or they
  /// aren't plain PCM (compressed members decode through the player's
  /// `compressedSoundDecoder`, and land in `decodedSound` from there).
  /// Decoded once, on first use.
  public var sound: SoundResource? {
    if let decodedSound { return decodedSound }
    let decoded = soundData.flatMap { SoundResource(sndResource: $0) }
    decodedSound = .some(decoded)
    return decoded
  }

  /// Installs samples decoded elsewhere (a compressed member's MP3
  /// bitstream) as this member's sound.
  public func setDecodedSound(_ sound: SoundResource?) {
    decodedSound = .some(sound)
  }

  /// The member's bitmap composited under `ink` with `backColor` as the
  /// key, as RGBA at the member's natural size — what the renderer
  /// uploads and what hit-testing reads coverage from. `nil` for anything
  /// but a decodable bitmap.
  public func rgba(ink: SpriteInk, backColorIndex: Int) -> [UInt8]? {
    guard let properties = chunk.bitmapProperties, let bitmapData,
      let decoded = BitmapData.decode(bitmapData, expectedByteCount: properties.decodedByteCount)
    else { return nil }
    return BitmapConversion.rgba(
      pixels: decoded.pixels, properties: properties,
      palette: BuiltinPalette.colors(forMember: properties.paletteMember),
      ink: ink, backColorIndex: backColorIndex, sourcePlanar: decoded.wasCompressed)
  }

  /// The member's current text: a script-set value wins, else the authored
  /// `STXT` content.
  public var text: String? {
    if let override = dynamicProperties["text"] { return override.asString() }
    return authoredText
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
    case "text":
      // `member(...).text` — dynamic writes win over the authored STXT
      // content; a member with neither answers empty string, as Lingo does.
      if let value = dynamicProperties["text"] { return value }
      return .string(authoredText ?? "")
    case "duration":
      // A sound's playing time in milliseconds; the sample's music code
      // queues clips as `[#member: m, #startTime: 0, #endTime: m.duration]`.
      if let sound { return .integer(sound.durationMilliseconds) }
      if let shockwaveAudio { return .integer(shockwaveAudio.durationMilliseconds) }
      return super.getProperty(name)
    case "font":
      if let value = dynamicProperties["font"] { return value }
      return textStyle.map { .string($0.fontName) } ?? super.getProperty(name)
    case "fontsize":
      if let value = dynamicProperties["fontsize"] { return value }
      return textStyle.map { .integer($0.fontSize) } ?? super.getProperty(name)
    // A bitmap's natural size and registration point — what
    // `s.width = s.member.width * scale` and `loc - member.regPoint` read.
    case "width":
      guard let bitmap = chunk.bitmapProperties else { return super.getProperty(name) }
      return .integer(bitmap.bounds.width)
    case "height":
      guard let bitmap = chunk.bitmapProperties else { return super.getProperty(name) }
      return .integer(bitmap.bounds.height)
    case "regpoint":
      guard let bitmap = chunk.bitmapProperties else { return super.getProperty(name) }
      return .list([.integer(bitmap.regX), .integer(bitmap.regY)])
    case "rect":
      guard let bitmap = chunk.bitmapProperties else { return super.getProperty(name) }
      return .list([
        .integer(0), .integer(0), .integer(bitmap.bounds.width), .integer(bitmap.bounds.height),
      ])
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
