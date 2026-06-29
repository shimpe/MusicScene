# gscore_osc — Design

Date: 2026-06-29
Target: Godot 4.7 (stable Godot 4.x APIs, pure GDScript)
Form: Godot addon at `addons/gscore_osc/`, runnable out-of-the-box via autoload.

## 1. Purpose

An OSC-controlled, INScore-inspired interactive music-score / world system. External
OSC clients (Max/MSP, Pd, SuperCollider, Python, TouchDesigner, …) create, bind, control,
animate, query and receive events from Godot scene objects under the root namespace
`/gscore`. Beyond INScore it adds Godot 2D physics, collision-driven OSC emission, binding
existing nodes, PackedScene instantiation, exposing methods/properties/signals over OSC,
and first-class music-notation display.

The full external spec (sections 1–36, including the complete OSC API surface and acceptance
criteria) is the authoritative requirements source. This document records the *internal
architecture and the technical decisions* that the spec leaves open.

## 2. Key principle

OSC identity is decoupled from Godot node identity. Clients address stable OSC IDs
(`/gscore/scene/score`) via `GScoreRegistry`, which maps id ⇄ wrapped node and tracks
ownership (`created_by_osc`, `instantiated_by_osc`, `bound_existing`, `auto_bound`,
`group_binding`). All registered objects share one command surface through `GScoreObject`.

## 3. Architecture decisions

- **2D world.** The spec uses RigidBody2D/StaticBody2D/Area2D. Everything lives in Node2D
  world space so positions/scale/rotation/modulate compose uniformly.
- **Central controller = `GScoreRoot`** (extends Node2D), installed as autoload `GScoreOSC`
  by `plugin.gd` and pre-registered in `project.godot` so the project runs on open. It owns
  and wires every subsystem and parents all OSC-created objects (so their Node2D children
  render in the active viewport).
- **Visual primitives** are drawn by one `GScorePrimitive2D` (custom `_draw`: rect/circle/
  line/text via `ThemeDB.fallback_font`); image/sprite/notation use `Sprite2D`. This keeps
  all objects in Node2D space and makes color/opacity (`modulate`) and transforms uniform.
- **Coordinates.** Default normalized score space: x∈[-1,1] L→R, y∈[-1,1] bottom→top
  (y-up). `GScoreCoordinateMapper` converts points (scale+flip+center offset) and vectors
  (scale+flip only) for modes normalized | pixels | world, separately for app and physics.
  Notation-internal coords (cursor/region) are [0,1] over the page rect, y-down.
- **OSC layer is pure GDScript and swappable.** `OscPacket` encodes/decodes messages and
  bundles (types i,f,s,b,T,F,h,d). `OscServer` uses `PacketPeerUDP` (bind to listen port;
  send replies/events to last-sender IP or configured host on the send port). `OscDispatcher`
  routes by address segments to small per-area sub-dispatchers (no monolith).
- **Dispatch shape.** `/gscore/scene/<id> <cmd> …` (command in args) for generic object
  commands; `/gscore/scene/<id>/<subsystem> …` (subsystem in address: physics, collider,
  on/off/payload, signal, cursor, region, annotation, plus notation queries) routed to the
  relevant manager. region/annotation take `<id_arg> <cmd> …` in args.
- **Notation backends** behind `GScoreNotationRenderer`: v1 image(PNG) + SVG
  (`Image.load_svg_from_string`, guarded), plus a `GScoreNotationBackendMusicXML` that shells
  out via `OS.execute` to a configurable external engraver (MuseScore/LilyPond/Verovio →
  SVG/PNG pages). Same OSC API regardless of backend. Pages cached under
  `user://gscore_cache/notation/` keyed by a hash of (source, format, page, backend, options).
- **Input/click** handled centrally by `GScoreInputEvents` (hit-tests objects/notation
  regions in their own coord space on mouse events) rather than per-object Area2D, so any
  visual object or notation region is clickable.
- **Collision events** via `GScoreCollisionEvents`: RigidBody2D contact monitoring + Area2D
  signals → compute intensity/pos/vel, apply per-binding options (minIntensity, cooldown,
  maxRate, layer, other, mode), emit to the bound target address and to canonical
  `/gscore/event/physics`. Input emits canonical `/gscore/event/input`.
- **Permissions** (`GScorePermissions`): conservative defaults — bindExisting only for
  exposed nodes, instantiate only whitelisted scenes/prefixes, callMethods/setProps only for
  exposed members, freeNodes off. A developer-mode project setting relaxes this for local use.
- **Exposure**: `OscExposable` marker node (exposes its parent, or a `target_path`) with
  @export osc_id/auto_bind/allow_bind/allow_free/methods/properties/signals; plus metadata
  exposure (`osc_expose`, `osc_id`). Registry auto-binds on startup.
- **Transport/time**: `GScoreTransport` (play/stop/pause/seek/tempo/time/beat/state) drives
  `GScoreTimeMapper` interpolations (`/scene/<id> map …`, cursor map) each frame.
- **Script runner**: `GScoreScriptRunner` tokenizes OSC-style text lines (quotes, typed
  literals, `#` comments) and feeds the dispatcher; loads `.gscore` files.

## 4. Module map

Matches the spec's required structure under `addons/gscore_osc/`: core/ (OscServer,
OscPacket, OscDispatcher, GScoreRegistry, GScoreObject, GScoreFactory, GScorePermissions,
GScoreCoordinateMapper), notation/, physics/, events/, transport/, script/, nodes/
(OscExposable, GScoreRoot), examples/.

## 5. Errors & replies

Structured `/gscore/error <code> <address> <message>` (codes: unknown_object,
unknown_property, bad_arguments, unsupported_type, load_failed, permission_denied,
internal_error). Replies use `/gscore/reply <topic> …`; `/gscore/pong` for ping; canonical
events under `/gscore/event/*`.

## 6. Verification

No CI; verify by running Godot 4.7 headless to catch parse/load errors, then manual OSC
round-trip (a bundled Python `tools/osc_test.py` sender) against the running example scene.

## 7. Out of scope for v1

Auto-generated notation regions from engraver bounding boxes; symbolic in-engine engraving;
OSC over TCP; variables in the script runner.
