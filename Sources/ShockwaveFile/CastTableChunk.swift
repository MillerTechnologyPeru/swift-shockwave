import BinaryParsing

/// The `CAS*` chunk: one cast library's member slots, in member-number
/// order, as big-endian resource ids of `CASt` chunks. A zero id is an empty
/// slot. Which library a given `CAS*` belongs to is determined by its owner
/// in the key table (`CastListEntry.resourceId`).
///
/// Always big-endian, independent of the container byte order.
public struct CastTableChunk: Sendable {
  public var memberIds: [Int]

  public init(memberIds: [Int]) {
    self.memberIds = memberIds
  }

  public init(parsing input: inout ParserSpan) throws(any Error) {
    let count = input.count / 4
    var memberIds: [Int] = []
    memberIds.reserveCapacity(count)
    for _ in 0..<count {
      memberIds.append(try Int(parsing: &input, storedAsBigEndian: UInt32.self))
    }
    self.memberIds = memberIds
  }
}
