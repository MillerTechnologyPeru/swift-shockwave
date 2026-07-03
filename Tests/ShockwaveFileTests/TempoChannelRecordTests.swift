import Testing

@testable import ShockwaveFile

@Test func tempoRecordDecodesDirectFPS() throws {
  // Byte 6 = 15 (direct FPS, valid for all format versions).
  let bytes: [UInt8] = [
    0, 0, 0, 0,  // spriteListIndex
    0, 0,  // tempoCuePoint
    15,  // tempo
    0,  // colorTempo
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // waitFlags, channelFlags, skip
    0, 0,  // frameData
  ]
  let record = try #require(TempoChannelRecord(bytes: bytes))
  #expect(record.tempo == 15)
  #expect(!record.isDefaultMarker)
  #expect(!record.isEmpty)
}

@Test func tempoRecordDecodesFPSViaCuePoint() throws {
  // D6+ mode: tempo byte 246 means "FPS is in tempoCuePoint".
  let bytes: [UInt8] = [
    0, 0, 0, 0,
    0, 24,  // tempoCuePoint = 24
    246,  // tempo mode: FPS-via-cue-point
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ]
  let record = try #require(TempoChannelRecord(bytes: bytes))
  #expect(record.tempo == 246)
  #expect(record.tempoCuePoint == 24)
}

@Test func tempoRecordRecognizesDefaultMarker() throws {
  // High 16 bits of spriteListIndex == 0xFFFE marks "no change" in the
  // delta buffer, not a real tempo setting.
  let bytes: [UInt8] = [
    0xFF, 0xFE, 0, 0,
    0, 0, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ]
  let record = try #require(TempoChannelRecord(bytes: bytes))
  #expect(record.isDefaultMarker)
}

@Test func tempoRecordRecognizesEmpty() throws {
  let record = try #require(TempoChannelRecord(bytes: [UInt8](repeating: 0, count: 20)))
  #expect(record.isEmpty)
}

@Test func frameTempoIgnoresDefaultAndEmptyRecords() throws {
  let defaultMarkerBytes: [UInt8] = [
    0xFF, 0xFE, 0, 0, 0, 0, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ]
  let frame = ScoreChunk.Frame(channels: [1: defaultMarkerBytes])
  #expect(frame.tempoRecord() == nil)

  let emptyFrame = ScoreChunk.Frame(channels: [1: [UInt8](repeating: 0, count: 20)])
  #expect(emptyFrame.tempoRecord() == nil)

  let untouchedFrame = ScoreChunk.Frame(channels: [:])
  #expect(untouchedFrame.tempoRecord() == nil)
}
