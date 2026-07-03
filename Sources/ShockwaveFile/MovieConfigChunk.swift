import Foundation

/// The movie config chunk (`VWCF`/`DRCF`). Field-level layout (stage rect,
/// frame rate, platform, protection flags, ...) varies across Director
/// versions and is deferred until it can be validated against real sample
/// files; phase 1 only preserves the raw payload.
public struct MovieConfigChunk: Sendable {
  public var rawData: Data

  public init(rawData: Data) {
    self.rawData = rawData
  }
}
