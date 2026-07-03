import BinaryParsing

@testable import ShockwaveFile

/// Hand-assembles a minimal but structurally real RIFX file (header → `imap`
/// → `mmap` → `Lnam` → `KEY*`) so the chunk-map walk and chunk parsers can be
/// exercised without a real Director sample file.
enum RIFXFixture {
  static func make(bigEndian: Bool = true) -> [UInt8] {
    func u32(_ value: UInt32) -> [UInt8] {
      let v = bigEndian ? value.bigEndian : value.littleEndian
      return withUnsafeBytes(of: v) { Array($0) }
    }
    func u16(_ value: UInt16) -> [UInt8] {
      let v = bigEndian ? value.bigEndian : value.littleEndian
      return withUnsafeBytes(of: v) { Array($0) }
    }
    // Tags follow the container byte order, so a little-endian file stores
    // them byte-reversed ("pami" for "imap").
    func tag(_ s: String) -> [UInt8] {
      let bytes = Array(s.utf8)
      return bigEndian ? bytes : bytes.reversed()
    }
    func chunk(_ tagString: String, _ payload: [UInt8]) -> [UInt8] {
      var bytes = tag(tagString)
      bytes += u32(UInt32(payload.count))
      bytes += payload
      if payload.count % 2 == 1 { bytes.append(0) }
      return bytes
    }

    let headerSize = 12
    let imapPayload = u32(1) + u32(0)  // memoryMapOffset patched below
    let imapChunkSize = 8 + imapPayload.count
    let mmapOffset = headerSize + imapChunkSize

    // Lingo chunk payloads are always big-endian, independent of the
    // container byte order.
    func be32(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
    func be16(_ value: UInt16) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }

    var lnamNames: [UInt8] = []
    for name in ["a", "bb"] {
      lnamNames += [UInt8(name.utf8.count)] + Array(name.utf8)
    }
    let lnamPayloadSize = 20 + lnamNames.count
    var lnamPayload = be32(0) + be32(0)
    lnamPayload += be32(UInt32(lnamPayloadSize)) + be32(UInt32(lnamPayloadSize))
    lnamPayload += be16(20) + be16(2)  // namesOffset, count
    lnamPayload += lnamNames

    var keyPayload = u16(12) + u16(0) + u32(1) + u32(1)
    keyPayload += u32(2) + u32(1) + tag("Lnam")  // Lnam (index 2) owned by mmap (index 1)

    let mmapPayloadHeaderSize = 24
    let entrySize = 20
    let entryCount = 4
    let mmapPayloadSize = mmapPayloadHeaderSize + entrySize * entryCount
    let mmapChunkSize = 8 + mmapPayloadSize

    let lnamOffset = mmapOffset + mmapChunkSize
    let lnamChunkSize = 8 + lnamPayload.count + (lnamPayload.count % 2)
    let keyOffset = lnamOffset + lnamChunkSize
    let keyChunkSize = 8 + keyPayload.count + (keyPayload.count % 2)
    let totalSize = keyOffset + keyChunkSize

    let imapPayloadFinal = u32(1) + u32(UInt32(mmapOffset))

    func entry(_ tagString: String, length: Int, offset: Int) -> [UInt8] {
      tag(tagString) + u32(UInt32(length)) + u32(UInt32(offset)) + u32(0) + u32(0)
    }
    var mmapPayload = u16(UInt16(mmapPayloadHeaderSize)) + u16(UInt16(entrySize))
    mmapPayload += u32(UInt32(entryCount)) + u32(UInt32(entryCount))
    mmapPayload += u32(0xFFFF_FFFF) + u32(0xFFFF_FFFF) + u32(0)  // junk/unknown/free pointers
    mmapPayload += entry("imap", length: imapPayload.count, offset: headerSize)
    mmapPayload += entry("mmap", length: mmapPayloadSize, offset: mmapOffset)
    mmapPayload += entry("Lnam", length: lnamPayload.count, offset: lnamOffset)
    mmapPayload += entry("KEY*", length: keyPayload.count, offset: keyOffset)

    var file = tag("RIFX")  // reversed to "XFIR" when little-endian
    file += u32(UInt32(totalSize - 8))
    file += tag("MV93")
    file += chunk("imap", imapPayloadFinal)
    file += chunk("mmap", mmapPayload)
    file += chunk("Lnam", lnamPayload)
    file += chunk("KEY*", keyPayload)
    return file
  }

  /// A minimal RIFX file (header → `imap` → `mmap` → `Lctx`) wrapping the
  /// same `Lctx` payload bytes `swift-lingo`'s own
  /// `ScriptContextChunkTests.scriptContextChunkLayout` uses, to confirm
  /// `RIFXFile.scriptContext(at:)` hands `LingoBytecode` a span shaped the
  /// way it expects.
  static func makeWithScriptContext() -> (bytes: [UInt8], lctxEntryIndex: Int) {
    func u32(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
    func u16(_ value: UInt16) -> [UInt8] { withUnsafeBytes(of: value.bigEndian) { Array($0) } }
    func tag(_ s: String) -> [UInt8] { Array(s.utf8) }
    func chunk(_ tagString: String, _ payload: [UInt8]) -> [UInt8] {
      var bytes = tag(tagString)
      bytes += u32(UInt32(payload.count))
      bytes += payload
      if payload.count % 2 == 1 { bytes.append(0) }
      return bytes
    }

    let lctxPayload: [UInt8] = [
      0x00, 0x00, 0x00, 0x00,  // unknown0
      0x00, 0x00, 0x00, 0x00,  // unknown1
      0x00, 0x00, 0x00, 0x02,  // entryCount = 2
      0x00, 0x00, 0x00, 0x02,  // entryCount2 = 2
      0x00, 0x2A,  // entriesOffset = 42
      0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x0A,  // lnamSectionId = 10
      0x00, 0x01,  // validCount = 1
      0x00, 0x00,  // flags = 0
      0x00, 0x00,  // freePointer = 0
      0x00, 0x00, 0x00, 0x01,
      0xFF, 0xFF, 0xFF, 0xFF,
      0x00, 0x0A,
      0x00, 0x0B,
      0x00, 0x00, 0x00, 0x02,
      0xFF, 0xFF, 0xFF, 0xFE,
      0x00, 0x0C,
      0x00, 0x0D,
    ]

    let headerSize = 12
    let imapPayload = u32(1) + u32(0)
    let imapChunkSize = 8 + imapPayload.count
    let mmapOffset = headerSize + imapChunkSize
    let imapPayloadFinal = u32(1) + u32(UInt32(mmapOffset))

    let entrySize = 20
    let entryCount = 3
    let mmapPayloadHeaderSize = 24
    let mmapPayloadSize = mmapPayloadHeaderSize + entrySize * entryCount
    let mmapChunkSize = 8 + mmapPayloadSize
    let lctxOffset = mmapOffset + mmapChunkSize

    func entry(_ tagString: String, length: Int, offset: Int) -> [UInt8] {
      tag(tagString) + u32(UInt32(length)) + u32(UInt32(offset)) + u32(0) + u32(0)
    }
    var mmapPayload = u16(UInt16(mmapPayloadHeaderSize)) + u16(UInt16(entrySize))
    mmapPayload += u32(UInt32(entryCount)) + u32(UInt32(entryCount))
    mmapPayload += u32(0xFFFF_FFFF) + u32(0xFFFF_FFFF) + u32(0)  // junk/unknown/free pointers
    mmapPayload += entry("imap", length: imapPayload.count, offset: headerSize)
    mmapPayload += entry("mmap", length: mmapPayloadSize, offset: mmapOffset)
    mmapPayload += entry("Lctx", length: lctxPayload.count, offset: lctxOffset)

    var file = tag("RIFX")
    file += u32(UInt32(0))  // patched below
    file += tag("MV93")
    file += chunk("imap", imapPayloadFinal)
    file += chunk("mmap", mmapPayload)
    file += chunk("Lctx", lctxPayload)

    let totalSize = file.count
    let lengthField = u32(UInt32(totalSize - 8))
    file.replaceSubrange(4..<8, with: lengthField)

    return (file, 2)
  }
}
