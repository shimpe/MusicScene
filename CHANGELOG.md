# Changelog

All notable changes to **MusicScene** are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [Unreleased]

### Added
- **Example — live two-hand score (SuperCollider).** `examples/supercollider/example_two_hands.scd`:
  two independent random patterns (right/left hand) generate notes and rhythms bar by bar and send each
  hand's score to MusicScene as ABC (filling four measures, then wiping and restarting from empty),
  visualising a treble+bass staff pair (two stacked notation objects) as it plays. Demonstrates live
  notation, zero-config Verovio, and `background`.
- **Notation background colour.** `/ms/scene/<id> background <colour>` (alias `bg`) fills an opaque
  "paper" behind a score — essential for Verovio/SVG scores, which draw ink on a transparent page.
  Accepts a named colour (`white`), hex (`#faf6e9`), or `r g b [a]` floats, plus `none` to clear. The
  colour is composited behind the page (cursor/regions stay on top), applies immediately without a
  re-render, and works identically in 2D and 3D.

### Fixed
- **Flicker on incremental 3D notation updates.** Re-rendering a 3D score (e.g. streaming notes one at
  a time) briefly tinted the current page yellow while the new one engraved. The "engraving" tint now
  appears only for the first render (when the page is empty); subsequent renders keep the previous page
  fully visible until the new one is ready. (The 2D path already behaved this way.)
- **Verovio scores padded with a wide white margin.** The bundled `verovio_render.py` set only
  `adjustPageHeight`, so a short excerpt was laid out on a full-width page and rendered with large empty
  space to the right. It now also sets `adjustPageWidth`, cropping the page to the music (a two-measure
  line goes from 840→515 px wide). Pass `--no-crop` to keep the full page width. Positions/timemap and
  the raster share the same cropped page, so addressable regions stay aligned.
- **Verovio (and other nested-`<svg>`) scores rendered blank.** Godot's ThorVG rasteriser ignores the
  `viewBox` scaling of a *nested* `<svg>` — the "definition-scale" wrapper Verovio emits — so MEI/ABC
  scores rasterised fully transparent (no error, the score just "disappeared"). The SVG backend now
  flattens a nested `<svg viewBox>` into an equivalent `<g transform="scale()">` before rasterising;
  the on-disk SVG (used for note-position parsing / following) is untouched. Fixes plain display,
  addressable display, and inline Verovio SVGs sent over OSC.
- **Missing staff and bar lines in Verovio scores.** Verovio colours staff/bar/stem lines with a
  `<style>` CSS rule (`path{stroke:currentColor}`) rather than a `stroke` attribute; ThorVG ignores the
  `<style>` block, so only the filled glyphs (clefs, noteheads, time signature) rendered while every
  stroked line disappeared. The SVG adapter now re-declares `stroke="currentColor"` on the container
  when an SVG uses that idiom, so ThorVG draws the lines (glyphs are unaffected).

### Changed
- **Self-contained engravers.** The engraver helper scripts MusicScene shells out to
  (`verovio_render.py`, `ly_to_score.py`, `mscore_to_score.py`) now live **inside the addon** under
  `addons/musicscene/tools/`, so installing the addon alone is enough — no separate `tools/` copy.
  (Client-side and test scripts such as `gosc.py`, `osc_test.py`, and `stub_engraver.py` stay at the
  repo root.)

### Added
- **Zero-config Verovio.** MEI and ABC now fall back to the bundled
  `res://addons/musicscene/tools/verovio_render.py` when no engraver is configured (launched via `py`
  on Windows, `python3` elsewhere, writing SVG), so they engrave after `pip install verovio` with no
  project settings. Override `musicscene/notation/engraver/mei` (or `/abc`) only to name a specific
  interpreter — e.g. a virtualenv's `python.exe`.
- **Better engraver diagnostics.** When an async engraver produces no output, the failure now reports
  the process exit code (`[engraver process exited with code N …]`) instead of only "no recognizable
  page", making a missing interpreter/script or an uninstalled dependency obvious.

## [0.12.0] — 2026-07-04

### Added
- **Collision reactors: bouncers & portals.** Two new Area-based object types.
  - `new bouncer` mirror-reflects a colliding body's velocity and adds an outward "kick" — a pinball
    bumper. The surface normal is exact for round (circle/sphere) and box/rect colliders (the face the
    body enters, honoring rotation). Configure with
    `/ms/scene/<id>/bouncer strength <s> gain <g> minSpeed <m>` (defaults `gain 1.0`, `strength 0`;
    `strength`/`minSpeed` are in normalized units — the same scale as a collider radius).
  - `new portal` teleports a colliding body to a random one of its linked targets, preserving velocity,
    with a short re-entry cooldown to prevent ping-pong. Configure with
    `/ms/scene/<id>/portal link <id...>` (directional; A→B does not imply B→A) and `portal unlink`.
  - Both are pass-through Areas and still emit `areaEnter`, so `on areaEnter …` bindings drive sound.
    Dimension-agnostic (2D and 3D).
- **Example:** `examples/supercollider/example_pinball.scd` — a self-contained generative pinball table
  combining bouncers, portals, sensor-zone targets, bouncy walls and pins, with all sound synthesised
  locally in SuperCollider.

## [0.11.0] — 2026-07-04

### Added
- **Multi-port OSC output.** MusicScene can now fan every reply and event out to a list of ports, so a
  client and one or more monitors each receive a copy. Configure a static list with the
  `musicscene/network/send_ports` project setting (e.g. `"7401,7402"`), or at runtime with
  `/ms/app/output <host> <port> [port2 …]`. `/ms/info` now reports the active output ports.

### Notes
- Fully backward-compatible: with `network/send_ports` unset the list is the single `network/send_port`
  (default 7401), identical to before; `/ms/app/output <host> <port>` with one port is unchanged.

## [0.10.0] — 2026-07-03

### Added
- **Volumetric primitives (3D):** `new sphere [r]`, `new box [w] [h] [d]` (alias `cube`),
  `new cylinder [r] [h]`, `new capsule [r] [h]`, `new cone [r] [h]`. Sized in the app coord mode,
  each with a matching auto-collider; `collider cylinder`/`collider capsule` shapes added.
- **Lighting (3D):** a default key + fill `DirectionalLight3D` rig is added automatically (skipped if
  the running scene already has a light). `/ms/light dir|color|energy|ambient|shadows|reset`.
- **Lit materials (3D):** volumetric primitives are lit by default; `circle` and flat/billboard
  elements stay unshaded. Per-object `shaded [1|0]`, `metallic <0..1>`, `roughness <0..1>`. Global
  `/ms/scene shading auto|shaded|flat`.

### Notes
- Fully backward-compatible: `circle`, `rect`, `text`, notation, etc. render exactly as before; the
  default lights only affect lit materials, which only the new primitives use by default.
- 2D: the new primitive names alias to the nearest flat shape; the material/light commands are no-ops.

## [0.9.0] — 2026-07-02

### Added
- **Sizable primitives** — `new circle <r>` and `new rect <w> [h]` now accept an optional size in the
  app coordinate mode (h defaults to w); omit for the previous fixed default. The auto-collider created
  on `physics enable` tracks the sized mesh, so a small primitive gets a small collider. This unblocks
  physics-dense scenes (e.g. a pachinko board) that need many small bodies — the fixed-size primitives
  were too coarse to build one.
- **Example: `tools/example_pachinko.py`** — a gravity-fed pachinko music box. Small balls rain through
  an offset peg grid into five pentatonic bins, each emitting `/music/note <bin> <note> <ball> <speed>`;
  the client recycles a ball the instant it lands (listening for its own notes) with a watchdog for
  stuck balls. Relies on sizable primitives (small balls/pegs) and `planar` (0.8.0) to stay reliable.

### Notes
- Getting the pachinko working surfaced why it failed before: out-of-plane **z-drift** (fixed by
  `planar` in 0.8.0 — balls were slipping past pegs/floor/bins in z) *plus* the fixed-size primitives
  being too coarse (fixed here). Both were real engine gaps for physics-heavy use.

## [0.8.0] — 2026-07-02

### Added
- **`/ms/scene/<id>/physics planar <0|1>`** — pin a rigid body to the z=0 plane (3D). MusicScene's 3D
  is effectively "2D in a plane", but a `RigidBody3D` accumulates a small out-of-plane velocity from
  collisions and solver drift that eventually carries it past the limited z-depth of colliders/areas,
  so it silently stops colliding while still looking fine head-on. `planar 1` locks the linear z axis
  and snaps z back to 0; no-op in 2D. The `example_chaos_globe.py` balls now use it so the piece keeps
  emitting indefinitely.

## [0.7.0] — 2026-07-01

### Added
- **`physics enable` now auto-creates a matching collider.** Enabling physics on an object
  (`rigid`/`static`/`area`) gives it a collision shape sized to its visible mesh (equivalent to
  `collider auto`), so bodies collide and are sensed by areas without a separate `collider` command; an
  explicit `collider …` still replaces the automatic shape. Bodies connected by a joint are excluded
  from colliding with each other (Godot's joint default), so hinge/spring setups are unaffected. The 3D
  `auto` collider now floors each axis to a small minimum so a flat quad (`rect`/notation) yields a
  usable volume instead of a degenerate zero-thickness box.
- **Joint debug overlay.** `/ms/physics debug 1` now also draws each joint (which otherwise has no
  visual): a line between its two bodies, a pivot marker, and — for a `hinge`/`slider` — the working
  axis. The overlay tracks the bodies each frame, is drawn on top, and is removed by `debug 0` or a
  scene clear/reset. Works in both 2D and 3D.

### Docs
- `TUTORIAL.md`: §7 gains a **Damping** note (contact `friction` doesn't slow a free swing — use
  `physics damping`, with the linear term being the effective one for a pendulum) plus an explanation of
  the surprising hinge `limit` result; §8 now documents that colliders are automatic and how to size a
  manual one (the normalized-units ×5 trap: `collider sphere 0.3` is a 1.5-world sphere). `README.md`
  colliders section documents the auto-creation and sizing.

## [0.6.0] — 2026-07-01

### Added
- **OSC camera control (3D)** — `/ms/camera` with `pos`, `lookAt`, `up`, `target` (re-aim at an
  object each frame), `follow` (chase-cam), `fov`, `projection` (perspective|orthographic),
  `orthoSize`, `reset`, and `info`. Normalized coordinates; 3D only (2D commands error).
- **`/ms/scene reset`** — a full "like first run" reset: clears objects/joints/time-maps and
  disables physics, zeroes gravity, resets the camera to default framing, drops buffered events, and
  restores default coordinate modes. Safety config (permissions, whitelist, developer mode) and the
  transport are preserved; `scene clear` is unchanged.

## [0.5.3] — 2026-07-01

### Changed
- **Default 3D `circle` primitive is smaller** — sphere radius `0.5` → `0.3` world (`0.06` normalized,
  matching the 2D circle's relative size). At `0.5` the sphere spanned `0.2` normalized, so objects at
  a normal `0.2` spacing (e.g. the tutorial's hinge example) visually overlapped and looked "glued
  together" even though the joint was correctly maintaining their separation.

## [0.5.2] — 2026-07-01

### Fixed
- **`pos` (and `x`/`y`/`z`) on a RigidBody now sticks while physics is simulating.** Previously a
  plain `global_position` assignment to an awake (gravity-kept-active) `RigidBody2D` was reverted by
  the physics server on the next step, snapping the body back to its creation origin (normalized
  `(-1, +1)` = top-left). This is why a re-run that populated the scene *while physics was already
  enabled* (e.g. after a first run left physics on through a `scene clear`) placed objects at the
  wrong position. Transform commands now teleport rigid bodies via `PhysicsServer2D/3D.body_set_state`,
  which is authoritative whether the body is frozen or active.

## [0.5.1] — 2026-06-30

### Fixed
- **`/ms/scene clear` now clears every scene-bound id-space** — not just registry objects, but
  also joints (`ctx.joints`) and time-maps (`ctx.timemapper`). Previously these separate id-spaces
  survived a scene clear and were only removed reactively a physics tick later, leaving a window
  where a stale joint (whose name-based `node_a`/`node_b` could re-bind to rebuilt bodies or dangle
  to world origin) could interfere with the next run. Global config (layer names, gravity, transport,
  permissions, coord modes) is intentionally preserved.

## [0.5.0] — 2026-06-30

### Added
- **Event-system completion** (spec §19): `collisionStay` continuous-contact events (per-body
  throttled, mirroring `areaStay`); a functional `layer` event filter (matches the other body's
  collision-layer name or number); and the `mode` option — `queued`, `bundle` (one OSC bundle per
  frame), and `quantized` (snapped to the next transport beat via `quantizeGrid`) — via a new
  per-frame emission scheduler. `positionEnter`/`positionExit` were intentionally dropped (redundant
  with area zones and `yAbove`/`yBelow`).

### Changed
- The `layer` payload field in physics event bindings now carries the other body's collision-layer
  names (comma-joined; named layers, else the bit number) — it was previously always empty.

## [0.4.0] — 2026-06-30

### Added
- **Sensors & trigger zones** (spec §12): `areaStay` continuous presence events, emitted per physics
  frame for each body inside an area and throttled **per body** by `maxRate`. New other-centric
  payload fields (`otherx/othery/otherz/othervx/othervy/othervz/otherspeed`) report each contained
  body's position and velocity. Event payloads can now carry **literal constants** via a `'`/`=`
  prefix (e.g. `payload areaEnter self other =A`). Area enter/exit, filters and rate-limiting were
  already supported.

## [0.3.0] — 2026-06-30

### Added
- **Physics joints** (`/ms/joint/<id>`), native per space. 2D: `pin`, `spring`/`dampedSpring`,
  `groove`, `distance`. 3D: `pin`, `hinge`, `slider`, `coneTwist`, `generic6dof` (per-DOF via `dof`).
  Properties `stiffness`/`damping` (normalized 0..1), `restLength`, `limit`, `motor`, `axis`,
  `breakForce`, plus `del` and `info`/`joints list` queries. `breakForce` is an overstretch proxy and
  emits `/ms/event/jointBreak`. Mirrors the physics architecture (`MSJointWorld` /
  `MSJoint` + spatial-backend joint methods).

## [0.2.1] — 2026-06-30

### Fixed
- **3D notation cursor** stayed on top of the score quad for the whole sweep. The page, regions and
  cursor are coplanar transparent quads; Godot sorts transparents by origin distance, so the moving
  cursor sorted behind the page off-centre and only popped in front near the middle. Explicit
  `render_priority` (page 0 < regions 1 < cursor 2 < annotations 3) gives stable layering.
- **Registry**: re-creating an existing id now frees the old MusicScene-owned node instead of orphaning
  it in the tree (bound/auto-bound nodes are still only unbound, never freed).

### Docs
- `TUTORIAL.md`: documented the `capabilities` reply and the reply/event format; added
  `transport stop/pause/seek/state` after `play`; tightened the `m1` region rect in the 3D
  notation-on-a-quad example (5.5).

## [0.2.0] — 2026-06-30

A large feature pass since the initial implementation.

### Added
- **2D and 3D** support, selectable via `musicscene/space` (`"2d"` | `"3d"`), behind a spatial
  backend abstraction (`MSSpatial2D` / `MSSpatial3D`). Same OSC API for both; 3D auto-creates
  a `Camera3D` and uses camera-ray picking; notation renders on a textured quad in world space.
- **Runtime-generated scores**: a notation source may be a file path (`res://` / `user://` /
  absolute), inline data over OSC (SVG/MusicXML/LilyPond/ABC string, or raster bytes as a blob), or
  symbolic music engraved on the fly. `notationData` forces inline data.
- **External engravers**: per-format commands (`notation/engraver/<fmt>`), tokens
  `{input} {output} {outbase} {outdir} {format} {page}`, `res://` resolution, and automatic
  resolution of self-named outputs. Working defaults for **MuseScore** (MusicXML),
  **LilyPond** (`.ly`), and **Verovio** (MEI/ABC, `pip install verovio`).
- **Async (non-blocking) engraving** via `OS.create_process` + polling — the app stays responsive
  while an engraver runs; results are cached.
- **Addressable / following notation**:
  - MuseScore → measure regions + timing (`.mpos`); `measures` query; `cursor measure <n>`.
  - LilyPond → note-level regions + timing (injected Scheme tagger + point-and-click SVG).
  - Verovio → note-level regions + timing (stable SVG ids + timemap).
  - `addressable 1`, `elements` query, clickable note/measure regions, and `cursor follow 1`
    (cursor tracks the transport and emits `/ms/event/note` / `/ms/event/measure`).
- SVG notation: prefers Godot's import for `res://`, runtime-rasterizes other paths/inline.
- `TUTORIAL.md` (2D + 3D getting started, all score-display options), bundled engraver wrappers and
  test tools, CI, this changelog.

### Fixed
- OSC argument coercion uses `str()` (not the `String()` constructor) so non-string args (blobs,
  numbers) no longer crash with "Nonexistent 'String' constructor".
- `res://` SVG scores load via Godot's import instead of fragile runtime re-rasterization.
- RefCounted cycle (object ↔ physics adapter) and freed-lambda crashes cleaned up.

## [0.1.0]

Initial implementation: OSC server + codec, dispatcher, registry (OSC-id ⇄ node), built-in objects,
transforms, notation (PNG/SVG, cursor, regions, annotations), 2D physics + collision/area/input
events, signal forwarding, node binding, PackedScene instantiation, transport + time mapping, script
runner, permissions, examples, README.
