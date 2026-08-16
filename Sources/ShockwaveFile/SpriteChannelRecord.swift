/// One sprite channel's decoded state from a score frame (the 48-byte
/// record format used by Director 6+ scores).
///
/// Layout (big-endian): sprite type, the packed ink byte, foreColor,
/// backColor, `castLib u16`, `member u16` (file-internal library numbering,
/// like score behavior references), the sprite's behavior-interval entry id,
/// then the display rect as top/left/height/width, then the packed color
/// code and blend amount. Validated against the junkbot sample: unscaled
/// bitmap sprites' height/width match their member's bounds exactly, and
/// member refs resolve to real cast members (except those pointing into its
/// runtime-populated casts).
///
/// Only bit 0x10 of byte 22 is decoded, as the blend-enabled flag. The rest
/// of that byte is disputed — line/text thickness in the Director 6 layout,
/// flip flags in the Director 8.5 one — and the junkbot sample can't settle
/// it. Rotation and skew (bytes 28–35) are likewise left alone: they are
/// 0.0 in all 4576 of the sample's records.
public struct SpriteChannelRecord: Equatable, Sendable {
  public var spriteType: Int
  /// The ink mode, bits 0–5 of the ink byte. The two high bits are separate
  /// flags (`trails` and `stretch`), not part of the ink number.
  public var ink: Int
  /// Whether the sprite leaves a trail (the score's "trails" toggle): the
  /// stage isn't erased under it between frames.
  public var trails: Bool
  /// Whether the sprite is stretched to its display rect rather than drawn
  /// at the member's natural size.
  public var stretch: Bool
  public var foreColor: Int
  public var backColor: Int
  public var castLib: Int
  public var member: Int
  public var top: Int
  public var left: Int
  public var height: Int
  public var width: Int
  /// The sprite's score-window color, bits 0–3 of the color-code byte. A
  /// authoring-time annotation with no effect on the rendered stage.
  public var scoreColor: Int
  /// Whether the sprite's text is editable at runtime.
  public var isEditable: Bool
  /// Whether the sprite can be dragged at runtime.
  public var isMoveable: Bool
  /// The raw blend byte, meaningful only when `blendEnabled`.
  public var blendAmount: Int
  /// Whether the blend byte carries an authored value. When clear, the
  /// blend byte is a junk default and the sprite draws fully opaque —
  /// which is why the junkbot sample stores 0 in 4562 records without
  /// every sprite being invisible.
  public var blendEnabled: Bool

  public init?(bytes: [UInt8]) {
    guard bytes.count >= 20 else { return nil }
    func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
    func i16(_ offset: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(offset)))) }
    spriteType = Int(bytes[0])
    ink = Int(bytes[1] & 0x3F)
    trails = bytes[1] & 0x40 != 0
    stretch = bytes[1] & 0x80 != 0
    foreColor = Int(bytes[2])
    backColor = Int(bytes[3])
    castLib = u16(4)
    member = u16(6)
    top = i16(12)
    left = i16(14)
    height = i16(16)
    width = i16(18)
    scoreColor = bytes.count > 20 ? Int(bytes[20] & 0x0F) : 0
    isEditable = bytes.count > 20 && bytes[20] & 0x40 != 0
    isMoveable = bytes.count > 20 && bytes[20] & 0x80 != 0
    blendAmount = bytes.count > 21 ? Int(bytes[21]) : 0
    blendEnabled = bytes.count > 22 && bytes[22] & 0x10 != 0
  }

  /// The sprite's opacity as Director's 0–100 percentage. The stored byte
  /// runs backwards (0 is opaque, 255 is invisible) and only counts when
  /// `blendEnabled`; everything else draws fully opaque.
  public var blendPercent: Int {
    guard blendEnabled else { return 100 }
    return Int((Double(255 - blendAmount) * 100 / 255).rounded())
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
