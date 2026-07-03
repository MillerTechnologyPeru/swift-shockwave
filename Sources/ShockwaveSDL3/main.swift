import CSDL3
import Foundation
import LingoRuntime
import ShockwaveFile
import ShockwaveModel
import ShockwavePlayer

guard CommandLine.arguments.count > 1 else {
  print("usage: ShockwaveSDL3 <movie.dir> [frame-label | frame-number]")
  exit(64)
}

let moviePath = CommandLine.arguments[1]
let file = try RIFXFile.read(from: Data(contentsOf: URL(fileURLWithPath: moviePath)))
let movie = try Movie.load(from: file)
let config = try file.movieConfig()
let stage = config?.stageRect ?? DirectorRect(top: 0, left: 0, bottom: 480, right: 640)
let player = MoviePlayer(movie: movie)

guard SDL_Init(SDL_INIT_VIDEO) else {
  fatalError("SDL_Init failed: \(String(cString: SDL_GetError()))")
}
defer { SDL_Quit() }

let title = URL(fileURLWithPath: moviePath).lastPathComponent
guard
  let window = SDL_CreateWindow(title, Int32(stage.width), Int32(stage.height), 0),
  let renderer = SDL_CreateRenderer(window, nil)
else {
  fatalError("SDL window/renderer failed: \(String(cString: SDL_GetError()))")
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
if CommandLine.arguments.count > 2 {
  let target = CommandLine.arguments[2]
  if let frame = Int(target) {
    player.jump(to: frame)
  } else if let frame = movie.score?.frame(labeled: target) {
    player.jump(to: frame)
  } else {
    print("unknown frame label: \(target)")
  }
}

var transcriptIndex = 0

@MainActor
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
    case SDL_EVENT_MOUSE_BUTTON_UP.rawValue:
      // No sprite hit-testing yet (needs score sprite geometry); events
      // bubble straight to the frame script and movie handlers.
      player.dispatch("mouseUp")
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
  SDL_Delay(66)  // ~15fps until the config tempo field is decoded
}

player.stop()
flushTranscript()
