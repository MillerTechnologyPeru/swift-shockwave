import ShockwaveFile

extension CastMemberType {
  /// The symbol Lingo's `castType`/`type` properties return for this
  /// member type.
  public var lingoSymbolName: String {
    switch self {
    case .bitmap: return "bitmap"
    case .filmLoop: return "filmLoop"
    case .field: return "text"
    case .palette: return "palette"
    case .picture: return "picture"
    case .sound: return "sound"
    case .button: return "button"
    case .shape: return "shape"
    case .movie: return "movie"
    case .digitalVideo: return "digitalVideo"
    case .script: return "script"
    case .richText: return "richText"
    case .ole: return "OLE"
    case .transition: return "transition"
    case .xtra: return "xtra"
    case .unknown: return "empty"
    }
  }
}
