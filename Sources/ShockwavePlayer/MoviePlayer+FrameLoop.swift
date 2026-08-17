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
  /// `prepareFrame`/`enterFrame` on arrival. A `go` has already swapped the
  /// spans by the time this runs (see `movePlayhead(to:)`), so arriving on
  /// its target only dispatches the frame events. Playback stops past the
  /// last frame.
  public func step() {
    guard isPlaying, currentFrame > 0 else { return }
    advanceFilmLoops()
    dispatchMouseWithin()
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
  /// movie.
  public func jump(to frame: Int) {
    guard isPlaying else { return }
    enterFrame(frame, isFirst: false)
  }

  /// Lingo `go`: the playhead moves now — the destination frame's spans
  /// open (and the old ones close) before the calling handler continues,
  /// as in Director — and the next `step()` lands on that frame instead of
  /// advancing. A `go` to the frame already showing just pins the playhead
  /// there, the idiom behind `go the frame`. Out-of-range targets are
  /// ignored, as Director ignores unknown labels.
  func go(to frame: Int) {
    guard let score = movieModel.score, frame >= 1, frame <= score.frameCount else { return }
    nextFrame = frame
    if isPlaying, frame != currentFrame {
      movePlayhead(to: frame)
    }
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
  ///
  /// `bubbles: false` confines the event to the sprite — the pointer
  /// events (`mouseEnter`/`mouseLeave`/`mouseWithin`) are the sprite's own
  /// and never reach the frame or movie scripts.
  @discardableResult
  public func dispatch(_ event: String, toSprite spriteNumber: Int? = nil, bubbles: Bool = true)
    -> Bool
  {
    if let spriteNumber {
      let handled = dispatchToSpans(event, channel: spriteNumber + 5)
      if handled || !bubbles { return handled }
    } else if !bubbles {
      return false
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
    movePlayhead(to: frame)
    dispatchFrameEvent("prepareFrame")
    if isFirst {
      callHandler("startMovie")
    }
    stepActors()
    dispatchFrameEvent("enterFrame")
  }

  /// Moves every film loop on the current frame on by one of its own
  /// frames. A loop's inner channels share their host's number as
  /// `owner`, so hosts are counted once each.
  private func advanceFilmLoops() {
    var hosts = Set<Int>()
    for entry in drawOrder(forFrame: currentFrame) where entry.spriteNumber != entry.owner {
      hosts.insert(entry.owner)
    }
    for host in hosts {
      filmLoopFrames[host, default: 0] += 1
    }
  }

  /// Puts the playhead on `frame` and swaps the live sprite spans over:
  /// spans that end are closed (`endSprite`), spans that start are opened
  /// (`beginSprite`), spans that continue are left alone. Idempotent — a
  /// second call for the frame the playhead is already on changes nothing.
  ///
  /// This is the part of a frame change Director performs *inside* `go`,
  /// before the calling handler continues, and movies lean on that order.
  /// The sample's download manager does `go("loading")` and then sets the
  /// bricks that live only on that frame visible — over the top of a
  /// behavior on those very sprites whose `beginSprite` hides them. Run
  /// `beginSprite` any later and the bricks vanish for good.
  func movePlayhead(to frame: Int) {
    let previous = Set(activeSpanIndices())
    currentFrame = frame
    movieModel.setProperty("frame", value: .integer(frame))

    let current = Set(spanIndices(at: frame))
    for index in previous.subtracting(current).sorted(by: >) {
      closeSpan(index)
    }
    // Channels whose span ended (or is being replaced) drop what Lingo
    // puppeted onto them before the new spans' `beginSprite` runs — that
    // is where the next span's own puppeting starts — and a film loop
    // arriving with a new span starts over.
    if let score = movieModel.score {
      let ended = previous.subtracting(current).compactMap { score.spans[$0].spriteNumber }
      let started = current.subtracting(previous).compactMap { score.spans[$0].spriteNumber }
      for spriteNumber in Set(ended).union(started) {
        existingSprite(spriteNumber)?.releasePuppetState()
        filmLoopFrames[spriteNumber] = 0
        if hoveredSprite == spriteNumber { hoveredSprite = nil }
      }
    }
    for index in current.subtracting(previous).sorted() {
      openSpan(index)
    }
  }

  /// Sends `stepFrame` to everything on `the actorList`, between
  /// `prepareFrame` and `enterFrame`.
  ///
  /// This is how a Director movie runs logic that isn't tied to a sprite or
  /// a frame script: an object adds itself to the list and is driven once
  /// per frame. The junkbot sample's download manager is one — its whole
  /// loading sequence is a `stepFrame` state machine — so without this the
  /// movie sits on its first frame forever.
  ///
  /// The list is snapshotted first because actors routinely remove
  /// themselves (or add others) from inside their own `stepFrame`.
  private func stepActors() {
    guard case .listType(let list) = movieModel.getProperty("actorList") else { return }
    for actor in list.elements {
      guard case .object(let object) = actor else { continue }
      guard let instance = object as? ScriptInstance,
        instance.handler(named: "stepFrame") != nil
      else { continue }
      _ = instance.callMethod("stepFrame", args: [])
    }
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
      // The parameters authored into the score for this attachment — the
      // `[#mylocz: 5]` a "set my locZ" behavior reads in `beginSprite`.
      if let initializer = reference.initializer,
        case .propertyListType(let parameters) = LingoBuiltins.value(.string(initializer))
      {
        for (key, value) in parameters.elements {
          instance.setProperty(key.asString(), value: value)
        }
      }
      instances.append(instance)
    }
    activeSpans[index] = instances
    for instance in instances where instance.handler(named: "beginSprite") != nil {
      _ = instance.callMethod("beginSprite", args: [])
    }
  }

  private func closeSpan(_ index: Int) {
    guard let instances = activeSpans.removeValue(forKey: index) else { return }
    for instance in instances where instance.handler(named: "endSprite") != nil {
      _ = instance.callMethod("endSprite", args: [])
    }
  }

  // MARK: - Dispatch

  /// Frame events broadcast to every level: each sprite's behaviors in
  /// channel order, then the frame script's, then the movie scripts.
  func dispatchFrameEvent(_ event: String) {
    for index in activeSpanIndices() {
      guard let instances = activeSpans[index] else { continue }
      for instance in instances where instance.handler(named: event) != nil {
        _ = instance.callMethod(event, args: [])
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
        _ = instance.callMethod(event, args: [])
        handled = true
      }
    }
    // Behaviors Lingo attached itself, through `scriptInstanceList` — the
    // sample's playfield hangs a "part click behavior" on every brick
    // sprite this way, and that is what makes the bricks draggable.
    if channel >= 6, let sprite = existingSprite(channel - 5) {
      for case let instance as ScriptInstance in sprite.scriptInstances
      where instance.handler(named: event) != nil {
        _ = instance.callMethod(event, args: [])
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
