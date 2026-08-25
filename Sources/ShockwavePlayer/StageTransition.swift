import Foundation

/// A frame transition waiting to be played: `puppetTransition(...)` (and
/// eventually the score's transition channel) post one here, and the host
/// consumes it when it next puts the new frame on screen.
public struct StageTransition: Sendable {
  /// Director's built-in transition id, 1–52.
  public let type: Int
  public let durationMilliseconds: Int
  /// 1–128; bigger chunks are coarser (the opposite of smoothness).
  public let chunkSize: Int

  public init(type: Int, durationMilliseconds: Int, chunkSize: Int) {
    self.type = type
    self.durationMilliseconds = durationMilliseconds
    self.chunkSize = chunkSize
  }
}

/// Which parts of the incoming frame a transition shows at a given moment.
/// Pure geometry over the stage rectangle, so hosts with any renderer can
/// drive it and tests can read it: at `progress` 0 nothing of the new
/// frame is visible, at 1 all of it.
public enum TransitionGeometry {
  public struct Rect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }
  }

  /// The regions of the new frame visible at `progress` (0...1).
  ///
  /// The wipe/cover/reveal families and the strip transitions get their
  /// real geometry (push and cover don't animate the frames sliding — the
  /// reveal edge moves the same way, which reads correctly at Director's
  /// short durations). Everything else falls back to the dissolve, which
  /// uncovers the stage in a shuffled grid of `chunkSize` squares.
  public static func revealedRects(
    type: Int, progress: Double, width: Int, height: Int, chunkSize: Int
  ) -> [Rect] {
    let p = min(1, max(0, progress))
    if p >= 1 { return [Rect(x: 0, y: 0, width: width, height: height)] }
    if p <= 0 { return [] }
    let w = Double(width)
    let h = Double(height)
    switch type {
    case 1, 11, 29, 15:  // wipe right; push/cover/reveal moving right
      return [Rect(x: 0, y: 0, width: Int((w * p).rounded()), height: height)]
    case 2, 12, 30, 16:  // wipe left
      let shown = Int((w * p).rounded())
      return [Rect(x: width - shown, y: 0, width: shown, height: height)]
    case 3, 13, 31, 17:  // wipe down
      return [Rect(x: 0, y: 0, width: width, height: Int((h * p).rounded()))]
    case 4, 14, 32, 18:  // wipe up
      let shown = Int((h * p).rounded())
      return [Rect(x: 0, y: height - shown, width: width, height: shown)]
    case 33, 19:  // cover/reveal from the top-left corner
      return [Rect(x: 0, y: 0, width: Int((w * p).rounded()), height: Int((h * p).rounded()))]
    case 34, 20:  // top-right
      let shown = Int((w * p).rounded())
      return [Rect(x: width - shown, y: 0, width: shown, height: Int((h * p).rounded()))]
    case 35, 21:  // bottom-left
      let shownH = Int((h * p).rounded())
      return [Rect(x: 0, y: height - shownH, width: Int((w * p).rounded()), height: shownH)]
    case 36, 22:  // bottom-right
      let shownW = Int((w * p).rounded())
      let shownH = Int((h * p).rounded())
      return [Rect(x: width - shownW, y: height - shownH, width: shownW, height: shownH)]
    case 5:  // center out, horizontal
      let shown = Int((w * p).rounded())
      return [Rect(x: (width - shown) / 2, y: 0, width: shown, height: height)]
    case 6:  // edges in, horizontal
      let half = Int((w * p / 2).rounded())
      return [
        Rect(x: 0, y: 0, width: half, height: height),
        Rect(x: width - half, y: 0, width: half, height: height),
      ]
    case 7:  // center out, vertical
      let shown = Int((h * p).rounded())
      return [Rect(x: 0, y: (height - shown) / 2, width: width, height: shown)]
    case 8:  // edges in, vertical
      let half = Int((h * p / 2).rounded())
      return [
        Rect(x: 0, y: 0, width: width, height: half),
        Rect(x: 0, y: height - half, width: width, height: half),
      ]
    case 9:  // center out, square
      let shownW = Int((w * p).rounded())
      let shownH = Int((h * p).rounded())
      return [
        Rect(x: (width - shownW) / 2, y: (height - shownH) / 2, width: shownW, height: shownH)
      ]
    case 10:  // edges in, square — the border closes on the middle
      let halfW = Int((w * p / 2).rounded())
      let halfH = Int((h * p / 2).rounded())
      return [
        Rect(x: 0, y: 0, width: width, height: halfH),
        Rect(x: 0, y: height - halfH, width: width, height: halfH),
        Rect(x: 0, y: 0, width: halfW, height: height),
        Rect(x: width - halfW, y: 0, width: halfW, height: height),
      ]
    case 37, 39:  // venetian blinds / build strips: horizontal slats
      let slats = 8
      let slatHeight = (height + slats - 1) / slats
      let shown = Int((Double(slatHeight) * p).rounded())
      return (0..<slats).map {
        Rect(x: 0, y: $0 * slatHeight, width: width, height: min(shown, height - $0 * slatHeight))
      }
    case 47:  // vertical blinds
      let slats = 8
      let slatWidth = (width + slats - 1) / slats
      let shown = Int((Double(slatWidth) * p).rounded())
      return (0..<slats).map {
        Rect(x: $0 * slatWidth, y: 0, width: min(shown, width - $0 * slatWidth), height: height)
      }
    case 38:  // checkerboard: half the squares grow first, then the rest
      let square = 32
      let columns = (width + square - 1) / square
      let rows = (height + square - 1) / square
      var rects: [Rect] = []
      for row in 0..<rows {
        for column in 0..<columns {
          let firstHalf = (row + column) % 2 == 0
          let local = firstHalf ? min(1, p * 2) : max(0, p * 2 - 1)
          let shown = Int((Double(square) * local).rounded())
          guard shown > 0 else { continue }
          rects.append(
            Rect(
              x: column * square, y: row * square,
              width: min(shown, width - column * square),
              height: min(square, height - row * square)))
        }
      }
      return rects
    default:
      return dissolveRects(progress: p, width: width, height: height, chunkSize: chunkSize)
    }
  }

  /// The dissolve family: the stage cut into `chunkSize` squares, shown in
  /// a fixed shuffled order as progress advances. The shuffle is a
  /// full-cycle linear congruence, so every square appears exactly once
  /// and the pattern is stable across frames of one transition.
  static func dissolveRects(progress: Double, width: Int, height: Int, chunkSize: Int) -> [Rect] {
    let square = max(1, min(128, chunkSize)) * 4
    let columns = max(1, (width + square - 1) / square)
    let rows = max(1, (height + square - 1) / square)
    let count = columns * rows
    let shown = Int((Double(count) * progress).rounded())
    var rects: [Rect] = []
    rects.reserveCapacity(shown)
    // x -> (5x + 7) mod 2^k cycles through every residue; take the first
    // `count` values below `count` in that orbit.
    var capacity = 1
    while capacity < count { capacity *= 2 }
    var value = 0
    var emitted = 0
    for _ in 0..<capacity {
      if value < count {
        if emitted >= shown { break }
        emitted += 1
        let x = (value % columns) * square
        let y = (value / columns) * square
        rects.append(
          Rect(x: x, y: y, width: min(square, width - x), height: min(square, height - y)))
      }
      value = (5 * value + 7) % capacity
    }
    return rects
  }
}
