import LingoRuntime
import ShockwaveModel

/// The mouse as Lingo sees it.
///
/// Two things feed off it. Discrete events — `mouseDown`/`mouseUp` on the
/// sprite under the pointer, `mouseEnter`/`mouseLeave` as it crosses sprite
/// edges, `mouseWithin` every frame it stays inside — and polled state:
/// `the mouseLoc`, `the mouseH`/`mouseV`, `the mouseDown`, `the stillDown`,
/// `the clickLoc`. The sample's play manager is built on polling: its
/// `stepFrame` reads `the mouseDown` and `the mouseLoc` every frame to run
/// the press → drag → drop of a brick, and its "part click behavior" tells
/// it which brick the pointer entered.
extension MoviePlayer {
  /// Pointer motion to `(x, y)` in stage coordinates.
  public func moveMouse(x: Int, y: Int) {
    movieModel.setProperty("mouseH", value: .integer(x))
    movieModel.setProperty("mouseV", value: .integer(y))
    movieModel.setProperty("mouseLoc", value: .list([.integer(x), .integer(y)]))
    updateHover()
  }

  /// The button going down at `(x, y)`.
  public func pressMouse(x: Int, y: Int) {
    moveMouse(x: x, y: y)
    movieModel.setProperty("mouseDown", value: .integer(1))
    movieModel.setProperty("stillDown", value: .integer(1))
    movieModel.setProperty("clickLoc", value: .list([.integer(x), .integer(y)]))
    let hit = spriteAt(x: x, y: y)
    movieModel.setProperty("clickOn", value: .integer(hit ?? 0))
    dispatch("mouseDown", toSprite: hit)
  }

  /// The button coming up at `(x, y)`.
  public func releaseMouse(x: Int, y: Int) {
    moveMouse(x: x, y: y)
    movieModel.setProperty("mouseDown", value: .integer(0))
    movieModel.setProperty("stillDown", value: .integer(0))
    dispatch("mouseUp", toSprite: spriteAt(x: x, y: y))
  }

  /// Re-evaluates which sprite is under the pointer — sprites move under a
  /// still pointer too — sending `mouseLeave`/`mouseEnter` on a change.
  /// Called on motion and once per frame.
  func updateHover() {
    guard let x = movieModel.getProperty("mouseH").asInteger(),
      let y = movieModel.getProperty("mouseV").asInteger()
    else { return }
    let now = spriteAt(x: x, y: y)
    guard now != hoveredSprite else { return }
    if let previous = hoveredSprite {
      dispatch("mouseLeave", toSprite: previous, bubbles: false)
    }
    hoveredSprite = now
    if let now {
      dispatch("mouseEnter", toSprite: now, bubbles: false)
    }
  }

  /// `mouseWithin` for the sprite the pointer is resting on — Director
  /// sends it every frame the pointer stays inside.
  func dispatchMouseWithin() {
    updateHover()
    if let hovered = hoveredSprite {
      dispatch("mouseWithin", toSprite: hovered, bubbles: false)
    }
  }
}
