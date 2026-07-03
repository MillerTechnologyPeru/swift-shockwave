import CSDL3
import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer

/// Composites the current frame's sprites into an SDL renderer: score
/// channel records first (already delta-decoded per frame), overridden by
/// any puppeted `Sprite` property bags the running Lingo has set.
@MainActor
final class StageRenderer {
  private let file: RIFXFile
  private let movie: Movie
  private let renderer: OpaquePointer
  /// Textures keyed by (fileCastLib << 16 | member) and transparency mode.
  private var textures: [Int: UnsafeMutablePointer<SDL_Texture>?] = [:]
  /// BITD chunk ids keyed by owning CASt chunk id.
  private var bitmapDataIds: [Int: Int] = [:]

  init(file: RIFXFile, movie: Movie, renderer: OpaquePointer) throws {
    self.file = file
    self.movie = movie
    self.renderer = renderer
    if let keyTable = try file.keyTable() {
      for entry in keyTable.entries
      where entry.fourCC == "BITD" && entry.childChunkIndex < file.chunkMap.count {
        bitmapDataIds[entry.ownerChunkIndex] = entry.childChunkIndex
      }
    }
  }

  func renderFrame(_ frameNumber: Int, player: MoviePlayer) {
    guard let score = movie.score, frameNumber >= 1, frameNumber <= score.chunk.frames.count
    else { return }
    let frame = score.chunk.frames[frameNumber - 1]
    for channel in frame.channels.keys.sorted() where channel >= 6 {
      guard let record = frame.spriteRecord(channel: channel) else { continue }
      drawSprite(record, spriteNumber: channel - 5, player: player)
    }
  }

  private func drawSprite(_ record: SpriteChannelRecord, spriteNumber: Int, player: MoviePlayer) {
    var castLib = record.castLib
    var memberNumber = record.member
    var destination = SDL_FRect(
      x: Float(record.left), y: Float(record.top),
      w: Float(record.width), h: Float(record.height))

    // Puppeted overrides: Lingo-set member/loc on the sprite channel win
    // over the score's record.
    if let sprite = player.sprite(.integer(spriteNumber)) {
      if case .object(let memberObject) = sprite.getProperty("member"),
        let castMember = memberObject as? CastMember,
        let library = movie.castManager.library(number: castMember.libraryNumber),
        let fileNumber = library.fileNumber
      {
        castLib = fileNumber
        memberNumber = castMember.memberNumber
      }
      if let locH = sprite.getProperty("locH").asInteger(),
        let locV = sprite.getProperty("locV").asInteger()
      {
        destination.x = Float(locH)
        destination.y = Float(locV)
      }
    }

    guard let member = movie.castManager.library(fileNumber: castLib)?.member(memberNumber),
      let properties = member.chunk.bitmapProperties
    else { return }
    let transparent = record.ink != 0
    guard
      let texture = texture(
        for: member, properties: properties, transparent: transparent,
        backColorIndex: record.backColor)
    else { return }
    SDL_RenderTexture(renderer, texture, nil, &destination)
  }

  private func texture(
    for member: CastMember, properties: BitmapMemberProperties, transparent: Bool,
    backColorIndex: Int
  ) -> UnsafeMutablePointer<SDL_Texture>? {
    let key =
      (member.libraryNumber << 24) | (member.memberNumber << 9) | (backColorIndex & 0xFF) << 1
      | (transparent ? 1 : 0)
    if let cached = textures[key] { return cached }

    var result: UnsafeMutablePointer<SDL_Texture>?
    defer { textures[key] = result }

    guard let castId = castChunkId(of: member),
      let bitdId = bitmapDataIds[castId],
      let data = try? file.chunkData(at: file.chunkMap[bitdId]),
      let pixels = BitmapData.decode(data, expectedByteCount: properties.decodedByteCount),
      let rgba = BitmapConversion.rgba(
        pixels: pixels, properties: properties,
        palette: BuiltinPalette.colors(forMember: properties.paletteMember),
        transparent: transparent, backColorIndex: backColorIndex)
    else { return nil }

    let width = Int32(properties.bounds.width)
    let height = Int32(properties.bounds.height)
    guard
      let texture = SDL_CreateTexture(
        renderer, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STATIC, width, height)
    else { return nil }
    rgba.withUnsafeBytes { buffer in
      _ = SDL_UpdateTexture(texture, nil, buffer.baseAddress, width * 4)
    }
    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)
    // Point-scale, not bilinear: this is pixel art, and several sprites are
    // placed at many times their native size (e.g. a 12×15 icon stretched
    // to 136×30), where linear filtering smears into color noise.
    SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST)
    result = texture
    return texture
  }

  /// Finds the member's `CASt` chunk id by re-walking its library's `CAS*`
  /// table (member number − minMember = slot).
  private var castIdCache: [Int: Int] = [:]
  private func castChunkId(of member: CastMember) -> Int? {
    let cacheKey = (member.libraryNumber << 16) | member.memberNumber
    if let cached = castIdCache[cacheKey] { return cached }
    guard let library = movie.castManager.library(number: member.libraryNumber),
      let fileNumber = library.fileNumber,
      let keyTable = try? file.keyTable(),
      let tableEntry = keyTable.entries.first(where: {
        $0.fourCC == "CAS*" && $0.ownerChunkIndex == (fileNumber << 16 | 1024)
      }),
      let table = try? file.castTable(at: file.chunkMap[tableEntry.childChunkIndex])
    else { return nil }
    let minMember = library.members.keys.min() ?? 1
    let slot = member.memberNumber - minMember
    guard slot >= 0, slot < table.memberIds.count else { return nil }
    let id = table.memberIds[slot]
    castIdCache[cacheKey] = id
    return id
  }
}
