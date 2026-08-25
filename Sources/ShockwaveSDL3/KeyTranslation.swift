import CSDL3
import SDL3Swift

/// Turns an SDL key event into what Lingo expects: the character the key
/// types and the Mac virtual key code Director exposes as `the keyCode` —
/// movies were authored against the Mac table whatever platform they ran
/// on, so arrows are 123–126 and the space bar is 49 everywhere.
enum KeyTranslation {
  /// Mac virtual key codes for the keys movies commonly test. Anything
  /// absent reports -1, which matches no `keyPressed(code)` check.
  private static let macKeyCodes: [Character: Int] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
    "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
    "n": 45, "m": 46, ".": 47, "`": 50,
  ]
  private static let specialKeyCodes: [UInt32: (character: String, code: Int)] = [
    UInt32(SDLK_RETURN): ("\r", 36), UInt32(SDLK_KP_ENTER): ("\u{3}", 76),
    UInt32(SDLK_TAB): ("\t", 48), UInt32(SDLK_SPACE): (" ", 49),
    UInt32(SDLK_BACKSPACE): ("\u{8}", 51), UInt32(SDLK_ESCAPE): ("\u{1B}", 53),
    UInt32(SDLK_LEFT): ("\u{1C}", 123), UInt32(SDLK_RIGHT): ("\u{1D}", 124),
    UInt32(SDLK_DOWN): ("\u{1F}", 125), UInt32(SDLK_UP): ("\u{1E}", 126),
    UInt32(SDLK_DELETE): ("\u{7F}", 117),
  ]
  /// What the shift key turns each unshifted printable into on a US
  /// layout, which is the layout Director's own table assumes.
  private static let shifted: [Character: Character] = [
    "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&",
    "8": "*", "9": "(", "0": ")", "-": "_", "=": "+", "[": "{", "]": "}",
    "\\": "|", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "`": "~",
  ]

  /// The (character, Mac key code) for an SDL keycode, or `nil` for keys
  /// that type nothing (modifiers, function keys).
  static func translate(keycode: UInt32, shift: Bool) -> (character: String, code: Int)? {
    if let special = specialKeyCodes[keycode] { return special }
    guard let scalar = Unicode.Scalar(keycode), keycode >= 0x20, keycode < 0x7F else {
      return nil
    }
    var character = Character(scalar)
    let code = macKeyCodes[character] ?? -1
    if shift {
      if let symbol = shifted[character] {
        character = symbol
      } else {
        character = Character(String(character).uppercased())
      }
    }
    return (String(character), code)
  }

  /// The current modifier state, polled at event time.
  static var modifiers: (shift: Bool, option: Bool, command: Bool, control: Bool) {
    let state = UInt32(SDL_GetModState())
    return (
      shift: state & SDL_KMOD_SHIFT != 0, option: state & SDL_KMOD_ALT != 0,
      command: state & SDL_KMOD_GUI != 0, control: state & SDL_KMOD_CTRL != 0
    )
  }
}
