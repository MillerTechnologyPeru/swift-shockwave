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

    let firstMemberNumber = entry.minMember ?? 1
    var members: [Int: CastMember] = [:]
    for (offset, memberId) in castTable.memberIds.enumerated() where memberId != 0 {
      let memberNumber = firstMemberNumber + offset
      let chunk = try file.castMember(at: file.chunkMap[memberId])
      let scriptChunk = try loadScriptChunk(for: chunk, sectionMap: sectionMap, file: file)
      members[memberNumber] = CastMember(
        libraryNumber: libraryNumber, memberNumber: memberNumber, chunk: chunk,
        scriptChunk: scriptChunk, scriptNames: scriptNames,
        scriptUsesCapitalContext: capitalContext, environment: environment)
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
