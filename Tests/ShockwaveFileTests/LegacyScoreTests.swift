import Foundation
import ShockwaveFile
import Testing

/// Director 4/5 scores are the frame data alone — no Director 6 offset-
/// table shell — with a zero frame count meaning "read to the end", one
/// main channel ahead of the sprites, and their own sprite record
/// layouts. These bytes are built to those layouts, as verified against
/// ScummVM's reader and the ScummVM director-tests movies.
private func u16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
private func u32(_ value: Int) -> [UInt8] {
  [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
}

/// One frame whose single patch writes a Director 5 sprite record into
/// data channel 1 — Lingo's sprite 1.
private func d5ScoreBytes() -> [UInt8] {
  var record: [UInt8] = []
  record += [1]  // sprite type: bitmap
  record += [8 | 0x40]  // ink matte, trails
  record += u16(1)  // castLib
  record += u16(7)  // member
  record += u16(0) + u16(0)  // script ref
  record += [35, 6]  // fore/back
  record += u16(40) + u16(60)  // top, left
  record += u16(30) + u16(50)  // height, width
  record += [0x40, 128, 0, 0]  // editable, blend, thickness, pad
  let patch = u16(record.count) + u16(24) + record  // offset 24 = channel 1
  let frame = u16(2 + patch.count) + patch
  var head = u32(0)  // total length, patched below
  head += u32(20)  // frame-1 offset
  head += u32(0)  // frame count: run to the end
  head += u16(7) + u16(24) + u16(50) + u16(0)  // version, record size, channels
  var bytes = head + frame
  bytes.replaceSubrange(0..<4, with: u32(bytes.count))
  return bytes
}

@Test func directorFiveScoreDecodes() throws {
  let data = Data(d5ScoreBytes())
  let score = try data.withParserSpan { span in
    try ScoreChunk(parsing: &span)
  }
  #expect(score.version == 7)
  #expect(score.channelRecordSize == 24)
  #expect(score.frames.count == 1)
  // The caller addresses sprites in 6+ numbering (sprite n at n + 5);
  // the frame maps that back to the old channel layout.
  let record = try #require(score.frames[0].spriteRecord(channel: 6))
  #expect(record.spriteType == 1)
  #expect(record.ink == 8)
  #expect(record.trails)
  #expect(record.castLib == 1)
  #expect(record.member == 7)
  #expect(record.foreColor == 35)
  #expect(record.backColor == 6)
  #expect(record.top == 40)
  #expect(record.left == 60)
  #expect(record.height == 30)
  #expect(record.width == 50)
  #expect(record.isEditable)
  #expect(record.blendEnabled)
}

@Test func directorFourSpriteRecordDecodes() {
  var bytes: [UInt8] = []
  bytes += [0, 1]  // script id (unused), sprite type
  bytes += [35, 6]  // fore/back
  bytes += [0]  // thickness
  bytes += [36 | 0x80]  // ink, stretch
  bytes += u16(9)  // member (single internal cast)
  bytes += u16(40) + u16(60)  // top, left
  bytes += u16(30) + u16(50)  // height, width
  bytes += u16(0)  // script
  bytes += [0x80, 0]  // moveable; no blend
  let record = SpriteChannelRecord(bytes: bytes, version: 4)!
  #expect(record.spriteType == 1)
  #expect(record.ink == 36)
  #expect(record.stretch)
  #expect(record.castLib == 1)
  #expect(record.member == 9)
  #expect(record.top == 40)
  #expect(record.left == 60)
  #expect(record.isMoveable)
  #expect(!record.blendEnabled)
  #expect(record.blendPercent == 100)
}

/// The Director 4 `CASt` shell: a 16-bit data length, a 32-bit info
/// length, and the member type as the data's first byte.
@Test func directorFourCastMemberDecodes() throws {
  var data: [UInt8] = [1, 0]  // type bitmap, flags
  data += u16(8)  // rowBytes
  data += u16(6) + u16(7) + u16(41) + u16(56)  // bounds
  data += u16(6) + u16(7) + u16(78) + u16(79)  // bounding rect
  data += u16(23) + u16(31)  // registration
  let chunk = u16(data.count) + u32(0) + data
  let member = try Data(chunk).withParserSpan { span in
    try CastMemberChunk(parsing: &span)
  }
  #expect(member.type == .bitmap)
  let properties = try #require(member.bitmapProperties)
  #expect(properties.rowBytes == 8)
  #expect(properties.bounds == DirectorRect(top: 6, left: 7, bottom: 41, right: 56))
  #expect(properties.regY == 23)
  #expect(properties.regX == 31)
  // Director 4 stopped before the depth byte; those members are 1-bit.
  #expect(properties.bitsPerPixel == 1)
}
