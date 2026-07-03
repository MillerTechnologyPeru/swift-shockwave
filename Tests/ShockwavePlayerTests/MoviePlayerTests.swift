import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwaveTestSupport
import Testing

@testable import ShockwavePlayer

private func realPlayer() throws -> MoviePlayer {
  let file = try RIFXFile.read(from: Data(contentsOf: TestResources.junkbotMovieURL))
  let movie = try Movie.load(from: file)
  return MoviePlayer(movie: movie)
}

@Test func putBuiltinCapturesOutput() throws {
  let player = try realPlayer()
  // "on enterFrame / put "My name is Junkbot"" in the main movie script:
  // real bytecode from the real file, run end to end through LingoVM.
  player.callHandler("enterFrame")
  #expect(player.transcript == ["My name is Junkbot"])

  player.callHandler("exitFrame")
  #expect(player.transcript == ["My name is Junkbot", "I love to eat trash"])

  player.callHandler("prepareFrame")
  #expect(player.transcript.last == "Junk is food!")
}

@Test func stringConcatenationHandlerRuns() throws {
  let player = try realPlayer()
  // on showGlobals: put "version = " & QUOTE & "8.0"
  player.callHandler("showGlobals")
  #expect(player.transcript == ["version = \"8.0"])
}

@Test func memberLookupByNameAndNumber() throws {
  let player = try realPlayer()
  let byName = try #require(player.member(.string("frameloop"), castLib: nil) as? CastMember)
  #expect(byName.name == "frameloop")

  let byNumber = try #require(player.member(.integer(4), castLib: .integer(2)) as? CastMember)
  #expect(byNumber.name == "frameloop")

  let byLibName = try #require(
    player.member(.string("main"), castLib: .string("legoparts")) as? CastMember)
  #expect(byLibName.scriptType == .movie)
}

@Test func makeObjectInstantiatesParentScript() throws {
  let player = try realPlayer()
  let object = try #require(player.makeObject(scriptName: "config manager", args: []))
  let instance = try #require(object as? ScriptInstance)
  #expect(instance.member.name == "config manager")
  #expect(instance.member.scriptType == .parent)
}

@Test func spriteChannelIsStableAcrossLookups() throws {
  let player = try realPlayer()
  let first = try #require(player.sprite(.integer(7)))
  first.setProperty("locH", value: .integer(123))
  let second = try #require(player.sprite(.integer(7)))
  #expect(second.getProperty("locH").asInteger() == 123)
  #expect(second.getProperty("spriteNum").asInteger() == 7)
}

@Test func markerAndGoBuiltinsUseScoreLabels() throws {
  let player = try realPlayer()
  let frame = player.callHandler("marker", args: [.string("mainmenu")])
  #expect(frame.asInteger() == 9)

  player.callHandler("go", args: [.string("play")])
  #expect(player.movieModel.getProperty("frame").asInteger() == 14)
}

@Test func prepareMovieRunsAgainstRealModel() throws {
  let player = try realPlayer()
  player.callHandler("prepareMovie")

  // Observable side effects of the real prepareMovie bytecode:
  //   set the exitLock to 1
  #expect(player.movieModel.getProperty("exitLock").asInteger() == 1)
  //   the itemDelimiter = ","
  #expect(player.movieModel.getProperty("itemDelimiter").asString() == ",")
  //   the actorList = []
  guard case .listType(let actorList) = player.movieModel.getProperty("actorList") else {
    Issue.record("actorList should be a list")
    return
  }
  #expect(actorList.elements.isEmpty)

  //   glob = [#EDITOR: [:], #catalog: [:], #PLAYER: [:]] with managers
  //   installed by new(script(...)) — makeObject instantiating real parent
  //   scripts.
  let glob = player.movieModel.lingoEnvironment.getGlobal("glob")
  guard case .propertyListType = glob else {
    Issue.record("glob should be a property list, got \(glob)")
    return
  }
  let configManager = glob[.symbol("config_manager")]
  guard case .object(let manager) = configManager else {
    Issue.record("glob[#config_manager] should be an object, got \(configManager)")
    return
  }
  #expect((manager as? ScriptInstance)?.member.name == "config manager")

  //   put "0" into field "editor par field"
  let field = try #require(player.member(.string("editor par field"), castLib: nil))
  #expect(field.getProperty("text").asString() == "0")
}
