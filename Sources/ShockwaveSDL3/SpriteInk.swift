import ShockwaveFile

/// The compositing modes the renderer distinguishes for a sprite channel's
/// ink value. Director defines many more inks (reverse, blend, darken...);
/// the ones the renderer doesn't implement yet map onto the closest of
/// these three so sprites still show up sensibly.
enum SpriteInk: Equatable {
  /// Ink 0: every pixel composites opaque.
  case copy
  /// Ink 36 ("background transparent"): pixels matching the sprite's
  /// `backColor` are keyed out wherever they appear.
  case backgroundTransparent
  /// Ink 8 ("matte"): only the background-colored region connected to the
  /// bitmap's edges is keyed out — background-colored pixels enclosed by
  /// the artwork stay opaque. Director keys matte against white, not the
  /// sprite's `backColor`.
  case matte
  /// Ink 3 ("ghost"): QuickDraw's `srcBic` — dark (non-white) source
  /// pixels erase the destination to white, white source pixels are
  /// transparent. The classic use is invisible/highlight buttons.
  case ghost

  /// Maps a score record's raw ink number onto a renderer mode. Unhandled
  /// inks fall back to `backgroundTransparent`, which was the renderer's
  /// previous behavior for every nonzero ink.
  init(inkNumber: Int) {
    switch inkNumber {
    case 0: self = .copy
    case 3: self = .ghost
    case 8: self = .matte
    default: self = .backgroundTransparent
    }
  }

  /// Whether the ink keys transparency against white rather than the
  /// sprite's `backColor` palette index.
  var keysWhite: Bool {
    self == .matte || self == .ghost
  }

  /// Stable 2-bit value for texture cache keys.
  var cacheBits: Int {
    switch self {
    case .copy: return 0
    case .backgroundTransparent: return 1
    case .matte: return 2
    case .ghost: return 3
    }
  }
}
