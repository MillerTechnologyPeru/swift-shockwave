/// The tempo channel's decoded state from a score frame (channel index 1,
/// Director 6+ uniform record layout — same fixed-size-record shell
/// `SpriteChannelRecord` uses for sprite channels).
///
/// Layout (big-endian): sprite-detail-table index, tempo cue point, tempo
/// mode/value byte, color tempo, wait flags, channel flags, 6 skipped
/// bytes, frame-specific data.
public struct TempoChannelRecord: Equatable, Sendable {
  public var spriteListIndex: Int
  public var tempoCuePoint: Int
  public var tempo: Int
  public var colorTempo: Int

  public init?(bytes: [UInt8]) {
    guard bytes.count >= 12 else { return nil }
    func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
    func u32(_ offset: Int) -> Int {
      Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8
        | Int(bytes[offset + 3])
    }
    spriteListIndex = u32(0)
    tempoCuePoint = u16(4)
    tempo = Int(bytes[6])
    colorTempo = Int(bytes[7])
  }

  /// A "no change" marker carried in the delta buffer rather than an actual
  /// tempo setting (high 16 bits of the sprite-list index read as `0xFFFE`).
  public var isDefaultMarker: Bool {
    (spriteListIndex >> 16) == 0xFFFE
  }

  public var isEmpty: Bool {
    spriteListIndex == 0 && tempo == 0
  }
}

extension ScoreChunk.Frame {
  /// Decodes the tempo channel (channel 1) for this frame, or `nil` when
  /// it's untouched, a delta "no change" marker, or carries no tempo data.
  public func tempoRecord() -> TempoChannelRecord? {
    guard let bytes = channels[1],
      let record = TempoChannelRecord(bytes: bytes),
      !record.isDefaultMarker, !record.isEmpty
    else { return nil }
    return record
  }
}
