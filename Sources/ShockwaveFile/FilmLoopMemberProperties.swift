import Foundation

/// The type-specific data of a film loop cast member: the bounding rect of
/// the frames it plays (in the coordinate space its own score records use)
/// and a flag word.
///
/// A film loop's frames live in a `SCVW` chunk the member owns through the
/// key table — the same layout as the movie's `VWSC`, whose sprite records
/// name members in the film loop's own cast as `castLib 65535`. On stage
/// the member's registration point is the center of `bounds`, so a sprite
/// at `loc` shows the loop's frame with `bounds` centered there.
public struct FilmLoopMemberProperties: Equatable, Sendable {
  public var bounds: DirectorRect
  public var flags: Int

  public init(bounds: DirectorRect, flags: Int) {
    self.bounds = bounds
    self.flags = flags
  }

  public init?(specificData: Data) {
    guard specificData.count >= 8 else { return nil }
    let bytes = [UInt8](specificData)
    func i16(_ offset: Int) -> Int {
      Int(Int16(bitPattern: UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])))
    }
    bounds = DirectorRect(top: i16(0), left: i16(2), bottom: i16(4), right: i16(6))
    flags = bytes.count >= 12 ? Int(bytes[10]) << 8 | Int(bytes[11]) : 0
  }
}

extension CastMemberChunk {
  /// Decodes the film-loop-specific data for film loop members; `nil` for
  /// every other member type.
  public var filmLoopProperties: FilmLoopMemberProperties? {
    guard type == .filmLoop else { return nil }
    return FilmLoopMemberProperties(specificData: specificData)
  }
}
