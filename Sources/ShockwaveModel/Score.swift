import LingoRuntime
import ShockwaveFile

/// One channel's span of frames with behaviors attached, resolved to the
/// movie's cast members. Channel 0 is the frame-script channel; sprite
/// channel `n` (as Lingo numbers sprites) is channel `n + 5`.
public struct SpriteSpan: Sendable {
  public var startFrame: Int
  public var endFrame: Int
  public var channel: Int
  public var behaviors: [ScoreChunk.BehaviorReference]

  public init(
    startFrame: Int, endFrame: Int, channel: Int, behaviors: [ScoreChunk.BehaviorReference]
  ) {
    self.startFrame = startFrame
    self.endFrame = endFrame
    self.channel = channel
    self.behaviors = behaviors
  }

  /// The Lingo sprite number, or `nil` for the special channels (frame
  /// script, tempo, transition, sounds, palette).
  public var spriteNumber: Int? {
    channel > 5 ? channel - 5 : nil
  }
}

/// The movie's score: the frame timeline, labels, and behavior spans.
/// Geometry/tween state is out of scope for the headless model; the raw
/// per-frame channel records stay available through `chunk`.
public final class Score {
  public let chunk: ScoreChunk
  public let labels: [FrameLabelsChunk.Label]
  public let spans: [SpriteSpan]

  public init(chunk: ScoreChunk, labels: [FrameLabelsChunk.Label]) {
    self.chunk = chunk
    self.labels = labels
    self.spans = chunk.behaviorIntervals.map {
      SpriteSpan(
        startFrame: $0.startFrame, endFrame: $0.endFrame, channel: $0.channel,
        behaviors: $0.behaviors)
    }
  }

  public var frameCount: Int { chunk.frames.count }

  public func frame(labeled name: String) -> Int? {
    labels.first { $0.name.caseInsensitiveEquals(name) }?.frame
  }

  public func label(at frame: Int) -> String? {
    labels.last { $0.frame <= frame }?.name
  }

  /// Every span active at `frame`, the frame-script channel included.
  public func spans(at frame: Int) -> [SpriteSpan] {
    spans.filter { $0.startFrame <= frame && frame <= $0.endFrame }
  }

  /// The frame-script behaviors for `frame` (channel 0 spans).
  public func frameBehaviors(at frame: Int) -> [ScoreChunk.BehaviorReference] {
    spans(at: frame).filter { $0.channel == 0 }.flatMap(\.behaviors)
  }
}
