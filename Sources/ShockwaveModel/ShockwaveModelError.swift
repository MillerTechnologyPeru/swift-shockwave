public enum ShockwaveModelError: Error, Equatable, Sendable {
  /// The movie has no `MCsL` chunk. Pre-Director-5 movies stored a single,
  /// unnamed cast without one; that layout isn't handled yet.
  case missingCastList
}
