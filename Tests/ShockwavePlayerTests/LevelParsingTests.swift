import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer
import ShockwaveTestSupport
import Testing

/// End to end through the movie's own Lingo: the loading screen's demo
/// level text (an `XMED` member) fed to `config manager`'s `parseParams`
/// must come back as the structured property list the game plays from —
/// exercising XMED extraction, string chunks, list commands, and builtins
/// in one authored code path.
@MainActor
@Test func theMoviesOwnParserReadsALevelDefinition() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()

  let glob = movie.lingoEnvironment.getGlobal("glob")
  guard case .object(let object) = glob.listGetAProp(.symbol("config_manager")),
    let configManager = object as? ScriptInstance
  else {
    Issue.record("config manager should exist after prepareMovie")
    return
  }

  let level = try #require(
    movie.castManager.library(named: "loading")?.members.values.first {
      $0.name == "loading_level"
    })
  let parsed = configManager.callMethod("parseParams", args: [.string(level.text ?? "")])

  let info = parsed.listGetAProp(.symbol("info"))
  #expect(info.isList, "parseParams should produce a structured list")
  #expect(info.listGetAProp(.symbol("title")).asString() == "loading level idea 2")

  // `the itemDelimiter = ","` splits `size=35,22` into two items, which
  // parseParams folds into the list [35, 22].
  let playfield = parsed.listGetAProp(.symbol("playfield"))
  let size = playfield.listGetAProp(.symbol("size"))
  #expect(size.isList)
  #expect(size[.integer(1)].asInteger() == 35)
  #expect(size[.integer(2)].asInteger() == 22)
}
