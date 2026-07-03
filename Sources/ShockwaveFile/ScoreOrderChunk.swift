import BinaryParsing

/// The `Sord` chunk: cast members in score order (the order Director loads
/// them for playback), as `(castLib, member)` pairs. The `castLib` here uses
/// the file-internal library numbering from `CastListEntry.resourceId`
/// (`resourceId >> 16`), not the 1-based `MCsL` position.
///
/// Always big-endian, independent of the container byte order.
public struct ScoreOrderChunk: Sendable {
  public struct MemberReference: Equatable, Sendable {
    public var castLib: Int
    public var member: Int

    public init(castLib: Int, member: Int) {
      self.castLib = castLib
      self.member = member
    }
  }

  public var members: [MemberReference]

  public init(members: [MemberReference]) {
    self.members = members
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let payloadStart = input.startPosition
    let _ = try UInt32(parsingBigEndian: &input)  // unknown
    let _ = try UInt32(parsingBigEndian: &input)  // unknown
    let count = try Int(parsing: &input, storedAsBigEndian: UInt32.self)
    let _ = try UInt32(parsingBigEndian: &input)  // count, repeated
    let headerSize = try Int(parsing: &input, storedAsBigEndian: UInt16.self)
    let entrySize = try Int(parsing: &input, storedAsBigEndian: UInt16.self)

    let consumed = input.startPosition - payloadStart
    guard headerSize >= consumed else {
      throw ShockwaveFileError.invalidOffset(headerSize)
    }
    try input.seek(toRelativeOffset: headerSize - consumed)

    var members: [MemberReference] = []
    members.reserveCapacity(count)
    for _ in 0..<count {
      var record = try input.sliceSpan(byteCount: entrySize)
      let castLib = try Int(parsing: &record, storedAsBigEndian: UInt16.self)
      let member = try Int(parsing: &record, storedAsBigEndian: UInt16.self)
      members.append(MemberReference(castLib: castLib, member: member))
    }
    self.members = members
  }
}
