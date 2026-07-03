/// One sprite channel's decoded state from a score frame (the 48-byte
/// record format used by Director 6+ scores).
///
/// Layout (big-endian): sprite type, ink (low 7 bits), foreColor, backColor,
/// `castLib u16`, `member u16` (file-internal library numbering, like score
/// behavior references), the sprite's behavior-interval entry id, then the
/// display rect as top/left/height/width. Validated against the junkbot
/// sample: unscaled bitmap sprites' height/width match their member's
/// bounds exactly, and member refs resolve to real cast members (except
/// those pointing into its runtime-populated casts).
public struct SpriteChannelRecord: Equatable, Sendable {
  public var spriteType: Int
  public var ink: Int
  public var foreColor: Int
  public var backColor: Int
  public var castLib: Int
  public var member: Int
  public var top: Int
  public var left: Int
  public var height: Int
  public var width: Int

  public init?(bytes: [UInt8]) {
    guard bytes.count >= 20 else { return nil }
    func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
    func i16(_ offset: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(offset)))) }
    spriteType = Int(bytes[0])
    ink = Int(bytes[1] & 0x7F)
    foreColor = Int(bytes[2])
    backColor = Int(bytes[3])
    castLib = u16(4)
    member = u16(6)
    top = i16(12)
    left = i16(14)
    height = i16(16)
    width = i16(18)
  }

  /// Whether the channel actually shows something (an empty channel record
  /// carries no member reference).
  public var isPopulated: Bool {
    castLib != 0 || member != 0
  }
}

extension ScoreChunk.Frame {
  /// Decodes the sprite record for a channel (Lingo sprite `n` is channel
  /// `n + 5`), or `nil` when the channel is untouched or empty.
  public func spriteRecord(channel: Int) -> SpriteChannelRecord? {
    guard let bytes = channels[channel],
      let record = SpriteChannelRecord(bytes: bytes),
      record.isPopulated
    else { return nil }
    return record
  }
}
