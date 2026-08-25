import CSDL3
import SDL3Swift
import ShockwavePlayer

/// Plays a `StageTransition` between two rendered frames: the old stage
/// stays put while the geometry uncovers more of the new one each pass,
/// presented until the duration runs out. Director blocks the movie during
/// a transition, and so does this.
@MainActor
enum TransitionAnimator {
  static func play(
    _ transition: StageTransition, from old: SDLTexture, to new: SDLTexture,
    renderer: SDLRenderer, width: Int, height: Int
  ) {
    let start = SDL_GetTicks()
    let duration = UInt64(max(1, transition.durationMilliseconds))
    while true {
      let elapsed = SDL_GetTicks() - start
      let progress = min(1, Double(elapsed) / Double(duration))
      try? renderer.copy(old, destination: SDL_FRect(x: 0, y: 0, w: Float(width), h: Float(height)))
      for rect in TransitionGeometry.revealedRects(
        type: transition.type, progress: progress, width: width, height: height,
        chunkSize: transition.chunkSize)
      {
        let region = SDL_FRect(
          x: Float(rect.x), y: Float(rect.y), w: Float(rect.width), h: Float(rect.height))
        try? renderer.copy(new, source: region, destination: region)
      }
      renderer.present()
      if progress >= 1 { return }
      SDL_Delay(16)
    }
  }
}
