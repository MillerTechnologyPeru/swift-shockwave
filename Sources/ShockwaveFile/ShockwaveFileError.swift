public enum ShockwaveFileError: Error, Equatable, Sendable {
  /// The file doesn't start with a recognized `RIFX`/`XFIR` container magic.
  case invalidMagic
  /// A chunk tag didn't match what the caller expected at this position.
  case unexpectedChunk(FourCharCode, expected: FourCharCode)
  /// An offset stored inside a chunk fell outside the file's bounds.
  case invalidOffset(Int)
  /// The container's form type is `FGDM`/`FGDC`: an Afterburner-compressed
  /// Shockwave-for-web `.dcr`/`.cct` file, which phase 1 doesn't parse — as
  /// opposed to the uncompressed `.dir`/`.cst`/`.dxr`/`.cxt` form types this
  /// module does handle.
  case compressedContainerUnsupported
}
