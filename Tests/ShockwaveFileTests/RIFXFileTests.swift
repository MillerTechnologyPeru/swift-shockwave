import CryptoKit
import Foundation
import Testing

@testable import ShockwaveFile

@Test func readsBigEndianRIFXHeader() throws {
  let file = try RIFXFile.read(from: Data(RIFXFixture.make(bigEndian: true)))
  #expect(file.header.byteOrder.isBigEndian)
  #expect(file.header.formatCode == "MV93")
}

@Test func readsLittleEndianXFIRHeader() throws {
  let file = try RIFXFile.read(from: Data(RIFXFixture.make(bigEndian: false)))
  #expect(file.header.byteOrder.isLittleEndian)
  #expect(file.header.formatCode == "MV93")
}

@Test func chunkMapWalkFindsEveryChunk() throws {
  let file = try RIFXFile.read(from: Data(RIFXFixture.make()))
  #expect(file.chunkMap.count == 4)
  #expect(file.entries(fourCC: "Lnam").count == 1)
  #expect(file.entries(fourCC: "KEY*").count == 1)
}

@Test func nameTableResolvesNamesInOrder() throws {
  let file = try RIFXFile.read(from: Data(RIFXFixture.make()))
  let names = try #require(try file.nameTable())
  #expect(names.names == ["a", "bb"])
}

@Test func keyTableResolvesChunkRelationship() throws {
  let file = try RIFXFile.read(from: Data(RIFXFixture.make()))
  let keyTable = try #require(try file.keyTable())
  #expect(keyTable.entries.count == 1)
  let relationship = try #require(keyTable.entries.first)
  #expect(relationship.fourCC == "Lnam")
  #expect(file.chunkMap[relationship.childChunkIndex].fourCC == "Lnam")
  #expect(file.chunkMap[relationship.ownerChunkIndex].fourCC == "mmap")
}

@Test func movieConfigIsAbsentWhenNoConfigChunkExists() throws {
  let file = try RIFXFile.read(from: Data(RIFXFixture.make()))
  #expect(try file.movieConfig() == nil)
}

private func realMovieData() throws -> Data {
  let url = try #require(
    Bundle.module.url(
      forResource: "junkbot2_13g_asp", withExtension: "dir", subdirectory: "Resources"))
  return try Data(contentsOf: url)
}

@Test func realMovieParsesHeader() throws {
  let data = try realMovieData()
  let file = try RIFXFile.read(from: data)
  #expect(file.header.byteOrder.isLittleEndian)
  #expect(file.header.formatCode == "MV93")
  #expect(file.header.length == 6_368_680)
  #expect(file.header.length + 8 == data.count)
}

@Test func realMovieChunkMapWalks() throws {
  let file = try RIFXFile.read(from: realMovieData())
  #expect(file.chunkMap.count == 155_336)
  #expect(file.entries(fourCC: "free").count == 152_456)
  #expect(file.entries(fourCC: "CASt").count == 1400)
  #expect(file.entries(fourCC: "BITD").count == 1085)
  #expect(file.entries(fourCC: "XMED").count == 122)
  #expect(file.entries(fourCC: "Lscr").count == 114)
  #expect(file.entries(fourCC: "snd ").count == 39)
  #expect(file.entries(fourCC: "ediM").count == 23)
  #expect(file.entries(fourCC: "STXT").count == 18)
  #expect(file.entries(fourCC: "Lctx").count == 13)
  #expect(file.entries(fourCC: "Cinf").count == 13)
  #expect(file.entries(fourCC: "Lnam").count == 13)
  #expect(file.entries(fourCC: "CAS*").count == 12)
  #expect(file.entries(fourCC: "SCVW").count == 6)  // film loops
  #expect(file.entries(fourCC: "VWSC").count == 1)  // the movie score
  #expect(file.entries(fourCC: "imap").count == 1)
  #expect(file.entries(fourCC: "mmap").count == 1)
  #expect(file.entries(fourCC: "KEY*").count == 1)
  #expect(file.entries(fourCC: "DRCF").count == 1)
}

@Test func realMovieNameTableResolves() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let names = try #require(try file.nameTable())
  #expect(names.names.count == 893)
  #expect(
    Array(names.names.prefix(10)) == [
      "prepareMovie", "startMovie", "movieloaded", "stopMovie", "streamStatus",
      "keyDown", "gbutton", "do_editor", "do_catalog", "do_player",
    ])
  #expect(Array(names.names.suffix(3)) == ["checksum", "checkvalue", "frameLabel"])
  // Full-table stability pin: any change to Lnam parsing that reorders,
  // drops, or corrupts names changes this digest.
  let digest = SHA256.hash(data: Data(names.names.joined(separator: "\n").utf8))
  let digestHex = digest.map { String(format: "%02x", $0) }.joined()
  #expect(digestHex == "de8d6e565abb1feb7ab008555df57134604253d0cd1ad8c93b3b0dd888d1b618")
}

@Test func realMovieKeyTableResolves() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let keyTable = try #require(try file.keyTable())
  #expect(keyTable.entries.count == 2647)

  let first = try #require(keyTable.entries.first)
  #expect(first.childChunkIndex == 152_591)
  #expect(first.ownerChunkIndex == 9)
  #expect(first.fourCC == "BITD")

  // 17 entries reference children past the end of the chunk map — dangling
  // records for deleted chunks (FCOL/GRID/PUBL/SCRF) that Director left in
  // the key table. Everything else resolves.
  let dangling = keyTable.entries.filter { $0.childChunkIndex >= file.chunkMap.count }
  #expect(dangling.count == 17)
  #expect(dangling.allSatisfy { ["FCOL", "GRID", "PUBL", "SCRF"].contains($0.fourCC.description) })

  // The chunks owned directly by the movie (fixed resource id 1024) are its
  // movie-level singletons.
  let movieOwned = keyTable.entries.filter { $0.ownerChunkIndex == 1024 }
  #expect(
    movieOwned.map(\.fourCC.description).sorted() == [
      "DRCF", "FCOL", "FXmp", "GRID", "MCsL", "PUBL", "SCRF",
      "Sord", "VERS", "VWFI", "VWLB", "VWSC", "XTRl",
    ])
}

@Test func realMovieScriptContextBridges() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let entry = try #require(file.entries(fourCC: "Lctx").first)
  let context = try file.scriptContext(at: entry)
  #expect(context.entryCount == 31)
  #expect(context.entryCount2 == 31)
  #expect(context.entriesOffset == 96)
  #expect(context.lnamSectionId == 152_195)
  #expect(context.validCount == 25)
  #expect(context.flags == 5)
  #expect(context.sectionMap.count == 31)
  #expect(context.sectionMap.first?.sectionId == 152_196)
  // lnamSectionId is a resource id: it must resolve to this cast's Lnam
  // chunk in the chunk map.
  let lnamEntry = file.chunkMap[Int(context.lnamSectionId)]
  #expect(lnamEntry.fourCC == "Lnam")
  #expect(lnamEntry.length == 8806)
}

@Test func realMovieConfigParses() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let config = try #require(try file.movieConfig())
  #expect(config.rawData.count == 84)
}

@Test func realMovieCastListParses() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let castList = try #require(try file.castList())
  #expect(
    castList.entries.map(\.name) == [
      "Internal", "legoparts", "catalog", "editor", "play", "peter 101", "sound",
      "levels", "dynamic", "unused levels", "screens_by_peter", "backgrounds", "loading",
    ])
  #expect(castList.entries.allSatisfy { $0.filePath.isEmpty })
  #expect(castList.entries.allSatisfy { $0.preloadMode == 0 })

  let internalCast = castList.entries[0]
  #expect(internalCast.resourceId == nil)

  let legoparts = castList.entries[1]
  #expect(legoparts.minMember == 1)
  #expect(legoparts.maxMember == 44)
  #expect(legoparts.resourceId == 0x10400)
}

@Test func realMovieCastTableJoinsThroughKeyTable() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let castList = try #require(try file.castList())
  let keyTable = try #require(try file.keyTable())
  let legoparts = castList.entries[1]

  let tableEntry = try #require(
    keyTable.entries.first {
      $0.fourCC == "CAS*" && $0.ownerChunkIndex == legoparts.resourceId
    })
  let table = try file.castTable(at: file.chunkMap[tableEntry.childChunkIndex])
  #expect(table.memberIds.count == 44)
  #expect(table.memberIds.allSatisfy { $0 != 0 })
  #expect(table.memberIds.first == 344)
  #expect(table.memberIds.allSatisfy { file.chunkMap[$0].fourCC == "CASt" })
}

@Test func realMovieCastMemberParses() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let member = try file.castMember(at: file.chunkMap[344])
  #expect(member.type == .script)
  #expect(member.name == "main")
  #expect(member.scriptId == 25)
  #expect(member.specificData == Data([0x00, 0x03]))  // movie script

  let scriptText = try #require(member.scriptText)
  #expect(scriptText.count == 3611)
  #expect(scriptText.hasPrefix("global glob, version"))
  let digest = SHA256.hash(data: Data(scriptText.utf8))
  let digestHex = digest.map { String(format: "%02x", $0) }.joined()
  #expect(digestHex == "470f69e971ab54162081659b5f10dc5205d3495548f6f9e8914712cb1a13dd10")
}

@Test func realMovieCastMemberNamesAreStable() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let castList = try #require(try file.castList())
  let keyTable = try #require(try file.keyTable())
  let legoparts = castList.entries[1]
  let tableEntry = try #require(
    keyTable.entries.first {
      $0.fourCC == "CAS*" && $0.ownerChunkIndex == legoparts.resourceId
    })
  let table = try file.castTable(at: file.chunkMap[tableEntry.childChunkIndex])

  var names: [String] = []
  for memberId in table.memberIds {
    let member = try file.castMember(at: file.chunkMap[memberId])
    names.append(member.name ?? "")
  }
  #expect(names.prefix(3) == ["main", "Display Text", "Tooltip"])
  let digest = SHA256.hash(data: Data(names.joined(separator: "\n").utf8))
  let digestHex = digest.map { String(format: "%02x", $0) }.joined()
  #expect(digestHex == "045f0a64127ba6ee7be077a4b44f55ed21e0188106cce68f6d9dbb0d9fa2c235")
}

@Test func realMovieFrameLabelsParse() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let labels = try #require(try file.frameLabels()).labels
  #expect(labels.count == 9)
  #expect(labels.map(\.frame) == [5, 7, 9, 14, 18, 21, 24, 26, 29])
  #expect(
    labels.map(\.name) == [
      "bumper", "loading", "mainmenu", "play", "levels", "ho-fame", "help", "help2", "credits",
    ])
}

@Test func realMovieScoreOrderParses() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let order = try #require(try file.scoreOrder()).members
  #expect(order.count == 1400)
  #expect(order[0] == ScoreOrderChunk.MemberReference(castLib: 1, member: 43))
  #expect(order[1] == ScoreOrderChunk.MemberReference(castLib: 7, member: 27))
}

@Test func realMovieScoreParses() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let score = try #require(try file.score())
  #expect(score.version == 13)
  #expect(score.channelRecordSize == 48)
  #expect(score.channelCount == 1006)
  #expect(score.displayedChannelCount == 1000)
  #expect(score.frames.count == 30)

  // Frame 1's script channel carries the "frameloop" behavior of the
  // legoparts cast (file-internal lib 1, member 4).
  let scriptChannel = try #require(score.frames[0].channels[0])
  #expect(scriptChannel.count == 48)
  #expect(Array(scriptChannel.prefix(4)) == [0x00, 0x01, 0x00, 0x04])

  #expect(score.behaviorIntervals.count == 431)
  let channel0 = score.behaviorIntervals.filter { $0.channel == 0 }
  #expect(channel0.count == 10)
  let frameloopUses = score.behaviorIntervals.filter {
    $0.behaviors.contains(ScoreChunk.BehaviorReference(castLib: 1, member: 6))
  }
  #expect(frameloopUses.count == 108)
}

@Test func realShockwaveMovieIsDetectedAsCompressed() throws {
  let url = try #require(
    Bundle.module.url(
      forResource: "junkbot2_13g_asp", withExtension: "dcr", subdirectory: "Resources"))
  let data = try Data(contentsOf: url)
  #expect(throws: ShockwaveFileError.compressedContainerUnsupported) {
    try RIFXFile.read(from: data)
  }
}

@Test func scriptContextBridgesToLingoBytecode() throws {
  let (bytes, lctxEntryIndex) = RIFXFixture.makeWithScriptContext()
  let file = try RIFXFile.read(from: Data(bytes))
  let entry = file.chunkMap[lctxEntryIndex]
  #expect(entry.fourCC == "Lctx")

  let context = try file.scriptContext(at: entry)
  #expect(context.entryCount == 2)
  #expect(context.lnamSectionId == 10)
  #expect(context.sectionMap.count == 2)
  #expect(context.sectionMap[0].sectionId == -1)
  #expect(context.sectionMap[1].sectionId == -2)
}
