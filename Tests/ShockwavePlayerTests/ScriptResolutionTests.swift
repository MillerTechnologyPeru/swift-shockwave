import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer
import ShockwaveTestSupport
import Testing

/// `prepareMovie` builds the junkbot sample's subsystems with
/// `new(script("... manager"))`. Every one of those names has to resolve —
/// `download manager` in particular lives in a cast table the movie's cast
/// list never mentions, and losing it disables the whole screen-building
/// path (`glob.download_manager.mainmenu()`) without raising an error.
@MainActor
@Test func everyManagerScriptResolves() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  for name in [
    "config manager", "download manager", "legoparts manager", "play manager",
    "database manager", "game manager", "edit manager", "catalog manager",
  ] {
    let found = movie.castManager.libraries.contains { library in
      library.members.values.contains {
        $0.chunk.type == .script && ($0.name?.caseInsensitiveEquals(name) ?? false)
      }
    }
    #expect(found, "\(name) should resolve to a script member")
  }
}

/// Every manager the sample builds in `prepareMovie` has to instantiate,
/// not just resolve — `database manager`'s constructor calls
/// `(the actorList).add(me)`, so it only works once `prepareMovie` has run
/// `the actorList = []`. Instantiating it beforehand hangs: calling a
/// method on VOID never returns in the VM.
@MainActor
@Test func prepareMovieBuildsItsManagers() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()

  for name in [
    "config manager", "download manager", "legoparts manager", "play manager",
    "database manager",
  ] {
    #expect(player.makeObject(scriptName: name, args: []) != nil, "\(name) should instantiate")
  }
  #expect(player.transcript.filter { $0.hasPrefix("no script cast member") }.isEmpty)
}

@MainActor
@Test func genuinelyMissingScriptIsReportedOnce() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  // An unresolved script yields VOID rather than raising, so it has to be
  // reported or it disappears — but only once, however often it's asked for.
  #expect(player.makeObject(scriptName: "no such manager", args: []) == nil)
  #expect(player.makeObject(scriptName: "no such manager", args: []) == nil)
  let warnings = player.transcript.filter { $0.contains("no such manager") }
  #expect(warnings.count == 1)
}
