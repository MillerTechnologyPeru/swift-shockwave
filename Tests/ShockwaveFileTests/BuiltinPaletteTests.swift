import Foundation
import ShockwaveFile
import Testing

@Test func builtinPalettesHave256Entries() {
  for member in [-1, -2, -3, -4, -5, -6, -7, -101, -102] {
    #expect(BuiltinPalette.colors(forMember: member).count == 256)
  }
}

@Test func systemWinSpotChecks() {
  let colors = BuiltinPalette.systemWin
  // Director index order: white first, black last, with the Windows static
  // colors at the ends (reversed relative to the raw Windows table).
  #expect(colors[0] == PaletteChunk.Color(red: 255, green: 255, blue: 255))
  #expect(colors[1] == PaletteChunk.Color(red: 0, green: 255, blue: 255))
  #expect(colors[8] == PaletteChunk.Color(red: 160, green: 160, blue: 164))
  #expect(colors[9] == PaletteChunk.Color(red: 255, green: 251, blue: 240))
  #expect(colors[255] == PaletteChunk.Color(red: 0, green: 0, blue: 0))
}

@Test func builtinPalettesEndInBlack() {
  // Every Director built-in table is white-at-0, black-at-255.
  for member in [-1, -2, -4, -5, -6, -7, -101, -102] {
    let colors = BuiltinPalette.colors(forMember: member)
    #expect(colors[0] == PaletteChunk.Color(red: 255, green: 255, blue: 255), "member \(member)")
    #expect(colors[255] == PaletteChunk.Color(red: 0, green: 0, blue: 0), "member \(member)")
  }
}

@Test func unknownMemberFallsBackToMacSystem() {
  #expect(BuiltinPalette.colors(forMember: -999) == BuiltinPalette.macSystem)
}

@Test func web216ResolvesToItsOwnTable() {
  let colors = BuiltinPalette.colors(forMember: -8)
  #expect(colors.count == 256)
  // Windows static colors at the head, mid gray at index 7 — the entry the
  // junkbot UI's 348 Web-216 bitmaps lean on hardest.
  #expect(colors[0] == PaletteChunk.Color(red: 255, green: 255, blue: 255))
  #expect(colors[7] == PaletteChunk.Color(red: 128, green: 128, blue: 128))
  #expect(colors[255] == PaletteChunk.Color(red: 0, green: 0, blue: 0))
}

/// The file stores built-in palette ids one higher than Lingo numbers
/// them; `BitmapMemberProperties` normalizes on parse so `colors(forMember:)`
/// always takes Lingo ids.
@Test func storedPaletteIdsNormalizeToLingoNumbering() {
  func parse(storedId: Int16) -> Int? {
    var bytes = [UInt8](repeating: 0, count: 28)
    bytes[23] = 8  // bitsPerPixel
    let raw = UInt16(bitPattern: storedId)
    bytes[26] = UInt8(raw >> 8)
    bytes[27] = UInt8(raw & 0xFF)
    return BitmapMemberProperties(specificData: Data(bytes))?.paletteMember
  }
  #expect(parse(storedId: 0) == -1)  // System-Mac
  #expect(parse(storedId: -6) == -7)  // Metallic
  #expect(parse(storedId: -7) == -8)  // Web 216
  #expect(parse(storedId: -100) == -101)  // System-Win
  #expect(parse(storedId: 5) == 5)  // a palette cast member passes through
}

@Test func vgaResolvesToWindowsSystemPalette() {
  // VGA ships no table of its own and resolves to System-Win, not the Mac
  // palette the other unknown ids fall back to.
  #expect(BuiltinPalette.colors(forMember: -9) == BuiltinPalette.systemWin)
}
