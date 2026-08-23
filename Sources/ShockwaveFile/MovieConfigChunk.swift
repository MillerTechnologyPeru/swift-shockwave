import BinaryParsing
import Foundation

/// A rectangle as Director stores them: big-endian `top, left, bottom,
/// right` signed 16-bit fields.
public struct DirectorRect: Equatable, Sendable {
  public var top: Int
  public var left: Int
  public var bottom: Int
  public var right: Int

  public init(top: Int, left: Int, bottom: Int, right: Int) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }

  public init(parsing input: inout ParserSpan) throws(ParsingError) {
    top = try Int(parsing: &input, storedAsBigEndian: Int16.self)
    left = try Int(parsing: &input, storedAsBigEndian: Int16.self)
    bottom = try Int(parsing: &input, storedAsBigEndian: Int16.self)
    right = try Int(parsing: &input, storedAsBigEndian: Int16.self)
  }

  public var width: Int { right - left }
  public var height: Int { bottom - top }
}

/// The movie config chunk (`VWCF`/`DRCF`). The version code, stage rect,
/// and member range are decoded; the remaining field layout (frame rate,
/// platform, protection flags, ...) varies across Director versions and
/// stays raw until it can be validated against more sample files.
///
/// Always big-endian, independent of the container byte order.
public struct MovieConfigChunk: Sendable {
  /// The file-format version code (e.g. `0x640` for a Director 7-era file).
  public var fileVersion: Int
  public var stageRect: DirectorRect
  public var minMember: Int
  public var maxMember: Int
  /// The movie's authored frame rate (offset 54, fixed across format
  /// versions despite the branching field layout before it). `0` when the
  /// chunk is too short to reach that offset (older/truncated files);
  /// callers should fall back to a default (Director's own default is 30).
  public var frameRate: Int
  public var rawData: Data

  public init(
    fileVersion: Int, stageRect: DirectorRect, minMember: Int, maxMember: Int, frameRate: Int,
    rawData: Data
  ) {
    self.fileVersion = fileVersion
    self.stageRect = stageRect
    self.minMember = minMember
    self.maxMember = maxMember
    self.frameRate = frameRate
    self.rawData = rawData
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let bytes = [UInt8](parsingRemainingBytes: &input)
    guard bytes.count >= 16 else {
      throw ShockwaveFileError.invalidOffset(bytes.count)
    }
    func i16(_ offset: Int) -> Int {
      Int(Int16(bitPattern: UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])))
    }
    func u16(_ offset: Int) -> Int { Int(bytes[offset]) << 8 | Int(bytes[offset + 1]) }
    self.init(
      fileVersion: Int(bytes[2]) << 8 | Int(bytes[3]),
      stageRect: DirectorRect(top: i16(4), left: i16(6), bottom: i16(8), right: i16(10)),
      minMember: i16(12),
      maxMember: i16(14),
      frameRate: bytes.count >= 56 ? u16(54) : 0,
      rawData: Data(bytes))
  }
}
