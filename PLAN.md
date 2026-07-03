# swift-shockwave: planning notes

## Context

`swift-shockwave` is an MIT-licensed Swift library for Adobe Director/Shockwave files. The goal is a **clean-room** implementation of a Director/Shockwave player: RIFX file parsing, the cast/score/movie data model, wiring that model up to run Lingo scripts, and (post-v1, amended from the original plan) a minimal SDL3-based renderer in the `ShockwaveSDL3` executable target. 3D, Xtras, and font rasterization remain out of scope.

**Hard constraint**: this must stay a clean-room reimplementation. Do not reference any GPL reference emulator's file paths, module names, or use "ported from"/"based on" language anywhere in code, comments, commit messages, or docs. Implement from an understanding of *behavior* (the RIFX container format, Director's chunk types, Lingo semantics — all independently documented/reverse-engineered knowledge), never by copying or transliterating GPL source. This mirrors a standing rule already followed in the sibling `swift-lingo` repo.

**Key strategic decision**: reuse [`swift-lingo`](https://github.com/MillerTechnologyPeru/swift-lingo)'s existing `LingoVM`/`LingoBytecode`/`LingoRuntime` as a package dependency for the bytecode-interpreter layer, rather than writing a second one. `swift-lingo` already has:
- A working, tested stack-machine VM: `LingoVM.call(handler:chunk:names:args:receiver:host:environment:version:capitalX:)`.
- A bytecode decompiler (`LingoBytecode.decompile`) and parser (`ScriptChunk.read`, `HandlerDef`) for standalone Lingo script bytecode chunks.
- A `LingoVMHost` protocol designed exactly for this kind of host integration:
  ```swift
  public protocol LingoVMHost: AnyObject {
      var movie: LingoObject { get }
      func sprite(_ channel: LingoValue) -> LingoObject?
      func member(_ id: LingoValue, castLib: LingoValue?) -> LingoObject?
      func menu(_ id: LingoValue) -> LingoObject?
      func sound(_ id: LingoValue) -> LingoObject?
      func window(_ id: LingoValue) -> LingoObject?
      func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject?
      func spriteIntersects(_ a: LingoObject, _ b: LingoObject) -> Bool
      func spriteWithin(_ a: LingoObject, _ b: LingoObject) -> Bool
      func hilite(_ member: LingoObject, type: String, first: LingoValue, last: LingoValue)
  }
  ```
- `LingoRuntime`'s `LingoObject` (property-bag base class with `getProperty`/`setProperty`/`callMethod`, ancestor-chain inheritance) and `LingoValue` (tagged value enum) — cast members and sprites should likely be modeled as `LingoObject` subclasses so Lingo scripts can read/write their properties through the same dynamic-dispatch mechanism scripts already use for everything else.

`swift-shockwave`'s job is everything *around* that VM: RIFX file parsing, the cast/score/movie data model, and a `LingoVMHost` conformance backed by real movie data.

## v1 goal

Load a real Director movie file and run its Lingo scripts headlessly against a cast/score/sprite model — no rendering, no audio output, no 3D, no Xtras. Enough to prove the pipeline end-to-end: **file → chunks → cast/score model → `LingoVM.call` → observable Lingo side effects** (global/property mutations, `put` output, etc.).

## Effort-sizing notes (structure only — not a literal spec to copy from anywhere)

A full Director/Shockwave player is a large undertaking. Rough shape of the problem, for planning purposes:

- **RIFX/chunk parsing** is the most mechanical, directly-portable-in-spirit piece: a top-level container walk (chunk map → chunk table → per-chunk decompression) dispatching to ~30 per-chunk-type parsers by four-character code (cast list, cast member, cast info, key table, script-context, script names, movie config, score, score order, frame labels, media, xtra list, cue points, bitmap, palette, sound, text, thumbnail, ...). The score chunk (the sprite/frame timeline binary format) is by far the most complex individual parser — budget real time for it.
- **Cast/score/movie model**: a `Movie` owns a cast manager (itself owning multiple named cast libraries, each holding cast members by number) and a `Score` (a frame/channel timeline referencing sprites, each pointing back at a cast member). Full-featured cast-member and score types in a complete player are enormous, mostly due to rendering/keyframe/tween/geometry state — a headless v1 needs a much smaller fraction of that surface (property storage + script/behavior references, not rendering-relevant fields).
- **Bytecode VM host-integration layer is the highest-risk part of this effort.** There is no existing clean abstraction to lean on for *how* to wire cast/score/movie state into VM opcode handling — this needs original design against `LingoVMHost`'s protocol: movie-property get/set, member lookup by name/number/cast-library, sprite property access, chunk/hilite text-range operations, sound-channel access, object instantiation. Treat this as a design task, not a mechanical translation.
- **Player lifecycle**: a frame loop that advances score/sprite state each tick and dispatches `enterFrame` to sprite behaviors then frame behaviors; discrete events (`mouseUp`, etc.) resolve the relevant script/handler and invoke it directly through `LingoVM.call`.

`swift-lingo` currently only parses a *standalone* Lingo-script bytecode chunk — it has no RIFX container reader and no cast/score/name/key-table chunk parsers. All of that is new work here.

## Proposed architecture

A SwiftPM package depending on `swift-lingo` (`LingoRuntime`, `LingoBytecode`, `LingoVM`) as a package dependency. Suggested module split (names indicative, refine when actually scaffolding):

- **`ShockwaveFile`** — RIFX container parsing: chunk-map walk, decompression, and a chunk-type registry dispatched by four-character code. Use `BinaryParsing` (already a `swift-lingo` dependency, same parsing style as `LingoBytecode`) for consistency. Chunk parsers phased in by what v1 actually needs first (see phases below); anything rendering/audio/3D-specific either skipped entirely or parsed only far enough to preserve raw bytes for a future rendering-focused project to pick up later.
- **`ShockwaveModel`** — the cast/score/movie runtime types: `Movie`, `CastLibrary`, `CastManager`, `CastMember` (as `LingoObject` subclasses), `Score`/`Sprite` (frame/channel timeline; geometry/rendering fields stubbed or omitted for v1).
- **`ShockwavePlayer`** (or similar) — the `LingoVMHost` conformance bridging the model above to `LingoVM`, plus a minimal frame-advance/event-dispatch loop (`enterFrame`, `mouseUp`, ...), calling `LingoVM.call` per handler.

## Phased plan

1. **RIFX container + name/key/context chunks**: chunk-map walk, decompression, key-table (parent/child chunk relationships), name table, script-context chunk, movie config chunk. Produces a flat chunk table + resolved name table usable directly by `LingoBytecode`.
2. **Cast chunks + model**: cast-member/cast-list/cast-info chunk parsing → `CastMember`/`CastLibrary`/`CastManager` runtime types; script chunks wired through `LingoBytecode.ScriptChunk`/`HandlerDef`.
3. **Score chunk + model**: score/score-order/frame-label chunk parsing → `Score`/`Sprite` timeline runtime types (no geometry/rendering).
4. **`LingoVMHost` conformance**: bridge the real model into `LingoVM`; first successful `LingoVM.call` against a real movie's real handler.
5. **Frame loop + event dispatch**: frame advance, `enterFrame`/`mouseUp` dispatch order, `go()` command — enough to run a movie headlessly end-to-end and observe Lingo side effects.
6. ~~Explicitly out of scope for this repo~~ *(amended post-v1)*: 2D rendering moved in-repo — see post-v1 roadmap below. Still out of scope: Xtras (file I/O, networking, system menu, XML parsing, external plugin hosting), 3D, font rasterization, multiuser networking.

## Post-v1 roadmap (phases 1–5 complete)

1. **Bitmap pipeline** (`ShockwaveFile`): `DRCF` stage rect, bitmap `CASt` specific-data (rowBytes/rect/regPoint/depth/palette), `CLUT` palettes + built-in system palettes, `BITD` RLE decode — each validated against the junkbot sample's real bitmaps.
2. **`ShockwaveSDL3` executable**: `CSDL3` system-library target; stage-sized window → cast bitmap viewer → sprite compositing at score tempo (puppeted sprites read from the player's `Sprite` property bags; copy ink first) → SDL mouse/keyboard events into `MoviePlayer.dispatch`.
3. **Score sprite-record field decode** — needs a sample movie that places sprites in the score (junkbot puppets everything).
4. **Afterburner (`.dcr`/`.cct`)**: `Fver`/`Fcdr`/`ILS `/`ABMP`/`FGEI` envelope + per-chunk zlib.
5. **Player depth as movies demand it**: `puppetSprite`/`updateStage`/`cursor`/timers/`the key`, `the actorList` + `stepFrame`, behavior initial values from score tertiary entries, `pass`/`stopEvent`, MacRoman string decoding, sound chunks.

## Conventions to carry over from `swift-lingo`

- Terse, backtick-quoted, imperative commit titles; no body text; no co-authored-by trailer; commit files individually except unit tests (batched into one "Update unit tests" commit).
- Run `swift-format` after every Swift edit.
- Default to writing no comments; only where the *why* is non-obvious.
- No premature abstraction — build what's needed for the current phase, not hypothetical future phases.
