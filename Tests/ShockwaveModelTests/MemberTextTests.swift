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

/// Field members carry their authored text in an `STXT` chunk owned by the
/// member's `CASt`, joined at load time like bitmaps join their `BITD`.
@Test func fieldMembersLoadTheirAuthoredText() throws {
  let movie = try realMovie()
  // `config field` in the internal cast holds the game's master playfield
  // configuration — the text `legoparts manager` parses at startup.
  let library = try #require(movie.castManager.library(number: 1))
  let config = try #require(library.member(29))
  #expect(config.name == "config field")
  let text = try #require(config.authoredText)
  #expect(text.hasPrefix("[playfield]\rsize=35,22"))
  #expect(text.contains("[legoman]"))

  // A button's label travels the same way.
  let button = try #require(library.member(28))
  #expect(button.authoredText == "EDIT")
}

/// `member(...).text` reads the authored content until a script overwrites
/// it; the override then wins without losing the original.
@Test func textPropertyPrefersScriptOverrides() throws {
  let movie = try realMovie()
  let member = try #require(movie.castManager.library(number: 1)?.member(29))
  #expect(member.getProperty("text").asString().hasPrefix("[playfield]"))

  member.setProperty("text", value: .string("READY TO PLAY"))
  #expect(member.getProperty("text").asString() == "READY TO PLAY")
  #expect(member.text == "READY TO PLAY")
  #expect(member.authoredText?.hasPrefix("[playfield]") == true)
}

/// Members without an `STXT` answer empty string, as Lingo does — not VOID,
/// which would poison string concatenation in scripts.
@Test func membersWithoutTextAnswerEmptyString() throws {
  let movie = try realMovie()
  let bitmap = try #require(movie.castManager.library(number: 2)?.member(10))
  #expect(bitmap.authoredText == nil)
  #expect(bitmap.getProperty("text").asString() == "")
}
