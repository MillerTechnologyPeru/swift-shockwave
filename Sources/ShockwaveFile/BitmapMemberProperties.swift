import Foundation

/// The decoded type-specific data of a bitmap `CASt` member: everything
/// needed to interpret its `BITD` pixel data.
///
/// Layout (28 bytes, big-endian): row-byte count with the high bit set,
/// bounds rect, alpha threshold, 6 undecoded bytes, registration point
/// (y then x, in the rect's coordinate space), flags, bits per pixel, and
/// a palette reference. Validated against every bitmap in the junkbot
/// sample: game pieces register bottom-left, cursors at their hotspot,
/// full-stage backgrounds at the top-left, and `rowBytes × rect.height`
/// matches the decoded `BITD` size for all 1085 members.
public struct BitmapMemberProperties: Equatable, Sendable {
  /// Bytes per row of pixel data (already padded to the storage alignment).
  public var rowBytes: Int
  public var bounds: DirectorRect
  public var regY: Int
  public var regX: Int
  public var bitsPerPixel: Int
  /// Palette reference: `castLib` and `member` of a `CLUT` cast member, or
  /// a negative `member` denoting a built-in system palette.
  public var paletteCastLib: Int
  public var paletteMember: Int

  public init(
    rowBytes: Int, bounds: DirectorRect, regY: Int, regX: Int, bitsPerPixel: Int,
    paletteCastLib: Int, paletteMember: Int
  ) {
    self.rowBytes = rowBytes
    self.bounds = bounds
    self.regY = regY
    self.regX = regX
    self.bitsPerPixel = bitsPerPixel
    self.paletteCastLib = paletteCastLib
    self.paletteMember = paletteMember
  }

  public init?(specificData: Data) {
    let bytes = [UInt8](specificData)
    guard bytes.count >= 24 else { return nil }
    func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
    func i16(_ offset: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(offset)))) }
    rowBytes = u16(0) & 0x3FFF
    bounds = DirectorRect(top: i16(2), left: i16(4), bottom: i16(6), right: i16(8))
    regY = i16(18)
    regX = i16(20)
    bitsPerPixel = Int(bytes[23])
    if bytes.count >= 28 {
      paletteCastLib = i16(24)
      paletteMember = i16(26)
    } else {
      paletteCastLib = 0
      paletteMember = 0
    }
  }

  /// The expected size of the decoded pixel data.
  public var decodedByteCount: Int {
    rowBytes * bounds.height
  }
}

extension CastMemberChunk {
  /// Decodes the bitmap-specific data for bitmap members; `nil` for every
  /// other member type.
  public var bitmapProperties: BitmapMemberProperties? {
    guard type == .bitmap else { return nil }
    return BitmapMemberProperties(specificData: specificData)
  }
}
