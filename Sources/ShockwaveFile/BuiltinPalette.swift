/// The built-in palettes Director references by negative palette member
/// ids: `-1` System-Mac, `-2` Rainbow, `-3` Grayscale, `-4` Pastels, `-5`
/// Vivid, `-6` NTSC, `-7` Metallic, `-8` Web 216, `-9` VGA, `-101`
/// System-Win, `-102` System-Win (Director 5 variant). All the D4-era
/// tables are real data verified against the palette resources in the
/// Director for Windows projector; only the D7-era additions (`-8`
/// Web 216, `-9` VGA) still fall back to the Mac system palette.
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

  /// Director's built-in "Metallic" system palette (id 7 in its standard
  /// list: System-Mac, Rainbow, Grayscale, Pastels, Vivid, NTSC, Metallic,
  /// System-Win — referenced here as member id `-7`). 256 entries, index 0
  /// through 255, verified against Director's own published table.
  public static let metallic: [PaletteChunk.Color] = [
    (255, 255, 255), (102, 76, 128), (95, 66, 108), (88, 55, 89), (117, 71, 94),
    (148, 88, 99), (155, 102, 105), (159, 108, 106), (163, 109, 104), (166, 111, 102),
    (170, 115, 101), (174, 121, 103), (180, 134, 107), (187, 148, 111), (194, 162, 115),
    (201, 176, 119), (208, 190, 123), (221, 218, 131), (199, 206, 123), (182, 200, 119),
    (166, 195, 116), (150, 189, 112), (133, 183, 109), (118, 177, 105), (102, 171, 102),
    (88, 148, 99), (74, 125, 95), (56, 90, 95), (67, 97, 118), (78, 103, 142),
    (88, 109, 165), (99, 115, 188), (68, 42, 92), (78, 53, 102), (88, 63, 111),
    (98, 74, 121), (108, 85, 130), (118, 95, 140), (128, 106, 149), (138, 117, 159),
    (148, 127, 168), (158, 138, 178), (168, 148, 187), (178, 159, 196), (188, 170, 206),
    (198, 180, 215), (208, 191, 225), (218, 202, 234), (228, 212, 244), (218, 201, 234),
    (207, 190, 224), (196, 178, 214), (185, 167, 203), (175, 156, 193), (164, 144, 183),
    (153, 133, 173), (143, 122, 163), (132, 110, 153), (121, 99, 143), (111, 88, 133),
    (100, 76, 123), (89, 65, 113), (78, 54, 103), (68, 42, 92), (81, 32, 31),
    (92, 43, 43), (103, 55, 55), (114, 66, 66), (125, 77, 78), (135, 88, 89),
    (146, 99, 101), (157, 110, 113), (168, 121, 124), (179, 132, 136), (190, 144, 148),
    (201, 155, 159), (212, 166, 171), (223, 177, 183), (234, 188, 194), (245, 199, 206),
    (255, 210, 218), (244, 198, 205), (232, 187, 193), (221, 175, 180), (209, 163, 168),
    (197, 151, 155), (186, 139, 143), (174, 127, 131), (162, 115, 118), (151, 103, 106),
    (139, 92, 93), (127, 80, 81), (116, 68, 69), (104, 56, 56), (93, 44, 44),
    (81, 32, 31), (68, 38, 25), (79, 49, 34), (89, 59, 44), (100, 70, 54),
    (111, 81, 64), (121, 91, 73), (132, 102, 83), (142, 113, 93), (153, 123, 102),
    (164, 134, 112), (174, 145, 122), (185, 155, 131), (195, 166, 141), (206, 177, 151),
    (217, 187, 161), (227, 198, 170), (238, 209, 180), (227, 195, 165), (215, 184, 155),
    (204, 172, 145), (193, 161, 135), (181, 150, 125), (170, 139, 115), (159, 128, 105),
    (147, 116, 95), (136, 105, 85), (125, 94, 75), (113, 83, 65), (102, 72, 55),
    (91, 60, 45), (79, 49, 35), (68, 38, 25), (118, 85, 18), (128, 93, 28),
    (138, 102, 38), (147, 110, 47), (157, 119, 57), (167, 127, 67), (177, 136, 76),
    (187, 145, 86), (197, 153, 95), (206, 162, 105), (216, 170, 115), (226, 179, 124),
    (236, 187, 134), (246, 196, 143), (255, 204, 153), (255, 213, 171), (255, 225, 194),
    (255, 216, 177), (246, 196, 143), (236, 187, 134), (226, 179, 124), (216, 170, 115),
    (206, 162, 105), (197, 153, 95), (187, 145, 86), (177, 136, 76), (167, 127, 67),
    (157, 119, 57), (147, 110, 47), (138, 102, 38), (128, 93, 28), (118, 85, 18),
    (3, 48, 3), (15, 61, 15), (26, 74, 26), (38, 87, 38), (49, 100, 49),
    (61, 113, 61), (73, 126, 73), (84, 139, 84), (96, 152, 96), (107, 165, 107),
    (119, 178, 119), (130, 191, 131), (142, 204, 142), (154, 217, 154), (165, 230, 165),
    (177, 242, 177), (188, 255, 188), (176, 242, 176), (164, 228, 164), (151, 214, 151),
    (139, 200, 139), (127, 186, 127), (114, 173, 114), (102, 159, 102), (90, 145, 90),
    (77, 131, 77), (65, 117, 65), (52, 103, 53), (40, 90, 40), (28, 76, 28),
    (15, 62, 16), (3, 48, 3), (0, 15, 85), (13, 29, 96), (27, 42, 106),
    (41, 55, 117), (55, 69, 128), (69, 82, 138), (83, 95, 149), (97, 109, 160),
    (111, 122, 170), (125, 135, 181), (138, 149, 192), (152, 162, 202), (166, 175, 213),
    (180, 189, 224), (194, 202, 234), (208, 215, 245), (222, 229, 255), (207, 214, 244),
    (192, 200, 233), (177, 186, 221), (163, 172, 210), (148, 157, 199), (133, 143, 187),
    (118, 129, 176), (103, 115, 165), (88, 101, 153), (74, 86, 142), (59, 72, 131),
    (44, 58, 119), (29, 44, 108), (14, 30, 97), (0, 15, 85), (17, 17, 17),
    (32, 32, 32), (47, 47, 47), (62, 62, 62), (77, 77, 77), (92, 92, 92),
    (106, 106, 106), (121, 121, 121), (136, 136, 136), (151, 151, 151), (166, 166, 166),
    (181, 181, 181), (196, 196, 196), (211, 211, 211), (226, 226, 226), (241, 241, 241),
    (255, 255, 255), (238, 238, 238), (221, 221, 221), (204, 204, 204), (187, 187, 187),
    (170, 170, 170), (153, 153, 153), (136, 136, 136), (119, 119, 119), (102, 102, 102),
    (85, 85, 85), (68, 68, 68), (51, 51, 51), (34, 34, 34), (17, 17, 17),
    (0, 0, 0),
  ].map { PaletteChunk.Color(red: $0.0, green: $0.1, blue: $0.2) }

  /// Resolves a built-in palette member id to a color table. Unknown ids
  /// (including the not-yet-transcribed D7-era `-8` Web 216 and `-9` VGA)
  /// fall back to the Mac system palette.
  public static func colors(forMember member: Int) -> [PaletteChunk.Color] {
    switch member {
    case -2: return rainbow
    case -3: return grayscale
    case -4: return pastels
    case -5: return vivid
    case -6: return ntsc
    case -7: return metallic
    case -101: return systemWin
    case -102: return systemWinD5
    default: return macSystem
    }
  }
}
