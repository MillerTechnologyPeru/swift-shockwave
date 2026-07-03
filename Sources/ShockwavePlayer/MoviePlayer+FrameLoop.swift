import LingoRuntime
import ShockwaveModel

extension MoviePlayer {
  /// Starts headless playback: `prepareMovie`, then enters the first frame
  /// (`beginSprite` → `prepareFrame` → `startMovie` → `enterFrame`),
  /// matching Director's documented startup event order.
  public func start() {
    guard !isPlaying else { return }
    callHandler("prepareMovie")
    isPlaying = true
    enterFrame(1, isFirst: true)
  }

  /// Runs one frame cycle: dispatches `exitFrame`, then moves the playhead
  /// to wherever `go(...)` pointed it (or the next frame), dispatching
  /// `endSprite`/`beginSprite` for spans that close/open along the way and
  /// `prepareFrame`/`enterFrame` on arrival. Playback stops past the last
  /// frame.
  public func step() {
    guard isPlaying, currentFrame > 0 else { return }
    dispatchFrameEvent("exitFrame")
    let target = nextFrame ?? (currentFrame + 1)
    nextFrame = nil
    guard let score = movieModel.score, target <= score.frameCount, target >= 1 else {
      stop()
      return
    }
    enterFrame(target, isFirst: false)
  }

  /// Moves the playhead immediately without dispatching `exitFrame` on the
  /// current frame — the between-frames jump tests use to position the
  /// movie. Regular Lingo `go(...)` instead takes effect at the next
  /// `step()`.
  public func jump(to frame: Int) {
    guard isPlaying else { return }
    enterFrame(frame, isFirst: false)
  }

  /// Dispatches `stopMovie` and tears down live behavior instances.
  public func stop() {
    guard isPlaying else { return }
    for index in activeSpanIndices().reversed() {
      closeSpan(index)
    }
    isPlaying = false
    callHandler("stopMovie")
  }

  /// Sends a discrete event (e.g. `mouseUp`) through Director's bubbling
  /// order: the target sprite's behaviors first, then the frame script's,
  /// then the movie scripts. Returns whether any handler received it.
  @discardableResult
  public func dispatch(_ event: String, toSprite spriteNumber: Int? = nil) -> Bool {
    if let spriteNumber {
      let handled = dispatchToSpans(event, channel: spriteNumber + 5)
      if handled { return true }
    }
    if dispatchToSpans(event, channel: 0) { return true }
    if movieHandlerNames.contains(event.asciiLowercased()) {
      callHandler(event)
      return true
    }
    return false
  }

  // MARK: - Frame transitions

  private func enterFrame(_ frame: Int, isFirst: Bool) {
    let previous = Set(activeSpanIndices())
    currentFrame = frame
    movieModel.setProperty("frame", value: .integer(frame))

    let current = Set(spanIndices(at: frame))
    for index in previous.subtracting(current).sorted(by: >) {
      closeSpan(index)
    }
    for index in current.subtracting(previous).sorted() {
      openSpan(index)
    }

    dispatchFrameEvent("prepareFrame")
    if isFirst {
      callHandler("startMovie")
    }
    dispatchFrameEvent("enterFrame")
  }

  private func openSpan(_ index: Int) {
    guard let score = movieModel.score else { return }
    let span = score.spans[index]
    var instances: [ScriptInstance] = []
    for reference in span.behaviors {
      guard let member = movieModel.castManager.member(reference), member.scriptChunk != nil
      else { continue }
      let instance = ScriptInstance(member: member, player: self)
      instance.setProperty("spriteNum", value: .integer(span.spriteNumber ?? 0))
      instances.append(instance)
    }
    activeSpans[index] = instances
    for instance in instances where instance.handler(named: "beginSprite") != nil {
      _ = instance.callMethod("beginSprite", args: [.object(instance)])
    }
  }

  private func closeSpan(_ index: Int) {
    guard let instances = activeSpans.removeValue(forKey: index) else { return }
    for instance in instances where instance.handler(named: "endSprite") != nil {
      _ = instance.callMethod("endSprite", args: [.object(instance)])
    }
  }

  // MARK: - Dispatch

  /// Frame events broadcast to every level: each sprite's behaviors in
  /// channel order, then the frame script's, then the movie scripts.
  func dispatchFrameEvent(_ event: String) {
    for index in activeSpanIndices() {
      guard let instances = activeSpans[index] else { continue }
      for instance in instances where instance.handler(named: event) != nil {
        _ = instance.callMethod(event, args: [.object(instance)])
      }
    }
    if movieHandlerNames.contains(event.asciiLowercased()) {
      callHandler(event)
    }
  }

  private func dispatchToSpans(_ event: String, channel: Int) -> Bool {
    guard let score = movieModel.score else { return false }
    var handled = false
    for index in activeSpanIndices() where score.spans[index].channel == channel {
      guard let instances = activeSpans[index] else { continue }
      for instance in instances where instance.handler(named: event) != nil {
        _ = instance.callMethod(event, args: [.object(instance)])
        handled = true
      }
    }
    return handled
  }

  /// Active span indices ordered for dispatch: sprite channels ascending,
  /// the frame-script channel (0) last.
  private func activeSpanIndices() -> [Int] {
    guard let score = movieModel.score else { return [] }
    return activeSpans.keys.sorted {
      let a = score.spans[$0].channel
      let b = score.spans[$1].channel
      return (a == 0 ? Int.max : a) < (b == 0 ? Int.max : b)
    }
  }

  private func spanIndices(at frame: Int) -> [Int] {
    guard let score = movieModel.score else { return [] }
    return score.spans.indices.filter {
      let span = score.spans[$0]
      return span.startFrame <= frame && frame <= span.endFrame
    }
  }
}
