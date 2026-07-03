import BinaryParsing
import Foundation

/// The movie config chunk (`VWCF`/`DRCF`). Only the version code is decoded;
/// the remaining field layout (stage rect, frame rate, platform, protection
/// flags, ...) varies across Director versions and stays raw until it can be
/// validated against more sample files.
///
/// Always big-endian, independent of the container byte order.
public struct MovieConfigChunk: Sendable {
  /// The file-format version code (e.g. `0x640` for a Director 7-era file).
  public var fileVersion: Int
  public var rawData: Data

  public init(fileVersion: Int, rawData: Data) {
    self.fileVersion = fileVersion
    self.rawData = rawData
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let rawData = Data(parsingRemainingBytes: &input)
    guard rawData.count >= 4 else {
      throw ShockwaveFileError.invalidOffset(rawData.count)
    }
    let fileVersion =
      Int(rawData[rawData.startIndex + 2]) << 8 | Int(rawData[rawData.startIndex + 3])
    self.init(fileVersion: fileVersion, rawData: rawData)
  }
}
