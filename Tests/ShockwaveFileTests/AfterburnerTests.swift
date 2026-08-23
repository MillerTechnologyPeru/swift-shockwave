import Foundation
import ShockwaveFile
import ShockwaveTestSupport
import Testing

/// The sample ships both as a `.dir` and as the Afterburner-compressed
/// `.dcr` Shockwave actually serves — the same movie, so the compressed one
/// has to read back to the same chunks at the same resource ids, which is
/// what everything above the file layer addresses them by.
@Test func afterburnerMoviesReadBackAsTheirPlainSelves() throws {
  let plain = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let burned = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotShockwaveURL))

  #expect(burned.header.formatCode == "FGDM")
  #expect(burned.header.isAfterburner)
  #expect(!plain.header.isAfterburner)

  func inventory(_ file: RIFXFile) -> [Int: ShockwaveFile.FourCharCode] {
    var result: [Int: ShockwaveFile.FourCharCode] = [:]
    for (id, entry) in file.chunkMap.enumerated()
    where entry.length > 0 && entry.fourCC != "free" && entry.fourCC != "junk" {
      result[id] = entry.fourCC
    }
    return result
  }
  let plainChunks = inventory(plain)
  let burnedChunks = inventory(burned)
  // A burned movie drops the container's own bookkeeping (`RIFX`, `imap`,
  // `mmap`) and the free space an editable file carries; everything else
  // is there, at the same id.
  let shared = Set(plainChunks.keys).intersection(burnedChunks.keys)
  #expect(shared.count > 2800)
  #expect(Set(burnedChunks.keys).subtracting(plainChunks.keys).isEmpty)
  for id in shared {
    #expect(plainChunks[id] == burnedChunks[id], "chunk \(id) type")
  }

  // Bitmaps and code come back byte for byte. Two kinds don't, by
  // design: cast member chunks lose the authoring-only half of their info
  // (a script's source text, thumbnails), and sounds are re-encoded as
  // Shockwave Audio.
  var compared = 0
  for id in shared.sorted() where plainChunks[id] != "CASt" && plainChunks[id] != "snd " {
    let plainData = try plain.chunkData(at: plain.chunkMap[id])
    let burnedData = try burned.chunkData(at: burned.chunkMap[id])
    #expect(plainData == burnedData, "chunk \(id) (\(plainChunks[id]!)) contents")
    compared += 1
  }
  #expect(compared > 1400)

  // The sounds are all there, just smaller than the samples they replaced.
  let sounds = shared.filter { plainChunks[$0] == "snd " }
  #expect(sounds.count == 39)
  for id in sounds {
    let burnedData = try burned.chunkData(at: burned.chunkMap[id])
    let plainData = try plain.chunkData(at: plain.chunkMap[id])
    #expect(!burnedData.isEmpty)
    #expect(burnedData.count < plainData.count)
  }
}
