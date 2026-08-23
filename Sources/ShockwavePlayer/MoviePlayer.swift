import LingoBytecode
import LingoRuntime
import LingoVM
import ShockwaveFile
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
  /// Script names `new(script(...))` failed to resolve, so each is reported
  /// only the first time.
  private var unresolvedScripts: Set<String> = []

  /// The frame the playhead is on; 0 before `start()`.
  public internal(set) var currentFrame = 0
  /// Where `go(...)` told the playhead to continue after the current frame
  /// finishes; `nil` means fall through to the next frame.
  public internal(set) var nextFrame: Int?
  public internal(set) var isPlaying = false

  private var sprites: [Int: Sprite] = [:]
  /// The sprite the pointer was last found over, for `mouseEnter`/
  /// `mouseLeave`/`mouseWithin`; `nil` when over the bare stage.
  var hoveredSprite: Int?
  /// Per-pixel coverage of bitmap members under a given ink and key
  /// color, for hit-testing; an empty array records a member that
  /// couldn't be decoded so it isn't retried.
  var hitMasks: [HitMaskKey: [Bool]] = [:]
  /// How many frames each film loop sprite has played, by sprite number —
  /// the loop's frame to show is this modulo its length. Advanced once
  /// per movie frame; a loop plays continuously while its sprite is up.
  var filmLoopFrames: [Int: Int] = [:]
  /// Director's sound channels, created as Lingo asks for them.
  var soundChannels: [Int: SoundChannel] = [:]
  /// The audio backend; `nil` plays nothing (headless runs, tests).
  public var audioSink: AudioSink?
  /// Decodes a compressed (Shockwave Audio, MP3) sound member's bitstream
  /// to PCM. Supplied by the platform layer; without it those members are
  /// silent. Results are cached on the member.
  public var compressedSoundDecoder: ((ShockwaveAudioMedia) -> SoundResource?)?

  /// A sound member's samples, decoding compressed members on first use.
  func decodedSound(of member: CastMember) -> SoundResource? {
    if let sound = member.sound { return sound }
    guard let media = member.shockwaveAudio, let decoder = compressedSoundDecoder else { return nil }
    let sound = decoder(media)
    member.setDecodedSound(sound)
    return sound
  }
  /// Measures how tall a text member's content is at a given width, so an
  /// auto-sizing text sprite (`boxType #adjust`) can grow past the height
  /// the score recorded for it — the memo on the levels screen was
  /// authored empty at 14px and filled in at runtime. Installed by the
  /// rendering layer, which owns the text engine; without it text sprites
  /// keep their score size.
  public var textHeightMeasurer: ((CastMember, Int) -> Int)?
  /// Where a text member paints when drawn at a given size — one flag per
  /// pixel, row-major — so pointer events fall through the unpainted part
  /// of a background-transparent text sprite the way they do through a
  /// keyed bitmap. The level list relies on it: its title column sits over
  /// the shape whose behavior takes the click. Installed by the rendering
  /// layer; without it text sprites take hits over their whole rect.
  public var textCoverage: ((CastMember, Int, Int) -> [Bool]?)?
  /// Cached `textCoverage` answers, keyed by member and the text, layout
  /// and size they were computed for.
  var textMasks: [Int: (text: String, layout: CastMember.TextLayout, size: (Int, Int), mask: [Bool])] = [:]
  /// Live behavior instances for the spans covering `currentFrame`, keyed
  /// by span index in `score.spans`.
  var activeSpans: [Int: [ScriptInstance]] = [:]
  var movieHandlerNames: Set<String> = []
  /// Last id handed out by a network-verb stub (see
  /// `registerNetworkingBuiltins`).
  var lastNetID = 0

  public init(movie: Movie) {
    self.movieModel = movie
    registerBuiltins()
    registerNetworkingBuiltins()
    registerMovieHandlers()
  }

  /// The version `LingoVM.call` branches on, mapped from the config chunk's
  /// file-format code (Director 5 and later use dot-syntax-era bytecode
  /// shapes; the VM only distinguishes pre/post 500).
  public var lingoVersion: UInt16 {
    movieModel.fileVersion >= 0x4C7 ? 700 : 400
  }

  /// The FPS in effect for `currentFrame`: the tempo channel's authored
  /// value if the current frame set one, else the movie's own frame rate,
  /// else Director's default of 30. Puppeting the tempo directly (as
  /// opposed to authoring it on the score) isn't modeled here yet.
  public var effectiveTempo: Int {
    movieModel.score?.frameTempo(at: currentFrame)
      ?? (movieModel.frameRate > 0 ? movieModel.frameRate : 30)
  }

  /// Milliseconds the host should wait before advancing to the next frame,
  /// derived from `effectiveTempo`.
  public var frameDelayMs: Double {
    1000.0 / Double(max(effectiveTempo, 1))
  }

  // MARK: - LingoVMHost

  public var movie: LingoObject { movieModel }

  public func sprite(_ channel: LingoValue) -> LingoObject? {
    guard let number = channel.asInteger() else { return nil }
    if let sprite = sprites[number] { return sprite }
    let sprite = Sprite(
      spriteNumber: number, player: self, environment: movieModel.lingoEnvironment)
    sprites[number] = sprite
    return sprite
  }

  /// The sprite object for a channel if Lingo has ever asked for it —
  /// unlike `sprite(_:)`, this never creates one, so it can be used to ask
  /// "has anything been puppeted here?" without answering yes by asking.
  func existingSprite(_ number: Int) -> Sprite? {
    sprites[number]
  }

  /// Every sprite number the running Lingo has puppeted a member onto and
  /// hasn't hidden. The sample's playfield cycles its whole 800-sprite
  /// pool as pieces are erased and re-placed each frame, so most of the
  /// pool ends up touched but parked out of sight; leaving those out here
  /// keeps the draw order to what actually shows.
  func puppetedSpriteNumbers() -> [Int] {
    sprites.compactMap { number, sprite in
      guard case .object(let object)? = sprite.puppeted("member"), object is CastMember else {
        return nil
      }
      if let visible = sprite.puppeted("visible") {
        if case .void = visible {} else if !visible.asBool() { return nil }
      }
      return number
    }
  }

  public func castLibrary(_ id: LingoValue) -> LingoObject? {
    resolveLibrary(id)
  }

  /// `sound(n)` — one of the eight sound channels.
  public func sound(_ id: LingoValue) -> LingoObject? {
    soundChannel(id.asInteger() ?? 1)
  }

  func soundChannel(_ number: Int) -> SoundChannel {
    if let channel = soundChannels[number] { return channel }
    let channel = SoundChannel(number: number, player: self)
    soundChannels[number] = channel
    return channel
  }

  public func member(_ id: LingoValue, castLib: LingoValue?) -> LingoObject? {
    let library = castLib.flatMap(resolveLibrary)
    switch id {
    case .integer(let number):
      if let library { return library.member(number) }
      return movieModel.castManager.member(number: number)
    case .string(let name), .symbol(let name):
      if let library {
        return library.members.values.first {
          $0.name?.caseInsensitiveEquals(name) ?? false
        }
      }
      return movieModel.castManager.member(named: name)
    default:
      return nil
    }
  }

  public func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject? {
    guard let member = scriptMember(named: scriptName) else {
      reportUnresolvedScript(scriptName)
      return nil
    }
    return instantiate(member, args: args)
  }

  /// Notes a handler the VM abandoned mid-way. Director would put up an
  /// alert; here the message lands in `transcript`, where a headless run
  /// can read it, so a handler that dies quietly doesn't masquerade as a
  /// rendering bug.
  func reportScriptError(_ message: String) {
    transcript.append("script error: \(message)")
  }

  /// Notes a script name that failed to resolve, once per name.
  func reportUnresolvedScript(_ name: String) {
    guard unresolvedScripts.insert(name).inserted else { return }
    transcript.append("no script cast member named \"\(name)\"")
  }

  private func instantiate(_ member: CastMember, args: [LingoValue]) -> ScriptInstance {
    let instance = ScriptInstance(member: member, player: self)
    if instance.handler(named: "new") != nil {
      _ = instance.callMethod("new", args: args)
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
    movieModel.castManager.scriptMember(named: name)
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
            do {
              return try LingoVM.call(
                handler: handler, chunk: chunk, names: member.scriptNames, args: args,
                receiver: nil, host: self, environment: self.movieModel.lingoEnvironment,
                version: self.lingoVersion, capitalX: member.scriptUsesCapitalContext)
            } catch {
              self.reportScriptError("\(handlerName): \(error)")
              return .void
            }
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
    // `sprite(n)` and `member(...)` as expressions, which scripts hold onto
    // and address later (`s = sprite(15)` … `s.visible = 0`). The VM reaches
    // the host directly for the `the locV of sprite n` spelling, but the
    // call spelling is an ordinary function and needs registering, or it
    // yields VOID and every later use of the reference quietly does nothing.
    environment.registerGlobalFunction("sprite") { [weak self] args in
      guard let self, let channel = args.first, let sprite = self.sprite(channel) else {
        return .void
      }
      return .object(sprite)
    }
    environment.registerGlobalFunction("member") { [weak self] args in
      guard let self, let id = args.first,
        let member = self.member(id, castLib: args[safe: 1])
      else { return .void }
      return .object(member)
    }
    environment.registerGlobalFunction("startTimer") { [weak self] _ in
      self?.movieModel.startTimer()
      return .void
    }
    environment.registerGlobalFunction("sound") { [weak self] args in
      guard let self, let id = args.first else { return .void }
      return .object(self.soundChannel(id.asInteger() ?? 1))
    }
    // `random(n)` — 1…n. Registered here rather than in the runtime so a
    // movie's own `random` handler could still win by name.
    environment.registerGlobalFunction("random") { args in
      guard let upper = args.first?.asInteger(), upper >= 1 else { return .integer(1) }
      return .integer(Int.random(in: 1...upper))
    }
    // `new(script("name"))` compiles to two chained ExtCalls, not NewObj:
    // `script` resolves the member, `new` instantiates it.
    environment.registerGlobalFunction("script") { [weak self] args in
      guard let self, let id = args.first else { return .void }
      if let member = self.member(id, castLib: args[safe: 1]) {
        return .object(member)
      }
      // An unresolved `script("name")` yields VOID rather than raising, so
      // `new(script("name"))` quietly produces VOID too and every later
      // call on it does nothing. That can disable an entire subsystem
      // invisibly, so report each missing name once.
      if case .string(let name) = id { self.reportUnresolvedScript(name) }
      if case .symbol(let name) = id { self.reportUnresolvedScript(name) }
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
        self.go(to: frame)
      case .string(let name), .symbol(let name):
        if let frame = self.movieModel.score?.frame(labeled: name) {
          self.go(to: frame)
        }
      default:
        break
      }
      return .void
    }
    // `puppetSound(channel, member)`, `puppetSound(member)` (channel 1),
    // `puppetSound(channel, 0)` / `puppetSound(0)` to stop.
    environment.registerGlobalFunction("puppetSound") { [weak self] args in
      guard let self else { return .void }
      let channelNumber: Int
      let target: LingoValue
      if args.count >= 2 {
        channelNumber = args[0].asInteger() ?? 1
        target = args[1]
      } else {
        channelNumber = 1
        target = args.first ?? .void
      }
      let channel = self.soundChannel(channelNumber)
      if target.asInteger() == 0 {
        channel.stop()
      } else if let member = self.member(target, castLib: nil) as? CastMember {
        channel.play(member: member)
      }
      return .void
    }
    environment.registerGlobalFunction("soundBusy") { [weak self] args in
      guard let self, let number = args.first?.asInteger() else { return .integer(0) }
      return .integer(self.soundChannel(number).isBusy ? 1 : 0)
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
          _ = instance.callMethod(name, args: Array(args.dropFirst()))
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

/// Identifies one bitmap member's coverage under one ink/key combination.
struct HitMaskKey: Hashable {
  var library: Int
  var member: Int
  var ink: SpriteInk
  var backColor: Int
}
