import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

private func realMovie() throws -> Movie {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  return try Movie.load(from: file)
}

/// Text xtra members carry their content in `XMED` media (Director's rich
/// text engine) rather than an `STXT`. The sample's level definitions,
/// level titles, and the loading screen's messages all live there.
@Test func xtraTextMembersLoadTheirAuthoredText() throws {
  let movie = try realMovie()

  // The loading screen's message member — authored, not just runtime-set.
  let loading = try #require(movie.castManager.library(named: "loading"))
  let message = try #require(
    loading.members.values.first { $0.name == "download_msg" })
  #expect(message.authoredText == "READY TO PLAY")

  // The loading screen's playable demo level: a full level definition.
  let level = try #require(
    loading.members.values.first { $0.name == "loading_level" })
  let text = try #require(level.authoredText)
  #expect(text.hasPrefix("[info]"))
  #expect(text.contains("[playfield]"))
  #expect(text.contains("size=35,22"))
  #expect(text.contains("[partslist]"))
}

/// The messages are set in the movie's embedded pixel font, 04b_08, at 10
/// point — that is what the loading screen's captions must be drawn with,
/// not a system default.
@Test func xtraTextMembersCarryTheirFontAndSize() throws {
  let movie = try realMovie()
  let loading = try #require(movie.castManager.library(named: "loading"))
  let message = try #require(loading.members.values.first { $0.name == "download_msg" })
  #expect(
    message.textStyle
      == XMediaText.Style(
        fontName: "04b_08 *", fontSize: 10, fixedLineSpace: 15, alignment: "center"))
  #expect(message.getProperty("font").asString() == "04b_08 *")
  #expect(message.getProperty("fontSize").asInteger() == 10)
  let welcome = try #require(loading.members.values.first { $0.name == "loading bkg text" })
  #expect(welcome.textStyle?.fontName == "04b_08 *")
  #expect(welcome.textStyle?.fontSize == 10)
  // The level menu's columns are ruled at 21px and the moves column is
  // right-aligned — paragraph formats the members carry themselves.
  let numbers = try #require(loading.members.values.first { $0.name == "level.num" }
    ?? movie.castManager.member(named: "level.num"))
  #expect(numbers.textStyle?.fixedLineSpace == 21)
  let moves = try #require(movie.castManager.member(named: "level.moves"))
  #expect(moves.textStyle?.fixedLineSpace == 21)
  #expect(moves.textStyle?.alignment == "right")
  // A level definition is data, set in Arial like a plain field.
  let level = try #require(loading.members.values.first { $0.name == "loading_level" })
  #expect(level.textStyle?.fontName == "Arial")
}

/// The game's 60 level definitions live in the `levels` cast, exactly as
/// `prepareLevelMenu` expects (`the number of castMembers of castLib
/// "levels"`), and every one must expose a parseable definition.
@Test func theLevelsCastHoldsAllSixtyLevelDefinitions() throws {
  let movie = try realMovie()
  let levelsCast = try #require(movie.castManager.library(named: "levels"))
  var definitions = 0
  for (_, member) in levelsCast.members where member.chunk.type == .xtra {
    let text = try #require(member.text, "'\(member.name ?? "?")' has no text")
    #expect(text.contains("[info]"), "'\(member.name ?? "?")'")
    #expect(text.contains("[playfield]"), "'\(member.name ?? "?")'")
    definitions += 1
  }
  #expect(definitions == 60)
}

/// Non-text media also ships as `XMED` (fonts, 3D scenes); those must not
/// produce garbage text.
@Test func nonTextMediaYieldsNoText() {
  #expect(XMediaText.text(from: Data("PFR1garbage".utf8)) == nil)
  #expect(XMediaText.text(from: Data()) == nil)
  #expect(XMediaText.text(from: Data("FFFF00000006".utf8)) == nil)
}
