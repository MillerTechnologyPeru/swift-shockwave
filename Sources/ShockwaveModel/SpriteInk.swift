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
  /// is normally used with, approximate for anything else. The reverse
  /// family (2, 4, 5, 6) shares this treatment, with and without keying.
  case ghost
  /// Inks 2/4/6 ("reverse", "not copy", "not reverse"): the source drawn
  /// RGB-inverted, every pixel opaque.
  case notCopy
  /// Ink 9 ("mask"): the next cast member's artwork is the stencil — the
  /// sprite shows only where the mask is dark. Needs the neighboring
  /// member, so the renderer applies it; the pixel pass treats it as copy.
  case mask
  /// Ink 32 ("blend"): plain alpha compositing at the sprite's blend
  /// percentage, which every draw already applies.
  case blend
  /// Inks 33/34 ("add pin", "add"): the source added onto the stage,
  /// saturating. Black adds nothing, so no keying is needed.
  case add
  /// Inks 35/38 ("subtract pin", "subtract"): the source subtracted from
  /// the stage, clamping at black.
  case subtract
  /// Ink 37 ("lightest"): per-channel maximum of source and stage.
  case lightest
  /// Ink 39 ("darkest"): per-channel minimum.
  case darkest
  /// Ink 41 ("darken"): the source multiplied onto the stage; white
  /// leaves it untouched.
  case darken

  /// Maps a score record's raw ink number onto a renderer mode. Ink 1
  /// ("transparent"), 5/7 ("not transparent"/"not ghost") and 40
  /// ("lighten") all key the background out of otherwise-plain drawing,
  /// which is `backgroundTransparent`; anything unknown falls back there
  /// too, the renderer's long-standing behavior for nonzero inks.
  public init(inkNumber: Int) {
    switch inkNumber {
    case 0: self = .copy
    case 2, 4, 6: self = .notCopy
    case 3: self = .ghost
    case 8: self = .matte
    case 9: self = .mask
    case 32: self = .blend
    case 33, 34: self = .add
    case 35, 38: self = .subtract
    case 37: self = .lightest
    case 39: self = .darkest
    case 41: self = .darken
    default: self = .backgroundTransparent
    }
  }

  /// Whether the pixel pass keys out `backColor` pixels.
  public var keysBackground: Bool {
    switch self {
    case .backgroundTransparent, .matte, .ghost: return true
    default: return false
    }
  }

  /// Whether the pixel pass RGB-inverts the surviving pixels.
  public var invertsSource: Bool {
    self == .ghost || self == .notCopy
  }

  /// Stable 4-bit value for texture cache keys.
  public var cacheBits: Int {
    switch self {
    case .copy: return 0
    case .backgroundTransparent: return 1
    case .matte: return 2
    case .ghost: return 3
    case .notCopy: return 4
    case .mask: return 5
    case .blend: return 6
    case .add: return 7
    case .subtract: return 8
    case .lightest: return 9
    case .darkest: return 10
    case .darken: return 11
    }
  }
}
