import ShockwaveFile

/// The compositing modes the renderer (and pixel hit-testing) distinguish for a sprite channel's
/// ink value. Director defines many more inks (reverse, blend, darken...);
/// the ones the renderer doesn't implement yet map onto the closest of
/// these three so sprites still show up sensibly.
public enum SpriteInk: Equatable, Sendable {
  /// Ink 0: every pixel composites opaque.
  case copy
  /// Ink 36 ("background transparent"): pixels matching the sprite's
  /// `backColor` are keyed out wherever they appear.
  case backgroundTransparent
  /// Ink 8 ("matte"): like `backgroundTransparent`, but only the keyed
  /// region connected to the bitmap's edges clears — keyed pixels enclosed
  /// by the artwork stay opaque. The key color is the same `backColor`;
  /// the flood fill is the entire difference between the two inks.
  case matte
  /// Ink 3 ("ghost"): keys out `backColor` like the other transparent inks,
  /// and inverts what survives. Director's real operation is `dst = dst &
  /// ~src` on palette indices, which depends on what's already on the
  /// stage; a per-texture conversion can't express that, so the surviving
  /// pixels are RGB-inverted — exact for the black-on-white artwork ghost
  /// is normally used with, approximate for anything else.
  case ghost

  /// Maps a score record's raw ink number onto a renderer mode. Unhandled
  /// inks fall back to `backgroundTransparent`, which was the renderer's
  /// previous behavior for every nonzero ink.
  public init(inkNumber: Int) {
    switch inkNumber {
    case 0: self = .copy
    case 3: self = .ghost
    case 8: self = .matte
    default: self = .backgroundTransparent
    }
  }

  /// Stable 2-bit value for texture cache keys.
  public var cacheBits: Int {
    switch self {
    case .copy: return 0
    case .backgroundTransparent: return 1
    case .matte: return 2
    case .ghost: return 3
    }
  }
}
