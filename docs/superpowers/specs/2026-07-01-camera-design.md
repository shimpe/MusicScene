# MusicScene — OSC Camera Control (3D)

**Date:** 2026-07-01
**Status:** Approved design, ready for implementation planning
**Scope:** Add an OSC API to control the 3D `Camera3D` — position, aim (static point / track object /
chase-follow), FOV, projection (perspective|orthographic), and reset. **3D only** for now (a 2D
pan/zoom camera is a possible future follow-up). Also add **`/ms/scene reset`** — a full "like
first run" reset that clears the scene *and* the runtime simulation/view state (including the camera),
which `scene clear` intentionally does not. **Out of scope:** near/far clip planes, a dolly/zoom
shorthand, 2D camera.

---

## 1. Goal

The 3D backend auto-creates a fixed `Camera3D` (on +Z, looking down −Z at the origin) with no way to
move or configure it over OSC. Add a `/ms/camera` namespace so clients can frame the score-world:

```
s("/ms/camera", "pos", 0.0, 0.0, 1.2)
s("/ms/camera", "lookAt", 0.0, 0.0, 0.0)
s("/ms/camera", "fov", 50)
s("/ms/camera", "target", "note")      # keep 'note' centred as it moves
s("/ms/camera", "follow", "note", 0.6) # chase-cam at distance 0.6
s("/ms/camera", "projection", "orthographic")
s("/ms/camera", "reset")
```

---

## 2. Design principles

- **One dedicated subsystem.** A new `MSCamera` (`ctx.camera`) owns all camera state and control,
  mirroring the other `ctx.*` managers. It controls the **active** `Camera3D` (via
  `ctx.spatial.ensure_camera()` + `get_camera_3d()`), so it drives whichever camera is current
  (MusicScene-created or scene-provided).
- **Normalized coordinates.** Positions and look-at points are normalized (converted through the same
  `ctx.spatial.to_world_point` / `length_to_world` as everything else). Direction vectors (`up`) are
  normalized, not scaled. Angles are degrees.
- **3D-guarded.** In 2D mode every camera command replies `bad_arguments`
  (*"camera control is only available in 3d space"*). No 2D coordinate-mapper changes.
- **Per-frame tracking via a small state machine.** `none` / `target` / `follow`, updated once per
  frame from `MSRoot._process`.

---

## 3. Architecture

**New file** `addons/musicscene/core/MSCamera.gd` (RefCounted). State:

```
var ctx
var _mode: String = "none"        # none | target | follow
var _target_id: String = ""
var _offset: Vector3 = Vector3.ZERO   # world-space camera→object offset, for follow
var _up: Vector3 = Vector3(0, 1, 0)
```

Helpers: `_cam()` → `ctx.spatial.ensure_camera(); return ctx.get_viewport().get_camera_3d()`.

**Dispatcher.** Add a case to the top-level `match head:`:
```gdscript
"camera":
    ctx.camera.handle(parts.slice(2), args)
```
`handle(rest, args)` accepts both the path-tail form (`/ms/camera/pos …`) and the OSC-arg form
(`/ms/camera` + `["pos", …]`): the verb is `rest[0]` if present else `args[0]`; the remaining
values are the params.

**MSRoot.** `var camera = null`; construct `camera = MSCamera.new(self)` (after `spatial`);
in `_process(delta)` call `camera.step(delta)`.

**MSSpatial3D.** Extract the default-camera framing (currently inline in `ensure_camera`) into a
small reusable helper so `reset` and `ensure_camera` share it, e.g.
`configure_default_camera(cam)` setting position `(0,0, H/tan(fov/2)*1.2)`, `fov = CAMERA_FOV`,
perspective, identity rotation. `ensure_camera` calls it; `MSCamera` reset calls it via
`ctx.spatial`. (Small DRY refactor, in-scope because reset needs the same values.)

---

## 4. Command surface

`handle` dispatches on the verb. Positions/points normalized; `up` a direction; angles degrees.

| verb | behaviour |
|---|---|
| `pos <x> <y> <z>` | `cam.global_position = to_world_point(x,y,z)`; sets `_mode = none` |
| `lookAt <x> <y> <z>` | `cam.look_at(to_world_point(x,y,z), _up)`; `_mode = none` |
| `up <x> <y> <z>` | `_up = Vector3(x,y,z).normalized()` (default `(0,1,0)`) |
| `target <object_id>` | `_mode = target`, `_target_id = id`; re-aims each frame (see §5). Unknown id → `unknown_object` |
| `follow <object_id> [dist]` | capture offset, `_mode = follow` (see §5). Unknown id → `unknown_object` |
| `fov <degrees>` | `cam.fov = degrees` |
| `projection <perspective\|orthographic>` | `cam.projection = …` (`ortho`/`perspective` aliases) |
| `orthoSize <size>` | `cam.size = length_to_world(size)` (orthographic extent, normalized) |
| `reset` | `ctx.spatial.configure_default_camera(cam)`; `_mode = none`, `_target_id = ""`, `_up = (0,1,0)` |
| `info` | `ctx.reply("camera", ["pos", nx, ny, nz, "fov", fov, "projection", <str>, "tracking", _mode, _target_id])` |

Unknown verb → `bad_arguments`. Missing/short args use sensible defaults via the existing `_f` helper.

---

## 5. Tracking semantics (`step`)

State transitions:
- `pos`, `lookAt`, `reset` → `_mode = none` (manual control resumes).
- `target <id>` → `_mode = target` (orientation tracks; camera position unchanged).
- `follow <id> [dist]` → `_mode = follow`. On set, capture `_offset = cam.global_position −
  objectWorldPos` (preserves the current viewing angle). If `dist` is given, rescale:
  `_offset = _offset.normalized() * length_to_world(dist)`. If the offset is ~zero (camera on the
  object), fall back to a default back-offset `(0, 0, defaultDist)`.

`step(delta)` (called each frame; no-op when `_mode == none` or space isn't 3D):
```
cam = _cam(); if cam == null: return
obj = ctx.registry.get_object(_target_id)
if obj invalid: _mode = "none"; return          # tracked object freed → stop gracefully
op = (obj.node as Node3D).global_position
if _mode == "follow": cam.global_position = op + _offset
cam.look_at(op, _up)
```

`target` and `follow` are mutually exclusive (setting one replaces the other).

---

## 6. Scene clear vs scene reset (camera lifecycle)

**`/ms/scene clear`** (existing) clears the scene-bound id-spaces — objects, joints, time-maps —
but intentionally keeps global config and the camera. So after `clear`, the camera keeps its
position/fov/projection; if it was tracking an object that got cleared, `step` reverts tracking to
`none` gracefully. **No change to `clear`.**

**`/ms/scene reset`** (new) is a full "like first run" reset. Routed in `OscDispatcher._handle_scene`
alongside `clear`, it runs:

```
ctx.registry.clear()          # objects
ctx.joints.clear()            # joints
ctx.timemapper.clear()        # time-maps
ctx.emitter.clear()           # drop buffered queued/bundle/quantized events   (new: MSEmissionScheduler.clear)
ctx.physics_world.reset()     # enabled=false, paused=false, gravity=ZERO, debug=false, layer_names cleared, re-freeze  (new)
ctx.camera.reset()            # default framing + tracking cleared; no-op in 2D
ctx.mapper.app_mode / physics_mode = project-setting defaults          # reset coord modes
```

**Preserved (safety config):** permissions (`bindExisting`/`instantiate`/`callMethods`/`setProps`/
`freeNodes`), the scene whitelist, and `developer_mode`. Transport is also preserved (playback is a
separate concern).

New small methods this requires: `MSPhysicsWorld.reset()`, `MSEmissionScheduler.clear()`,
and a public `MSCamera.reset()` (the same routine the `camera reset` verb uses). The coord-mode
defaults are re-read from the `musicscene/app/coord_mode` / `musicscene/physics/coord_mode` settings
(fallback `"normalized"`).

---

## 7. Edge cases

- **2D space:** all camera commands error (guarded in `handle` and `step`).
- **No active camera:** `_cam()` calls `ensure_camera()` first, so a camera always exists in 3D.
- **`look_at` degeneracy:** if the camera position coincides with the look-at point, Godot's
  `look_at` errors; guard by skipping when the two are within an epsilon.
- **Freed tracked object:** `step` detects invalidity and reverts to `none`.
- **Scene-provided camera:** the API controls whatever `get_camera_3d()` returns; `reset` applies the
  MusicScene default framing to it.

---

## 8. Verification

- **Headless `tools/test_camera.gd`** (3D; a 2D run asserts the error path):
  - `pos`/`lookAt` set the camera transform (world position matches the normalized input).
  - `fov`, `projection` (perspective↔orthographic), `orthoSize` set the corresponding `Camera3D`
    properties.
  - `target <id>`: move the object, step a frame, assert the camera's forward (−Z) points at it.
  - `follow <id> [dist]`: move the object, step, assert the camera keeps the captured offset (position
    tracks) and still aims at it.
  - `reset` restores default fov/projection/position and clears tracking.
  - In 2D space, a camera command produces a `bad_arguments` error (assert via a captured/guarded path)
    and does not crash.
- **Headless `tools/test_scene_reset.gd`** (space-aware): after building objects + a joint + a
  time-map + enabling physics with gravity (+ moving the camera in 3D), `/ms/scene reset` leaves
  registry/joints/time-maps empty, physics disabled with zero gravity, coord modes back to default,
  and (3D) the camera at its default framing; a preserved permission flag set beforehand is still set.
- **CI** runs `test_camera.gd` and `test_scene_reset.gd`.
- **Documentation — both files:**
  - `TUTORIAL.md` gains a "Camera control (3D)" section with examples, and documents `scene reset`
    vs `scene clear`.
  - `README.md` gains a "Camera control" section and adds `camera` + `scene reset` to the API
    reference / command list, so the reference stays complete.
- **CHANGELOG** `[0.6.0]`; version bump.

---

## 9. File-change summary

**New:** `addons/musicscene/core/MSCamera.gd`, `tools/test_camera.gd`, `tools/test_scene_reset.gd`.
**Modified:**
- `addons/musicscene/core/OscDispatcher.gd` — route `camera`; add `scene reset`.
- `addons/musicscene/nodes/MSRoot.gd` — `ctx.camera` + per-frame `camera.step(delta)`.
- `addons/musicscene/core/MSSpatial3D.gd` — `configure_default_camera` helper (shared with
  `ensure_camera`).
- `addons/musicscene/physics/MSPhysicsWorld.gd` — `reset()` (disable/zero-gravity/unpause/debug-off/clear layer names).
- `addons/musicscene/events/MSEmissionScheduler.gd` — `clear()` (drop buffered events).
- `TUTORIAL.md` (camera section + `scene reset` vs `clear`), `README.md` (camera section + API
  reference entries for `camera` and `scene reset`), `CHANGELOG.md`, `addons/musicscene/plugin.cfg`
  (version), `.github/workflows/ci.yml`.

No changes to `MSRegistry.clear()` / `scene clear` semantics (unchanged).
