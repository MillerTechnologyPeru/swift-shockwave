import BinaryParsing

/// The `CLUT` chunk: a color lookup table for palette cast members. Each
/// entry stores 16-bit big-endian red/green/blue components (the high byte
/// carries the 8-bit color).
public struct PaletteChunk: Sendable {
  public struct Color: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
      self.red = red
      self.green = green
      self.blue = blue
    }
  }

  public var colors: [Color]

  public init(colors: [Color]) {
    self.colors = colors
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let count = input.count / 6
    var colors: [Color] = []
    colors.reserveCapacity(count)
    for _ in 0..<count {
      let red = try UInt16(parsingBigEndian: &input)
      let green = try UInt16(parsingBigEndian: &input)
      let blue = try UInt16(parsingBigEndian: &input)
      colors.append(
        Color(red: UInt8(red >> 8), green: UInt8(green >> 8), blue: UInt8(blue >> 8)))
    }
    self.colors = colors
  }
}
