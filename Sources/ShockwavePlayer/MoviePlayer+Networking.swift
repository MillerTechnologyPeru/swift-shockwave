import LingoRuntime

extension MoviePlayer {
  /// Stubs for Director's network Lingo verbs: no actual I/O happens, but
  /// every request reports itself as immediately, successfully done. This
  /// unblocks movies whose intro/loading logic polls `netDone(id)` before
  /// proceeding (they'd otherwise loop forever waiting on a network layer
  /// that doesn't exist here) without pretending to be a real network
  /// stack. `netTextResult` has nothing to return, so callers that actually
  /// depend on fetched content will just see an empty string.
  func registerNetworkingBuiltins() {
    let environment = movieModel.lingoEnvironment

    environment.registerGlobalFunction("preloadNetThing") { [weak self] _ in
      .integer(self?.nextNetID() ?? 0)
    }
    environment.registerGlobalFunction("getNetText") { [weak self] _ in
      .integer(self?.nextNetID() ?? 0)
    }
    environment.registerGlobalFunction("postNetText") { [weak self] _ in
      .integer(self?.nextNetID() ?? 0)
    }
    environment.registerGlobalFunction("preloadNetMovie") { [weak self] _ in
      .integer(self?.nextNetID() ?? 0)
    }
    environment.registerGlobalFunction("getLatestNetID") { [weak self] _ in
      .integer(self?.lastNetID ?? 0)
    }
    // Every request is considered done the instant it's issued.
    environment.registerGlobalFunction("netDone") { _ in .integer(1) }
    environment.registerGlobalFunction("netError") { _ in .string("OK") }
    environment.registerGlobalFunction("netTextResult") { _ in .string("") }
    environment.registerGlobalFunction("checkNetConnection") { _ in .integer(1) }
    environment.registerGlobalFunction("gotoNetPage") { _ in .void }
    environment.registerGlobalFunction("netMIME") { _ in .string("") }
  }

  private func nextNetID() -> Int {
    lastNetID += 1
    return lastNetID
  }
}
