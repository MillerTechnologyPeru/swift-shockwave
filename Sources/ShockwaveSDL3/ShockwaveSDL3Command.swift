import ArgumentParser
import CSDL3
import SDL3Swift
import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer

struct SDLError: Error, CustomStringConvertible {
  var description: String
}

@main
struct ShockwaveSDL3Command: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "ShockwaveSDL3",
    abstract: "Runs a Director movie's Lingo scripts and score in an SDL3-rendered stage window."
  )

  @Argument(help: "Path to a Director movie file (.dir/.cst/.dxr).")
  var moviePath: String

  @Argument(help: "Frame label or number to jump to at startup, e.g. \"mainmenu\".")
  var startFrame: String?

  @Option(
    help: "Run headless (hidden window), save a BMP of the stage to this path after stepping, then exit.")
  var screenshot: String?

  @Option(help: "How many frames to step before capturing --screenshot.")
  var screenshotDelay: Int = 30

  @Option(
    help:
      "Headless only: click the stage at X,Y (movie coordinates) after --screenshot-delay frames, then step as many frames again before capturing. Repeatable."
  )
  var click: [String] = []

  @MainActor
  func run() async throws {
    let file = try RIFXFile.read(from: Data(contentsOf: URL(fileURLWithPath: moviePath)))
    let movie = try Movie.load(from: file)
    let config = try file.movieConfig()
    let stage = config?.stageRect ?? DirectorRect(top: 0, left: 0, bottom: 480, right: 640)
    let player = MoviePlayer(movie: movie)

    try SDL.initialize(subSystems: [.video])
    defer { SDL.quit() }

    let title = URL(fileURLWithPath: moviePath).lastPathComponent
    let windowOptions: BitMaskOptionSet<SDLWindow.Option> = screenshot != nil ? [.hidden] : []
    let window = try SDLWindow(
      title: title, 
      frame: (x: .centered, y: .centered, width: stage.width, height: stage.height),
      options: windowOptions
    )
    let renderer = try SDLRenderer(window: window)

    let stageRenderer = try StageRenderer(file: file, movie: movie, renderer: renderer)

    player.start()

    // Optional starting point: a frame label or number (junkbot idles on
    // frame 1 until its network-streaming flow calls go, so jumping to
    // "mainmenu" etc. is the way to see content).
    if let startFrame {
      if let frame = Int(startFrame) {
        player.jump(to: frame)
      } else if let frame = movie.score?.frame(labeled: startFrame) {
        player.jump(to: frame)
      } else {
        print("unknown frame label: \(startFrame)")
      }
    }

    var transcriptIndex = 0
    func flushTranscript() {
      while transcriptIndex < player.transcript.count {
        print("-- \(player.transcript[transcriptIndex])")
        transcriptIndex += 1
      }
    }
    flushTranscript()

    if let screenshotPath = screenshot {
      // Paced at the movie's own tempo rather than run flat out: scripts
      // gate on `the ticks`, so a loop with no elapsed time between frames
      // never satisfies them.
      func stepAWhile() {
        for _ in 0..<screenshotDelay where player.isPlaying {
          player.step()
          SDL_Delay(UInt32(player.frameDelayMs.rounded()))
        }
      }
      stepAWhile()
      for spec in click {
        let parts = spec.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else {
          print("bad --click \(spec); expected X,Y")
          continue
        }
        let hit = player.spriteAt(x: parts[0], y: parts[1])
        player.pressMouse(x: parts[0], y: parts[1])
        player.releaseMouse(x: parts[0], y: parts[1])
        print("clicked \(parts[0]),\(parts[1]) -> sprite \(hit.map(String.init) ?? "none")")
        stepAWhile()
      }
      flushTranscript()
      try renderer.setDrawColor(red: 255, green: 255, blue: 255, alpha: 255)
      try renderer.clear()
      stageRenderer.renderFrame(player.currentFrame, player: player)
      guard let surface = SDL_RenderReadPixels(renderer.unsafePointer, nil) else {
        throw SDLError(description: "SDL_RenderReadPixels failed: \(String(cString: SDL_GetError()))")
      }
      defer { SDL_DestroySurface(surface) }
      guard SDL_SaveBMP(surface, screenshotPath) else {
        throw SDLError(description: "SDL_SaveBMP failed: \(String(cString: SDL_GetError()))")
      }
      print("saved frame \(player.currentFrame) to \(screenshotPath)")
      player.stop()
      return
    }

    var running = true
    while running {
      while let event = SDL.pollEvent() {
        switch event {
        case .quit:
          running = false
        case .keyDown(_, let keycode):
          if keycode.rawValue == UInt32(SDLK_ESCAPE) {
            running = false
          } else {
            player.dispatch("keyDown")
          }
        case .mouseMotion(_, let x, let y, _):
          player.moveMouse(x: Int(x), y: Int(y))
        case .mouseButtonDown(_, let x, let y, _):
          player.pressMouse(x: Int(x), y: Int(y))
        case .mouseButtonUp(_, let x, let y, _):
          player.releaseMouse(x: Int(x), y: Int(y))
        default:
          break
        }
      }

      if player.isPlaying {
        player.step()
        flushTranscript()
      }

      try renderer.setDrawColor(red: 255, green: 255, blue: 255, alpha: 255)
      try renderer.clear()
      stageRenderer.renderFrame(player.currentFrame, player: player)
      renderer.present()
      SDL_Delay(UInt32(player.frameDelayMs.rounded()))
    }

    player.stop()
    flushTranscript()
  }
}
