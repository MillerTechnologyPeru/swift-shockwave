import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

private typealias Rect = TransitionGeometry.Rect

private func area(_ rects: [Rect]) -> Int {
  rects.reduce(0) { $0 + $1.width * $1.height }
}

/// Every transition uncovers nothing at 0, everything at 1, and roughly
/// tracks progress in between.
@Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 33, 37, 38, 47, 51])
func transitionsUncoverTheStage(type: Int) {
  #expect(
    TransitionGeometry.revealedRects(type: type, progress: 0, width: 640, height: 480, chunkSize: 4)
      .isEmpty)
  let done = TransitionGeometry.revealedRects(
    type: type, progress: 1, width: 640, height: 480, chunkSize: 4)
  #expect(done == [Rect(x: 0, y: 0, width: 640, height: 480)])
  let half = area(
    TransitionGeometry.revealedRects(
      type: type, progress: 0.5, width: 640, height: 480, chunkSize: 4))
  // The corner families cover exactly a quarter at half progress, and
  // edges-in-square's four bands overlap in the corners, so the bounds
  // are inclusive of both extremes.
  #expect(half >= 640 * 480 / 4)
  #expect(half <= 640 * 480)
}

/// The wipe family's geometry: a wipe right reveals a growing left band,
/// edges-in closes from both sides, center-out grows from the middle.
@Test func wipeGeometryMatchesDirector() {
  #expect(
    TransitionGeometry.revealedRects(type: 1, progress: 0.25, width: 400, height: 100, chunkSize: 1)
      == [Rect(x: 0, y: 0, width: 100, height: 100)])
  #expect(
    TransitionGeometry.revealedRects(type: 2, progress: 0.25, width: 400, height: 100, chunkSize: 1)
      == [Rect(x: 300, y: 0, width: 100, height: 100)])
  #expect(
    TransitionGeometry.revealedRects(type: 5, progress: 0.5, width: 400, height: 100, chunkSize: 1)
      == [Rect(x: 100, y: 0, width: 200, height: 100)])
  #expect(
    TransitionGeometry.revealedRects(type: 6, progress: 0.5, width: 400, height: 100, chunkSize: 1)
      == [
        Rect(x: 0, y: 0, width: 100, height: 100),
        Rect(x: 300, y: 0, width: 100, height: 100),
      ])
}

/// The dissolve shows each chunk exactly once, in a shuffled but stable
/// order — the same squares are revealed at the same progress every pass.
@Test func dissolveIsStableAndComplete() {
  let all = TransitionGeometry.dissolveRects(progress: 1, width: 320, height: 240, chunkSize: 8)
  #expect(area(all) == 320 * 240)
  #expect(Set(all.map { "\($0.x),\($0.y)" }).count == all.count)
  let half1 = TransitionGeometry.dissolveRects(progress: 0.5, width: 320, height: 240, chunkSize: 8)
  let half2 = TransitionGeometry.dissolveRects(progress: 0.5, width: 320, height: 240, chunkSize: 8)
  #expect(half1 == half2)
  // Shuffled: the first revealed squares are not simply the top row.
  #expect(half1.prefix(5).map(\.y).contains { $0 != 0 })
}

/// `puppetTransition` posts a transition for the host to consume.
@MainActor
@Test func puppetTransitionPostsForTheHost() throws {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  let player = MoviePlayer(movie: movie)
  player.start()
  _ = movie.lingoEnvironment.callGlobal(
    "puppetTransition", args: [.integer(51), .integer(4), .integer(8)])
  let transition = try #require(player.pendingTransition)
  #expect(transition.type == 51)
  #expect(transition.durationMilliseconds == 1000)
  #expect(transition.chunkSize == 8)
}
