public enum ShockwaveFileError: Error, Equatable, Sendable {
  /// The file doesn't start with a recognized `RIFX`/`XFIR` container magic.
  case invalidMagic
  /// A chunk tag didn't match what the caller expected at this position.
  case unexpectedChunk(FourCharCode, expected: FourCharCode)
  /// An offset stored inside a chunk fell outside the file's bounds.
  case invalidOffset(Int)
  /// The container envelope is Afterburner-compressed (`Fver`), which phase 1 doesn't parse.
  /// This is the format used by Shockwave-for-web `.dcr`/`.cct` files, as opposed to the
  /// plain-RIFX `.dir`/`.cst`/`.dxr`/`.cxt` files this module does handle.
  case compressedContainerUnsupported
}
