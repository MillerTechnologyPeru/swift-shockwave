import Foundation
import LingoBytecode
import LingoRuntime
import ShockwaveFile
import ShockwaveTestSupport
import Testing

@testable import ShockwaveModel

private func realMovie() throws -> Movie {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  return try Movie.load(from: file)
}

@Test func realMovieLoadsAllCastLibraries() throws {
  let movie = try realMovie()
  // Exactly the thirteen `MCsL` entries; every `CAS*` table in the file
  // belongs to one of them (dirplayer-rs loads the same thirteen).
  #expect(movie.castManager.libraries.count == 13)
  #expect(movie.getProperty("castCount").asInteger() == 13)

  let names = movie.castManager.libraries.map(\.libraryName)
  #expect(
    names == [
      "Internal", "legoparts", "catalog", "editor", "play", "peter 101", "sound",
      "levels", "dynamic", "unused levels", "screens_by_peter", "backgrounds", "loading",
    ])
}

/// Library numbers and the file-internal owner ids diverge from cast 8 on
/// (owner id 8 is skipped), so a score record's `castLib` must resolve
/// through `fileNumber`, not `number`.
@Test func libraryNumbersAndFileNumbersDiverge() throws {
  let movie = try realMovie()
  let levels = try #require(movie.castManager.library(named: "levels"))
  #expect(levels.number == 8)
  #expect(levels.fileNumber == 9)
  let loading = try #require(movie.castManager.library(named: "loading"))
  #expect(loading.number == 13)
  #expect(loading.fileNumber == 14)
  #expect(movie.castManager.library(fileNumber: 8) == nil)
}

@Test func theLoadingCastHoldsTheDownloadManager() throws {
  let movie = try realMovie()
  // The screen-building script and the loading/intro art live in the
  // `loading` cast — the last listed library, owner id 14.
  let loading = try #require(movie.castManager.library(named: "loading"))
  #expect(loading.members.count == 28)
  #expect(loading.member(1)?.name == "download manager")
  #expect(loading.member(2)?.name == "loading_level")
}

@Test func internalLibraryHoldsTheMovieScripts() throws {
  let movie = try realMovie()
  let internalLibrary = try #require(movie.castManager.library(number: 1))
  #expect(internalLibrary.libraryName == "Internal")
  #expect(internalLibrary.memberCount == 44)
  #expect(internalLibrary.member(1)?.name == "main")
}

@Test func legopartsLibraryMemberRangeMatchesMCsL() throws {
  let movie = try realMovie()
  let legoparts = try #require(movie.castManager.library(number: 2))
  #expect(legoparts.libraryName == "legoparts")
  #expect(legoparts.memberCount == 36)
  #expect(legoparts.minMember == 1)
  #expect(legoparts.maxMember == 36)
  #expect(legoparts.member(1)?.name == "BRICK_01_BLUE")
}

@Test func soundLibraryUsesNonOneMinMember() throws {
  // "sound" has minMember 9 / maxMember 177 in the file's own MCsL metadata
  // (not 1-based), so member numbers must be offset by minMember, not by
  // the member's position in the CAS* array. Its CAS* has 169 slots (177-9+1)
  // but only 75 are occupied — the rest are deleted/empty member numbers.
  let movie = try realMovie()
  let sound = try #require(movie.castManager.library(named: "sound"))
  #expect(sound.memberCount == 75)
  #expect(sound.minMember == 9)
  #expect(sound.maxMember == 177)
  #expect(sound.member(9) != nil)
  #expect(sound.member(1) == nil)
}

@Test func scriptMemberExposesLingoProperties() throws {
  let movie = try realMovie()
  let internalLibrary = try #require(movie.castManager.library(number: 1))
  let main = try #require(internalLibrary.member(1))

  #expect(main.getProperty("name").asString() == "main")
  #expect(main.getProperty("type").asString() == "script")
  #expect(main.getProperty("number").asInteger() == (0 << 16) | 1)
  #expect(main.getProperty("scriptText").asString().hasPrefix("global glob, version"))

  main.setProperty("name", value: .string("renamed"))
  #expect(main.getProperty("name").asString() == "renamed")
}

@Test func scriptMemberBridgesToCompiledScriptChunk() throws {
  let movie = try realMovie()
  let internalLibrary = try #require(movie.castManager.library(number: 1))
  let main = try #require(internalLibrary.member(1))

  let scriptChunk = try #require(main.scriptChunk)
  #expect(!scriptChunk.handlers.isEmpty)

  let names = try #require(try RIFXFile.read(from: realMovieData()).nameTable()).names
  let handlerNames = scriptChunk.handlers.map { names[Int($0.nameId)] }
  #expect(handlerNames.contains("prepareMovie"))
}

@Test func castWithNoScriptsLoadsWithoutError() throws {
  // "catalog"'s Lctx stores entryCount == 0 with entriesOffset pointing
  // exactly at the chunk's end — a valid empty section map, since nothing
  // is ever read from a one-past-the-end offset. Regression coverage for
  // `ScriptContextChunk.read`'s off-by-one lives in swift-lingo itself
  // (`scriptContextChunkWithNoEntriesAtChunkEnd`); this pins the same case
  // end-to-end through `Movie.load`.
  let movie = try realMovie()
  let catalog = try #require(movie.castManager.library(named: "catalog"))
  #expect(catalog.memberCount == 21)
  #expect(catalog.members.values.contains { $0.scriptChunk != nil })
}

@Test func nonScriptMembersHaveNoScriptChunk() throws {
  let movie = try realMovie()
  let legoparts = try #require(movie.castManager.library(number: 2))
  // Member 12 is a brick bitmap, not a script.
  let cursor = try #require(legoparts.member(12))
  #expect(cursor.getProperty("type").asString() == "bitmap")
  #expect(cursor.scriptChunk == nil)
}

@Test func scoreLoadsWithLabelsAndSpans() throws {
  let movie = try realMovie()
  let score = try #require(movie.score)
  #expect(score.frameCount == 30)
  #expect(movie.getProperty("lastFrame").asInteger() == 30)

  #expect(score.frame(labeled: "mainmenu") == 9)
  #expect(score.frame(labeled: "MAINMENU") == 9)
  #expect(score.label(at: 10) == "mainmenu")
  #expect(score.label(at: 1) == nil)

  #expect(score.spans.count == 431)
}

@Test func movieFrameRateDecodesFromConfigChunk() throws {
  // The config chunk's frame_rate field (offset 54) — junkbot.dir is
  // authored at a flat 15fps with no per-frame tempo channel overrides.
  let movie = try realMovie()
  #expect(movie.frameRate == 15)
  #expect(movie.score?.frameTempo(at: 1) == nil)
}

@Test func frameBehaviorsResolveToCastMembers() throws {
  let movie = try realMovie()
  let score = try #require(movie.score)

  // Frame 1's frame-script behavior is legoparts' "frameloop"
  // (file-internal lib 1, member 4).
  let behaviors = score.frameBehaviors(at: 1)
  #expect(behaviors.count == 1)
  let frameloop = try #require(movie.castManager.member(behaviors[0]))
  #expect(frameloop.getProperty("name").asString() == "frameloop")
  #expect(frameloop.getProperty("type").asString() == "script")
  #expect(frameloop.scriptChunk != nil)
}

@Test func spriteSpansExposeLingoSpriteNumbers() throws {
  let movie = try realMovie()
  let score = try #require(movie.score)

  let frameSpans = score.spans(at: 5)
  #expect(!frameSpans.isEmpty)
  for span in frameSpans {
    if span.channel > 5 {
      #expect(span.spriteNumber == span.channel - 5)
    } else {
      #expect(span.spriteNumber == nil)
    }
  }
}

private func realMovieData() throws -> Data {
  try Data(contentsOf: TestResources.junkbotMovieURL)
}
