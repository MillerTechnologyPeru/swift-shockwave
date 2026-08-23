import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

/// A Shockwave (`.dcr`) movie loads into the same model as the `.dir` it
/// was burned from: same casts, same members, same score, same compiled
/// scripts. What burning drops is authoring-only — a script's source text
/// is gone, its bytecode isn't.
@Test func shockwaveMoviesLoadLikeTheirSourceMovies() throws {
  let plain = try Movie.load(from: RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL)))
  let burned = try Movie.load(
    from: RIFXFile.read(from: Data(contentsOf: TestResources.junkbotShockwaveURL)))

  let plainLibraries = plain.castManager.libraries.sorted { $0.number < $1.number }
  let burnedLibraries = burned.castManager.libraries.sorted { $0.number < $1.number }
  #expect(plainLibraries.map(\.libraryName) == burnedLibraries.map(\.libraryName))
  #expect(plainLibraries.map(\.members.count) == burnedLibraries.map(\.members.count))

  for (plainLibrary, burnedLibrary) in zip(plainLibraries, burnedLibraries) {
    for (number, plainMember) in plainLibrary.members {
      let burnedMember = try #require(burnedLibrary.members[number], "\(plainLibrary.libraryName) \(number)")
      #expect(plainMember.name == burnedMember.name)
      #expect(plainMember.chunk.type == burnedMember.chunk.type)
      #expect(plainMember.bitmapData == burnedMember.bitmapData)
      // Sounds are re-encoded when a movie is burned: the plain movie's
      // PCM becomes Shockwave Audio, so what survives is that there is
      // audio, at the same rate and roughly the same length.
      if let plainSound = plainMember.sound {
        let burnedAudio = try #require(
          burnedMember.shockwaveAudio, "\(plainLibrary.libraryName) \(number) audio")
        #expect(burnedAudio.sampleRate == plainSound.sampleRate)
        // The re-encode carries about eleven frames (~390 ms at this
        // rate) of encoder padding, so the burned clip is a little longer
        // but never shorter.
        let padding = burnedAudio.durationMilliseconds - plainSound.durationMilliseconds
        #expect(padding >= 0 && padding < 500, "\(plainMember.name ?? "?") duration")
      }
      #expect(plainMember.authoredText == burnedMember.authoredText)
      // Compiled code survives; the source it was compiled from doesn't.
      #expect(plainMember.scriptChunk?.handlers.count == burnedMember.scriptChunk?.handlers.count)
    }
  }

  #expect(plain.score?.frameCount == burned.score?.frameCount)
  #expect(plain.score?.spans.count == burned.score?.spans.count)
  #expect(plain.score?.labels.map(\.name) == burned.score?.labels.map(\.name))
  #expect(burned.fileVersion == plain.fileVersion)
}
