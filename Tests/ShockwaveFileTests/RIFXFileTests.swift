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
  let file = try RIFXFile.read(from: realMovieData())
  #expect(file.header.byteOrder.isLittleEndian)
  #expect(file.header.formatCode == "MV93")
}

@Test func realMovieChunkMapWalks() throws {
  let file = try RIFXFile.read(from: realMovieData())
  #expect(!file.chunkMap.isEmpty)
  #expect(!file.entries(fourCC: "Lscr").isEmpty)
  #expect(!file.entries(fourCC: "CASt").isEmpty)
  #expect(file.entries(fourCC: "VWSC").count == 1)  // score
}

@Test func realMovieNameTableResolves() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let names = try #require(try file.nameTable())
  #expect(!names.names.isEmpty)
  #expect(names.names.allSatisfy { !$0.isEmpty })
  #expect(names.names.contains("prepareMovie"))
  #expect(names.names.contains("startMovie"))
}

@Test func realMovieKeyTableResolves() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let keyTable = try #require(try file.keyTable())
  #expect(!keyTable.entries.isEmpty)
}

@Test func realMovieScriptContextBridges() throws {
  let file = try RIFXFile.read(from: realMovieData())
  let entry = try #require(file.entries(fourCC: "Lctx").first)
  let context = try file.scriptContext(at: entry)
  #expect(context.entryCount > 0)
  #expect(context.sectionMap.count == Int(context.entryCount))
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
