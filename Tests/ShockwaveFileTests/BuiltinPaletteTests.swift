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
  #expect(BuiltinPalette.colors(forMember: -8) == BuiltinPalette.macSystem)
  #expect(BuiltinPalette.colors(forMember: -999) == BuiltinPalette.macSystem)
}
