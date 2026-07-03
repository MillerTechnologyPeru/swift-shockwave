import ArgumentParser
import CSDL3
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

  @MainActor
  func run() async throws {
    let file = try RIFXFile.read(from: Data(contentsOf: URL(fileURLWithPath: moviePath)))
    let movie = try Movie.load(from: file)
    let config = try file.movieConfig()
    let stage = config?.stageRect ?? DirectorRect(top: 0, left: 0, bottom: 480, right: 640)
    let player = MoviePlayer(movie: movie)

    guard SDL_Init(SDL_INIT_VIDEO) else {
      throw SDLError(description: "SDL_Init failed: \(String(cString: SDL_GetError()))")
    }
    defer { SDL_Quit() }

    let title = URL(fileURLWithPath: moviePath).lastPathComponent
    guard
      let window = SDL_CreateWindow(title, Int32(stage.width), Int32(stage.height), 0),
      let renderer = SDL_CreateRenderer(window, nil)
    else {
      throw SDLError(description: "SDL window/renderer failed: \(String(cString: SDL_GetError()))")
    }
    defer {
      SDL_DestroyRenderer(renderer)
      SDL_DestroyWindow(window)
    }

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

    var running = true
    var event = SDL_Event()
    while running {
      while SDL_PollEvent(&event) {
        switch event.type {
        case SDL_EVENT_QUIT.rawValue:
          running = false
        case SDL_EVENT_KEY_DOWN.rawValue:
          if event.key.key == SDLK_ESCAPE {
            running = false
          } else {
            player.dispatch("keyDown")
          }
        case SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue:
          let hit = player.spriteAt(x: Int(event.button.x), y: Int(event.button.y))
          player.dispatch("mouseDown", toSprite: hit)
        case SDL_EVENT_MOUSE_BUTTON_UP.rawValue:
          let hit = player.spriteAt(x: Int(event.button.x), y: Int(event.button.y))
          player.dispatch("mouseUp", toSprite: hit)
        default:
          break
        }
      }

      if player.isPlaying {
        player.step()
        flushTranscript()
      }

      SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
      SDL_RenderClear(renderer)
      stageRenderer.renderFrame(player.currentFrame, player: player)
      SDL_RenderPresent(renderer)
      SDL_Delay(UInt32(player.frameDelayMs.rounded()))
    }

    player.stop()
    flushTranscript()
  }
}
