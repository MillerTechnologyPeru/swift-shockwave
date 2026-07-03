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
