import LingoBytecode
import LingoRuntime
import LingoVM
import ShockwaveModel

/// The `LingoVMHost` conformance bridging a loaded `Movie` into `LingoVM`:
/// resolves members and sprites, instantiates parent scripts, registers
/// every movie-script handler as a global so cross-script calls work,
/// provides the player built-ins (`put`, `marker`, `go`, ...) headless
/// execution needs, and runs the frame loop (`start`/`step`/`jump`).
public final class MoviePlayer: LingoVMHost {
  public let movieModel: Movie
  /// Everything `put` writes, in order — the headless stand-in for the
  /// message window.
  public private(set) var transcript: [String] = []

  /// The frame the playhead is on; 0 before `start()`.
  public internal(set) var currentFrame = 0
  /// Where `go(...)` told the playhead to continue after the current frame
  /// finishes; `nil` means fall through to the next frame.
  public internal(set) var nextFrame: Int?
  public internal(set) var isPlaying = false

  private var sprites: [Int: Sprite] = [:]
  /// Live behavior instances for the spans covering `currentFrame`, keyed
  /// by span index in `score.spans`.
  var activeSpans: [Int: [ScriptInstance]] = [:]
  var movieHandlerNames: Set<String> = []

  public init(movie: Movie) {
    self.movieModel = movie
    registerBuiltins()
    registerMovieHandlers()
  }

  /// The version `LingoVM.call` branches on, mapped from the config chunk's
  /// file-format code (Director 5 and later use dot-syntax-era bytecode
  /// shapes; the VM only distinguishes pre/post 500).
  public var lingoVersion: UInt16 {
    movieModel.fileVersion >= 0x4C7 ? 700 : 400
  }

  // MARK: - LingoVMHost

  public var movie: LingoObject { movieModel }

  public func sprite(_ channel: LingoValue) -> LingoObject? {
    guard let number = channel.asInteger() else { return nil }
    if let sprite = sprites[number] { return sprite }
    let sprite = Sprite(spriteNumber: number, environment: movieModel.lingoEnvironment)
    sprites[number] = sprite
    return sprite
  }

  public func member(_ id: LingoValue, castLib: LingoValue?) -> LingoObject? {
    let library = castLib.flatMap(resolveLibrary)
    switch id {
    case .integer(let number):
      if let library { return library.member(number) }
      return movieModel.castManager.member(number: number)
    case .string(let name), .symbol(let name):
      let libraries = library.map { [$0] } ?? movieModel.castManager.libraries
      for library in libraries {
        if let member = library.members.values.first(where: {
          $0.name?.caseInsensitiveEquals(name) ?? false
        }) {
          return member
        }
      }
      return nil
    default:
      return nil
    }
  }

  public func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject? {
    guard let member = scriptMember(named: scriptName) else { return nil }
    return instantiate(member, args: args)
  }

  private func instantiate(_ member: CastMember, args: [LingoValue]) -> ScriptInstance {
    let instance = ScriptInstance(member: member, player: self)
    if instance.handler(named: "new") != nil {
      _ = instance.callMethod("new", args: [.object(instance)] + args)
    }
    return instance
  }

  // MARK: - Handler invocation

  /// Calls a movie-script handler by name (they're registered as globals,
  /// exactly how Lingo's own cross-script dispatch works).
  @discardableResult
  public func callHandler(_ name: String, args: [LingoValue] = []) -> LingoValue {
    movieModel.lingoEnvironment.callGlobal(name, args: args)
  }

  private func scriptMember(named name: String) -> CastMember? {
    var fallback: CastMember?
    for library in movieModel.castManager.libraries {
      for member in library.members.values where member.chunk.type == .script {
        guard member.name?.caseInsensitiveEquals(name) ?? false else { continue }
        if member.scriptType == .parent { return member }
        if fallback == nil { fallback = member }
      }
    }
    return fallback
  }

  private func registerMovieHandlers() {
    for library in movieModel.castManager.libraries {
      for member in library.members.values.sorted(by: { $0.memberNumber < $1.memberNumber })
      where member.scriptType == .movie {
        guard let chunk = member.scriptChunk else { continue }
        for handler in chunk.handlers {
          guard let handlerName = member.scriptNames[safe: Int(handler.nameId)] else { continue }
          movieHandlerNames.insert(handlerName.asciiLowercased())
          movieModel.lingoEnvironment.registerGlobalFunction(handlerName) {
            [weak self] args in
            guard let self else { return .void }
            let result = try? LingoVM.call(
              handler: handler, chunk: chunk, names: member.scriptNames, args: args,
              receiver: nil, host: self, environment: self.movieModel.lingoEnvironment,
              version: self.lingoVersion, capitalX: member.scriptUsesCapitalContext)
            return result ?? .void
          }
        }
      }
    }
  }

  private func registerBuiltins() {
    let environment = movieModel.lingoEnvironment
    environment.registerGlobalFunction("put") { [weak self] args in
      self?.transcript.append(args.map { $0.asString() }.joined(separator: " "))
      return .void
    }
    // `new(script("name"))` compiles to two chained ExtCalls, not NewObj:
    // `script` resolves the member, `new` instantiates it.
    environment.registerGlobalFunction("script") { [weak self] args in
      guard let self, let id = args.first else { return .void }
      if let member = self.member(id, castLib: args[safe: 1]) {
        return .object(member)
      }
      return .void
    }
    environment.registerGlobalFunction("new") { [weak self] args in
      guard let self, let target = args.first else { return .void }
      switch target {
      case .object(let object):
        guard let member = object as? CastMember, member.scriptChunk != nil else { return .void }
        return .object(self.instantiate(member, args: Array(args.dropFirst())))
      case .string(let name), .symbol(let name):
        guard let instance = self.makeObject(scriptName: name, args: Array(args.dropFirst()))
        else { return .void }
        return .object(instance)
      default:
        return .void
      }
    }
    environment.registerGlobalFunction("marker") { [weak self] args in
      guard let score = self?.movieModel.score, let target = args.first else { return .void }
      switch target {
      case .string(let name), .symbol(let name):
        if let frame = score.frame(labeled: name) { return .integer(frame) }
      default:
        break
      }
      return .void
    }
    environment.registerGlobalFunction("go") { [weak self] args in
      guard let self, let target = args.first else { return .void }
      switch target {
      case .integer(let frame):
        self.nextFrame = frame
      case .string(let name), .symbol(let name):
        if let frame = self.movieModel.score?.frame(labeled: name) {
          self.nextFrame = frame
        }
      default:
        break
      }
      return .void
    }
    environment.registerGlobalFunction("sendAllSprites") { [weak self] args in
      guard let self, let event = args.first else { return .void }
      let name: String
      switch event {
      case .symbol(let value), .string(let value): name = value
      default: return .void
      }
      for (_, instances) in self.activeSpans.sorted(by: { $0.key < $1.key }) {
        for instance in instances where instance.handler(named: name) != nil {
          _ = instance.callMethod(name, args: [.object(instance)] + Array(args.dropFirst()))
        }
      }
      return .void
    }
  }

  private func resolveLibrary(_ castLib: LingoValue) -> CastLibrary? {
    switch castLib {
    case .integer(let number):
      return movieModel.castManager.library(number: number)
    case .string(let name), .symbol(let name):
      return movieModel.castManager.library(named: name)
    default:
      return nil
    }
  }
}
