import LingoRuntime
import ShockwaveModel

/// The keyboard as Lingo sees it.
///
/// Like the mouse, it feeds two styles of script. Discrete events —
/// `keyDown`/`keyUp`, which Director sends to the frame script and then the
/// movie scripts (the sample's frame behavior fans `the key` out to its
/// "keyboard equivalent" buttons from there) — and polled state: `the key`
/// and `the keyCode` describe the last key that went down, the modifier
/// properties the current modifiers, and `keyPressed(...)` answers whether
/// a given key is held right now, which is how the play manager reads the
/// space bar every frame.
extension MoviePlayer {
  /// A key going down. `character` is what the key types (already
  /// shifted); `code` is the Mac virtual key code Director exposes as
  /// `the keyCode`, or -1 when the host has no mapping for it.
  public func pressKey(character: String, code: Int) {
    movieModel.setProperty("key", value: .string(character))
    movieModel.setProperty("keyCode", value: .integer(code))
    heldKeyCharacters.insert(character.asciiLowercased())
    heldKeyCodes.insert(code)
    dispatch("keyDown")
  }

  /// The key coming up. `the key`/`the keyCode` keep describing the last
  /// key pressed — Director leaves them in place — only the held set and
  /// the event change.
  public func releaseKey(character: String, code: Int) {
    heldKeyCharacters.remove(character.asciiLowercased())
    heldKeyCodes.remove(code)
    dispatch("keyUp")
  }

  /// The current modifier keys, polled by `the shiftDown` and friends.
  public func setModifiers(shift: Bool, option: Bool, command: Bool, control: Bool) {
    movieModel.setProperty("shiftDown", value: .integer(shift ? 1 : 0))
    movieModel.setProperty("optionDown", value: .integer(option ? 1 : 0))
    movieModel.setProperty("commandDown", value: .integer(command ? 1 : 0))
    movieModel.setProperty("controlDown", value: .integer(control ? 1 : 0))
  }

  /// `keyPressed()` with no argument is `the key`; with one, whether that
  /// key — a character string or a Mac key code — is held down now.
  func registerKeyboardBuiltins() {
    movieModel.lingoEnvironment.registerGlobalFunction("keyPressed") { [weak self] args in
      guard let self else { return .integer(0) }
      guard let argument = args.first else { return self.movieModel.getProperty("key") }
      switch argument {
      case .integer(let code):
        return .integer(self.heldKeyCodes.contains(code) ? 1 : 0)
      default:
        let character = argument.asString().asciiLowercased()
        return .integer(self.heldKeyCharacters.contains(character) ? 1 : 0)
      }
    }
  }
}
