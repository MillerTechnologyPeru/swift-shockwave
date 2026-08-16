import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer
import ShockwaveTestSupport
import Testing

/// The junkbot sample's `prepareMovie` builds its subsystems with
/// `new(script("... manager"))`. Every one of those scripts is present
/// except the download manager, which owns the screen-building path
/// (`glob.download_manager.mainmenu()`), so the movie can never assemble
/// its menu from this file alone.
@MainActor
@Test func missingDownloadManagerIsReported() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()

  let warnings = player.transcript.filter { $0.hasPrefix("no script cast member") }
  #expect(warnings.contains { $0.contains("download manager") })
  // Reported once, not once per call site.
  #expect(warnings.count == Set(warnings).count)
}

@MainActor
@Test func sampleResolvesEveryOtherManagerScript() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  for name in ["config manager", "legoparts manager", "play manager", "database manager"] {
    #expect(player.makeObject(scriptName: name, args: []) != nil, "\(name) should resolve")
  }
  #expect(player.makeObject(scriptName: "download manager", args: []) == nil)
}
