import Foundation
import LingoBytecode
import LingoRuntime
import ShockwaveFile

extension Movie {
  public static func load(
    from file: RIFXFile,
    environment: LingoEnvironment = LingoEnvironment()
  ) throws -> Movie {
    guard let castList = try file.castList() else {
      throw ShockwaveModelError.missingCastList
    }
    let keyTable = try file.keyTable()

    var libraries: [CastLibrary] = []
    libraries.reserveCapacity(castList.entries.count)
    for (index, entry) in castList.entries.enumerated() {
      let libraryNumber = index + 1
      let members = try loadMembers(
        for: entry, libraryNumber: libraryNumber, file: file, keyTable: keyTable,
        environment: environment)
      libraries.append(
        CastLibrary(number: libraryNumber, entry: entry, members: members, environment: environment)
      )
    }

    var score: Score?
    if let scoreChunk = try file.score() {
      let labels = try file.frameLabels()?.labels ?? []
      score = Score(chunk: scoreChunk, labels: labels)
    }

    let config = try file.movieConfig()
    let fileVersion = config?.fileVersion ?? 0
    let frameRate = config?.frameRate ?? 0

    return Movie(
      castManager: CastManager(libraries: libraries), score: score, fileVersion: fileVersion,
      frameRate: frameRate, environment: environment)
  }

  /// Joins a cast library's members to their compiled scripts: `CAS*` gives
  /// the member chunk ids, and each script member's `CASt.scriptId` (a
  /// 1-based index into the cast's `Lctx` section map) resolves through that
  /// map to the `Lscr` chunk holding its compiled bytecode. The same `Lctx`
  /// also points at the cast's own `Lnam` name table, which every script in
  /// the cast shares.
  private static func loadMembers(
    for entry: CastListEntry,
    libraryNumber: Int,
    file: RIFXFile,
    keyTable: KeyTableChunk?,
    environment: LingoEnvironment
  ) throws -> [Int: CastMember] {
    guard let resourceId = entry.resourceId,
      let castTableRelationship = keyTable?.entries.first(where: {
        $0.fourCC == "CAS*" && $0.ownerChunkIndex == resourceId
      })
    else { return [:] }
    let castTable = try file.castTable(at: file.chunkMap[castTableRelationship.childChunkIndex])

    var sectionMap: [ScriptContextMapEntry] = []
    var scriptNames: [String] = []
    var capitalContext = false
    if let lctxRelationship = keyTable?.entries.first(where: {
      ($0.fourCC == "Lctx" || $0.fourCC == "LctX") && $0.ownerChunkIndex == resourceId
    }) {
      capitalContext = lctxRelationship.fourCC == "LctX"
      let context = try file.scriptContext(at: file.chunkMap[lctxRelationship.childChunkIndex])
      sectionMap = context.sectionMap
      let lnamId = Int(context.lnamSectionId)
      if lnamId >= 0, lnamId < file.chunkMap.count, file.chunkMap[lnamId].fourCC == "Lnam" {
        scriptNames = try file.withPayloadSpan(of: file.chunkMap[lnamId]) { payload in
          try NameTableChunk(parsing: &payload).names
        }
      }
    }

    // Text hangs off the member's own `CASt` chunk in the key table, the
    // same owned-by relationship bitmaps use for `BITD`: fields carry an
    // `STXT`, text xtras (rich text — junkbot's level definitions and
    // runtime messages) carry an `XMED`.
    var textChunkIds: [Int: Int] = [:]
    var mediaChunkIds: [Int: Int] = [:]
    var bitmapChunkIds: [Int: Int] = [:]
    var filmLoopScoreIds: [Int: Int] = [:]
    var soundChunkIds: [Int: Int] = [:]
    for relationship in keyTable?.entries ?? [] {
      guard relationship.childChunkIndex < file.chunkMap.count else { continue }
      if relationship.fourCC == "STXT" {
        textChunkIds[relationship.ownerChunkIndex] = relationship.childChunkIndex
      } else if relationship.fourCC == "XMED" {
        mediaChunkIds[relationship.ownerChunkIndex] = relationship.childChunkIndex
      } else if relationship.fourCC == "BITD" {
        bitmapChunkIds[relationship.ownerChunkIndex] = relationship.childChunkIndex
      } else if relationship.fourCC == "snd " {
        soundChunkIds[relationship.ownerChunkIndex] = relationship.childChunkIndex
      } else if relationship.fourCC == "ediM" {
        mediaChunkIds[relationship.ownerChunkIndex] = relationship.childChunkIndex
      } else if relationship.fourCC == "SCVW" || relationship.fourCC == "VWSC" {
        // A film loop's frames: a score chunk owned by the member.
        filmLoopScoreIds[relationship.ownerChunkIndex] = relationship.childChunkIndex
      }
    }

    let firstMemberNumber = entry.minMember ?? 1
    var members: [Int: CastMember] = [:]
    for (offset, memberId) in castTable.memberIds.enumerated() where memberId != 0 {
      let memberNumber = firstMemberNumber + offset
      let chunk = try file.castMember(at: file.chunkMap[memberId])
      let scriptChunk = try loadScriptChunk(for: chunk, sectionMap: sectionMap, file: file)
      var authoredText: String?
      var textStyle: XMediaText.Style?
      var textBox: (width: Int, height: Int)?
      var embeddedFont: PFRFont?
      if let textId = textChunkIds[memberId] {
        authoredText = try? file.textChunk(at: file.chunkMap[textId]).text
      } else if let mediaId = mediaChunkIds[memberId],
        let data = try? file.chunkData(at: file.chunkMap[mediaId])
      {
        // A font member's media is the font file itself; every other
        // xtra member's is styled text.
        if let font = PFRFont(data: data) {
          embeddedFont = font
        } else {
          authoredText = XMediaText.text(from: data)
          textStyle = XMediaText.style(from: data)
          textBox = XMediaText.boxSize(from: data)
        }
      }
      var bitmapData: Data?
      if chunk.type == .bitmap, let bitmapId = bitmapChunkIds[memberId] {
        bitmapData = try? file.chunkData(at: file.chunkMap[bitmapId])
      }
      var filmLoopScore: ScoreChunk?
      if chunk.type == .filmLoop, let scoreId = filmLoopScoreIds[memberId] {
        filmLoopScore = try? file.score(at: file.chunkMap[scoreId])
      }
      var soundData: Data?
      var shockwaveAudio: ShockwaveAudioMedia?
      if chunk.type == .sound {
        if let soundId = soundChunkIds[memberId],
          let data = try? file.chunkData(at: file.chunkMap[soundId]), !data.isEmpty
        {
          // A burned movie's sounds keep their `snd ` wrapper but hold a
          // Shockwave Audio stream where the samples were.
          if let media = ShockwaveAudioMedia(sndResource: data) {
            shockwaveAudio = media
          } else {
            soundData = data
          }
        } else if let mediaId = mediaChunkIds[memberId],
          let data = try? file.chunkData(at: file.chunkMap[mediaId])
        {
          shockwaveAudio = ShockwaveAudioMedia(ediMData: data)
        }
      }
      members[memberNumber] = CastMember(
        libraryNumber: libraryNumber, memberNumber: memberNumber, chunkId: memberId, chunk: chunk,
        scriptChunk: scriptChunk, scriptNames: scriptNames,
        scriptUsesCapitalContext: capitalContext, authoredText: authoredText,
        textStyle: textStyle, textBox: textBox, embeddedFont: embeddedFont,
        bitmapData: bitmapData,
        filmLoopScore: filmLoopScore,
        soundData: soundData, shockwaveAudio: shockwaveAudio, environment: environment)
    }
    return members
  }

  private static func loadScriptChunk(
    for member: CastMemberChunk,
    sectionMap: [ScriptContextMapEntry],
    file: RIFXFile
  ) throws -> ScriptChunk? {
    guard member.scriptId > 0, member.scriptId <= sectionMap.count else { return nil }
    let sectionId = Int(sectionMap[member.scriptId - 1].sectionId)
    guard sectionId >= 0, sectionId < file.chunkMap.count, file.chunkMap[sectionId].fourCC == "Lscr"
    else { return nil }
    return try file.script(at: file.chunkMap[sectionId])
  }
}
