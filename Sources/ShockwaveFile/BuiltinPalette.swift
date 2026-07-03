/// The built-in palettes Director references by negative palette member
/// ids. Only the algorithmically-defined tables are constructed here (the
/// classic Mac 8-bit system palette, grayscale, and the web-safe cube);
/// other built-ins currently fall back to the Mac system palette until
/// their tables can be validated visually.
public enum BuiltinPalette {
  /// The classic Mac 8-bit system palette: a 6-level RGB color cube
  /// (255/204/153/102/51/0, red varying slowest, minus the black entry),
  /// then 10-step red/green/blue/gray ramps of the intermediate values,
  /// with black last.
  public static let macSystem: [PaletteChunk.Color] = {
    var colors: [PaletteChunk.Color] = []
    let cube: [UInt8] = [255, 204, 153, 102, 51, 0]
    for red in cube {
      for green in cube {
        for blue in cube where !(red == 0 && green == 0 && blue == 0) {
          colors.append(PaletteChunk.Color(red: red, green: green, blue: blue))
        }
      }
    }
    let ramp: [UInt8] = [238, 221, 187, 170, 136, 119, 85, 68, 34, 17]
    for value in ramp { colors.append(PaletteChunk.Color(red: value, green: 0, blue: 0)) }
    for value in ramp { colors.append(PaletteChunk.Color(red: 0, green: value, blue: 0)) }
    for value in ramp { colors.append(PaletteChunk.Color(red: 0, green: 0, blue: value)) }
    for value in ramp { colors.append(PaletteChunk.Color(red: value, green: value, blue: value)) }
    colors.append(PaletteChunk.Color(red: 0, green: 0, blue: 0))
    return colors
  }()

  /// 256-step grayscale, white first (matching palette index 0 = white).
  public static let grayscale: [PaletteChunk.Color] = (0..<256).map { index in
    let value = UInt8(255 - index)
    return PaletteChunk.Color(red: value, green: value, blue: value)
  }

  /// Resolves a built-in palette member id (negative, e.g. `-1` for the
  /// Mac system palette) to a color table.
  public static func colors(forMember member: Int) -> [PaletteChunk.Color] {
    switch member {
    case -3: return grayscale
    default: return macSystem
    }
  }
}
