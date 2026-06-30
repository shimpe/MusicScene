# Event-System Completion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete §19 of the gscore_osc spec: a functional `layer` event filter, the `mode` option (`queued`/`bundle`/`quantized`) via a per-frame emission scheduler, and `collisionStay` continuous-contact events.

**Architecture:** Three additions on the existing event system. The `layer` filter populates the event-data `layer` field (other body's layers) and switches the binding check to membership. A new `GScoreEmissionScheduler` buffers non-immediate emissions and flushes them each frame (bundle via the existing `OscServer.send_bundle`, quantized snapped to the transport beat); all three emission call sites route through it. `collisionStay` mirrors the existing `areaStay` block (per-body throttled), using the scheduler.

**Tech Stack:** Godot 4.7, GDScript. Tests are headless SceneTree scripts run via `godot --headless --path . --script res://tools/<t>.gd`, printing `PASS:`/`FAIL:`. Some checks unit-test preloaded classes; others drive the live `GScoreOSC` autoload.

**Engine binary:** `D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`

---

## Background the engineer needs

- **Run a test:** `"<godot>" --headless --path . --script res://tools/test_events.gd`. Before each run free the UDP port: `powershell -Command "Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } | Stop-Process -Force -ErrorAction SilentlyContinue"`. AV may lock git objects — retry `git add`/`commit`.
- **GDScript 4.7:** `:=` can't infer from untyped values (`ctx`, `.get()`); use explicit `var x: T =` or untyped `var x =`. `str(v)` not `String(v)`. `",".join(packed_string_array)` is valid. `Dictionary.keys()` returns a fresh array (safe to erase during iteration).
- **`GScoreEventBinding`** (`addons/gscore_osc/events/GScoreEventBinding.gd`): fields incl. `target`, `mode` (default `"immediate"`), `layer_filter`, `other_filter`, `min_intensity`, `cooldown`, `max_rate`, `_last_emit_other`. Methods `should_emit(intensity, now, other_id, layer)`, `should_emit_other(intensity, now, other_id, layer)`, `mark_other`, `prune_others`, `_passes_filters(intensity, other_id, layer)`, `_gap()`, `build_args(data)`, `set_option(key, value)`.
- **`GScoreCollisionEvents`** (`addons/gscore_osc/physics/GScoreCollisionEvents.gd`, static funcs): `emit(ctx, obj, event, other)` (discrete) emits the canonical `/gscore/event/physics` then the binding target; `check_continuous(ctx, obj)` runs each physics frame (while `ctx.physics_world.is_simulating()`) and currently handles velocity/y events + `areaStay`; `_build_data(...) -> Dictionary` (keys lowercase; `"layer"` currently constant `""`).
- **Backends** (`core/GScoreSpatial2D.gd`/`GScoreSpatial3D.gd`) already have `is_area`, `overlapping_others`, plus `body_get_velocity`, `point_to_norm`, etc. `physics_world.layer_names` maps layer number → name (set via `/gscore/physics/layer <n> <name>`). `physics_world.layer_bit(value)` resolves a name/number to a bitmask.
- **`OscServer.send_bundle(elements, timetag=1)`** already exists; `elements` are `{address, args}` dicts. `ctx.send_event(addr, args)` and `ctx.server` are available.
- **Emission sites to reroute (Task 2):** in `GScoreCollisionEvents.gd` — `emit` (binding target line ~26), the velocity/y loop (line ~50), and the `areaStay` block. The canonical `/gscore/event/physics` send in `emit` stays immediate.

## File structure

| File | Change |
|---|---|
| `addons/gscore_osc/events/GScoreEventBinding.gd` | layer membership in `_passes_filters`; `quantize_grid` field + `quantizegrid` option |
| `addons/gscore_osc/events/GScoreEmissionScheduler.gd` | **New** — buffer/flush by mode |
| `addons/gscore_osc/physics/GScoreCollisionEvents.gd` | `layer` in `_build_data`; reroute emissions to `ctx.emitter`; `collisionStay` block |
| `addons/gscore_osc/core/GScoreSpatial2D.gd` + `GScoreSpatial3D.gd` | `layer_names_for`, `colliding_others` |
| `addons/gscore_osc/nodes/GScoreRoot.gd` | `ctx.emitter` + per-frame `flush` |
| `tools/test_events.gd` | **New** — built up across tasks |
| `TUTORIAL.md`, `CHANGELOG.md`, `plugin.cfg`, `OscDispatcher.gd`, `.github/workflows/ci.yml` | docs, version, CI |

---

## Task 1: Functional `layer` filter

**Files:** Modify `GScoreEventBinding.gd`, `GScoreCollisionEvents.gd`, `GScoreSpatial2D.gd`, `GScoreSpatial3D.gd`. Test: `tools/test_events.gd`.

- [ ] **Step 1: Write the failing test** — create `tools/test_events.gd`:

```gdscript
extends SceneTree
## Headless event-system tests. Run:
##   <godot> --headless --path . --script res://tools/test_events.gd
## Space-aware (run once per space). Mixes unit (preloaded) + integration (live autoload) checks.
const EB := preload("res://addons/gscore_osc/events/GScoreEventBinding.gd")
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", msg)
	else:
		_fail += 1
		print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 2:
		# layer filter membership (unit, via should_emit which calls _passes_filters)
		var b = EB.new()
		b.layer_filter = "perc"
		check(b.should_emit(1.0, 0.0, "x", "perc,bass"), "layer filter matches a member")
		check(not b.should_emit(1.0, 0.0, "x", "bass,drums"), "layer filter rejects a non-member")
		b.layer_filter = ""
		check(b.should_emit(1.0, 0.0, "x", "anything"), "empty layer filter always passes")
	if _f == 3:
		osc.dispatcher.dispatch("/gscore/physics/layer", [3, "perc"])
		osc.dispatcher.dispatch("/gscore/scene/obj", ["new", "circle"])
		osc.dispatcher.dispatch("/gscore/scene/obj/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/gscore/scene/obj/physics", ["layer", "perc"])
	if _f == 5:
		var o = osc.registry.get_object("obj")
		var names = osc.spatial.layer_names_for(o.physics_adapter.body)
		check("perc" in names, "layer_names_for resolves a named layer")
	if _f == 8:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run to verify it fails**

Run: `"D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://tools/test_events.gd`
Expected: `FAIL: layer filter rejects a non-member` (current `_passes_filters` does equality: `"perc" != "bass,drums"` is true → it would actually reject, so this one may pass by luck — but `FAIL: layer filter matches a member` WILL fail, because `"perc" != "perc,bass"` is true → rejected) and/or a runtime error on `osc.spatial.layer_names_for` (method missing).

- [ ] **Step 3: Add `layer_names_for` to both backends** — append to `GScoreSpatial2D.gd`:

```gdscript
func layer_names_for(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is CollisionObject2D:
		var bits: int = (node as CollisionObject2D).collision_layer
		for i in range(1, 33):
			if bits & (1 << (i - 1)):
				out.append(str(ctx.physics_world.layer_names.get(i, i)))
	return out
```

And to `GScoreSpatial3D.gd` (same, with `CollisionObject3D`):

```gdscript
func layer_names_for(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is CollisionObject3D:
		var bits: int = (node as CollisionObject3D).collision_layer
		for i in range(1, 33):
			if bits & (1 << (i - 1)):
				out.append(str(ctx.physics_world.layer_names.get(i, i)))
	return out
```

- [ ] **Step 4: Populate `data["layer"]`** — in `GScoreCollisionEvents._build_data`, change the line `"layer": "",` to:

```gdscript
		"layer": ",".join(sp.layer_names_for(other)) if other != null else "",
```

- [ ] **Step 5: Membership check** — in `GScoreEventBinding._passes_filters`, replace the layer line `if layer_filter != "" and layer != layer_filter:` with:

```gdscript
	if layer_filter != "" and not (layer_filter in str(layer).split(",")):
		return false
```

- [ ] **Step 6: Run to verify it passes**

Run the test. Expected: `PASS: layer filter matches a member`, `PASS: layer filter rejects a non-member`, `PASS: empty layer filter always passes`, `PASS: layer_names_for resolves a named layer`, `DONE pass=4 fail=0`.

- [ ] **Step 7: Commit**

```bash
git add addons/gscore_osc/events/GScoreEventBinding.gd addons/gscore_osc/physics/GScoreCollisionEvents.gd addons/gscore_osc/core/GScoreSpatial2D.gd addons/gscore_osc/core/GScoreSpatial3D.gd tools/test_events.gd
git commit -m "feat(events): functional layer filter (other body's layer names)"
```

---

## Task 2: Emission scheduler + `mode` (queued / bundle / quantized)

**Files:** Create `GScoreEmissionScheduler.gd`; modify `GScoreEventBinding.gd`, `GScoreRoot.gd`, `GScoreCollisionEvents.gd`. Test: `tools/test_events.gd`.

- [ ] **Step 1: Add the failing test** — insert before the DONE block (bump DONE from `_f == 8` to `_f == 12`):

```gdscript
	if _f == 7:
		var SCHED = load("res://addons/gscore_osc/events/GScoreEmissionScheduler.gd")
		var sch = SCHED.new(osc)
		sch.emit("/a", [1], "queued", 1.0)
		check(sch._queued.size() == 1, "queued buffers")
		sch.flush(0.0)
		check(sch._queued.is_empty(), "queued flushes")
		sch.emit("/b", [2], "bundle", 1.0)
		check(sch._bundle.size() == 1, "bundle buffers")
		sch.flush(0.0)
		check(sch._bundle.is_empty(), "bundle flushes")
		sch.emit("/c", [3], "quantized", 1.0)
		check(sch._quantized.size() == 1, "quantized buffers")
		var fb: float = sch._quantized[0].fire_beat
		sch.flush(fb - 0.01)
		check(sch._quantized.size() == 1, "quantized withheld before its grid beat")
		sch.flush(fb)
		check(sch._quantized.is_empty(), "quantized released at its grid beat")
		check(sch._next_grid(2.3, 1.0) == 3.0, "_next_grid 2.3 -> 3.0")
		check(sch._next_grid(2.0, 1.0) == 3.0, "_next_grid 2.0 -> 3.0")
```

Change DONE to:
```gdscript
	if _f == 12:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
```

- [ ] **Step 2: Run to verify it fails**

Expected: error loading the scheduler script / `FAIL: queued buffers` (file doesn't exist).

- [ ] **Step 3: Create `addons/gscore_osc/events/GScoreEmissionScheduler.gd`:**

```gdscript
extends RefCounted
## Buffers non-immediate event emissions and flushes them once per frame.
## - immediate: sent now (bypasses all buffers)
## - queued:    accumulated, flushed as individual messages at end of frame
## - bundle:    the frame's bundle-mode events sent as one OSC bundle
## - quantized: held until the transport beat crosses the next grid line, then sent

var ctx = null
var _queued: Array = []      # {address, args}
var _bundle: Array = []      # {address, args}
var _quantized: Array = []   # {address, args, fire_beat}

func _init(p_ctx) -> void:
	ctx = p_ctx

func emit(address: String, args: Array, mode: String, grid: float) -> void:
	match mode:
		"queued":
			_queued.append({"address": address, "args": args})
		"bundle":
			_bundle.append({"address": address, "args": args})
		"quantized":
			var beat: float = ctx.transport.beat if ctx.transport != null else 0.0
			_quantized.append({"address": address, "args": args, "fire_beat": _next_grid(beat, grid)})
		_:
			ctx.send_event(address, args)   # "immediate" and any unknown mode

func flush(now_beat: float) -> void:
	for m in _queued:
		ctx.send_event(m.address, m.args)
	_queued.clear()
	if not _bundle.is_empty():
		ctx.server.send_bundle(_bundle)
		_bundle.clear()
	if not _quantized.is_empty():
		var keep: Array = []
		for m in _quantized:
			if now_beat >= m.fire_beat:
				ctx.send_event(m.address, m.args)
			else:
				keep.append(m)
		_quantized = keep

func _next_grid(beat: float, grid: float) -> float:
	if grid <= 0.0:
		return beat   # no grid -> fire on next flush
	return (floor(beat / grid) + 1.0) * grid
```

- [ ] **Step 4: Add `quantize_grid` to `GScoreEventBinding.gd`** — add the field near `var mode`:

```gdscript
var quantize_grid: float = 1.0     # beats; grid for mode "quantized"
```

And add a case in `set_option`'s match (alongside `"mode"`):

```gdscript
		"quantizegrid": quantize_grid = maxf(float(value), 0.0)
```

- [ ] **Step 5: Wire the scheduler in `GScoreRoot.gd`** — add member near the other subsystems:

```gdscript
var emitter = null
```

Add the preload with the other consts:
```gdscript
const GScoreEmissionScheduler := preload("res://addons/gscore_osc/events/GScoreEmissionScheduler.gd")
```

Construct it after `transport` is created (it reads `ctx.transport`):
```gdscript
	emitter = GScoreEmissionScheduler.new(self)
```

Flush each frame in `_process(delta)`, after the transport/timemapper updates:
```gdscript
	if emitter != null and transport != null:
		emitter.flush(transport.beat)
```

- [ ] **Step 6: Reroute the emission sites in `GScoreCollisionEvents.gd`** — replace each binding emission with the scheduler call (leave the canonical `/gscore/event/physics` send in `emit` as a direct `ctx.send_event`):

In `emit`, change:
```gdscript
	binding.mark(data["time"])
	ctx.send_event(binding.target, binding.build_args(data))
```
to:
```gdscript
	binding.mark(data["time"])
	ctx.emitter.emit(binding.target, binding.build_args(data), binding.mode, binding.quantize_grid)
```

In the velocity/y loop, change:
```gdscript
			b.mark(data["time"])
			ctx.send_event(b.target, b.build_args(data))
```
to:
```gdscript
			b.mark(data["time"])
			ctx.emitter.emit(b.target, b.build_args(data), b.mode, b.quantize_grid)
```

In the `areaStay` block, change:
```gdscript
				sb.mark_other(oid, odata["time"])
				ctx.send_event(sb.target, sb.build_args(odata))
```
to:
```gdscript
				sb.mark_other(oid, odata["time"])
				ctx.emitter.emit(sb.target, sb.build_args(odata), sb.mode, sb.quantize_grid)
```

- [ ] **Step 7: Run to verify it passes**

Run `test_events.gd`. Expected: all scheduler checks PASS, `DONE pass=12 fail=0`.

- [ ] **Step 8: Regression-check existing event tests** (the reroute must not change immediate-mode behavior):

Run: `"D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://tools/test_zones.gd`
Expected: `DONE pass=17 fail=0` (areaStay still works through the scheduler in immediate mode).

- [ ] **Step 9: Commit**

```bash
git add addons/gscore_osc/events/GScoreEmissionScheduler.gd addons/gscore_osc/events/GScoreEventBinding.gd addons/gscore_osc/nodes/GScoreRoot.gd addons/gscore_osc/physics/GScoreCollisionEvents.gd tools/test_events.gd
git commit -m "feat(events): emission scheduler with queued/bundle/quantized modes"
```

---

## Task 3: `collisionStay` continuous-contact events

**Files:** Modify `GScoreCollisionEvents.gd`, `GScoreSpatial2D.gd`, `GScoreSpatial3D.gd`. Test: `tools/test_events.gd`.

- [ ] **Step 1: Add the failing test** — insert before the DONE block (bump DONE from `_f == 12` to `_f == 40`). The rigid ball is placed already resting in contact with the static floor (with gravity holding it down) so contact is detected within a few frames — not dependent on a long fall:

```gdscript
	if _f == 14:
		osc.dispatcher.dispatch("/gscore/scene/floor", ["new", "rect"])
		osc.dispatcher.dispatch("/gscore/scene/floor/physics", ["enable", "static"])
		osc.dispatcher.dispatch("/gscore/scene/floor/collider", ["rect", 1.0, 0.1])
		osc.dispatcher.dispatch("/gscore/scene/floor", ["pos", 0.0, -0.3, 0.0])   # collider top at y=-0.25
		osc.dispatcher.dispatch("/gscore/scene/dropball", ["new", "circle"])
		osc.dispatcher.dispatch("/gscore/scene/dropball/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/gscore/scene/dropball/collider", ["circle", 0.08])
		osc.dispatcher.dispatch("/gscore/scene/dropball", ["pos", 0.0, -0.18, 0.0])  # bottom y=-0.26: touching/overlapping the floor top
		osc.dispatcher.dispatch("/gscore/scene/dropball/on", ["collisionStay", "/synth/sustain", "maxRate", 30])
		osc.dispatcher.dispatch("/gscore/physics", ["gravity", 0.0, -1.0, 0.0])
		osc.dispatcher.dispatch("/gscore/physics", ["enable", 1])
	if _f == 16:
		var ball = osc.registry.get_object("dropball")
		check(osc.spatial.colliding_others(ball.physics_adapter.body) != null, "colliding_others callable")
	if _f == 36:
		var ball = osc.registry.get_object("dropball")
		var cb = ball.event_bindings.get("collisionStay")
		check(cb != null, "collisionStay binding registered")
		check(cb != null and cb._last_emit_other.has("floor"), "collisionStay emitted for the resting contact")
```

Change DONE to:
```gdscript
	if _f == 40:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
```

- [ ] **Step 2: Run to verify it fails**

Expected: error on `osc.spatial.colliding_others` (method missing) / `FAIL: collisionStay emitted for the resting contact`.

- [ ] **Step 3: Add `colliding_others` to both backends** — `GScoreSpatial2D.gd`:

```gdscript
func colliding_others(node: Node) -> Array:
	if node is RigidBody2D:
		return (node as RigidBody2D).get_colliding_bodies()
	return []
```

`GScoreSpatial3D.gd`:

```gdscript
func colliding_others(node: Node) -> Array:
	if node is RigidBody3D:
		return (node as RigidBody3D).get_colliding_bodies()
	return []
```

- [ ] **Step 4: Add the `collisionStay` block to `check_continuous`** — in `GScoreCollisionEvents.gd`, after the `areaStay` block (still inside `check_continuous`):

```gdscript
	var cb = obj.event_bindings.get("collisionStay")
	if cb != null:
		var c_active := {}
		for other in ctx.spatial.colliding_others(node):
			if not is_instance_valid(other):
				continue
			var cdata := _build_data(ctx, obj, "collisionStay", other)
			var coid := str(cdata["other"])
			c_active[coid] = true
			if cb.should_emit_other(cdata["intensity"], cdata["time"], coid, cdata["layer"]):
				cb.mark_other(coid, cdata["time"])
				ctx.emitter.emit(cb.target, cb.build_args(cdata), cb.mode, cb.quantize_grid)
		cb.prune_others(c_active)
```

> `var cb = obj.event_bindings.get(...)` untyped (Variant); `var cdata := _build_data(...)` infers Dictionary. Mirrors the `areaStay` block exactly, with `colliding_others` instead of `overlapping_others`.

- [ ] **Step 5: Run to verify it passes**

Run `test_events.gd`. Expected: `PASS: colliding_others callable`, `PASS: collisionStay binding registered`, `PASS: collisionStay emitted for the resting contact`, `DONE pass=...  fail=0`.

If `collisionStay emitted...` fails: the ball isn't registering contact. Confirm gravity is enabled, physics is on, and the ball/floor colliders touch (ball center -0.18, radius 0.08 → bottom -0.26; floor collider top -0.25, i.e. floor center -0.3 + half-height 0.05 → they overlap ~0.01 and rest in contact). If needed, nudge the ball lower (e.g. -0.19) or raise the assert frame (f36 → f48) — but do not weaken the assertion.

- [ ] **Step 6: Commit**

```bash
git add addons/gscore_osc/physics/GScoreCollisionEvents.gd addons/gscore_osc/core/GScoreSpatial2D.gd addons/gscore_osc/core/GScoreSpatial3D.gd tools/test_events.gd
git commit -m "feat(events): collisionStay continuous-contact events"
```

---

## Task 4: 2D verification, tutorial, CHANGELOG 0.5.0, version, CI

**Files:** Modify `TUTORIAL.md`, `CHANGELOG.md`, `addons/gscore_osc/plugin.cfg`, `addons/gscore_osc/core/OscDispatcher.gd`, `.github/workflows/ci.yml`.

- [ ] **Step 1: Verify the 2D backend** — create `override.cfg` at repo root:
```
[gscore_osc]
space="2d"
```
Kill stray Godot, run `… --script res://tools/test_events.gd`, confirm `ready (space=2d)` and `fail=0`, then `rm override.cfg` (it's gitignored; confirm it's gone and untracked). If a 2D assertion fails it's a real 2D bug (likely `colliding_others`/`layer_names_for`) — diagnose, fix minimally, re-run, and report. (Expectation: passes unchanged, like 3D.)

- [ ] **Step 2: Add a tutorial note** — in `TUTORIAL.md`, after the "Sensors & trigger zones" section, add (real markdown, not wrapped):

```markdown
### Event modes, filters & continuous contacts

Every physics/area event binding accepts gating options and an emission `mode`:

```
s("/gscore/scene/ball/on", "collisionEnter", "/synth/hit", "minIntensity", 0.2, "cooldown", 0.05)
s("/gscore/scene/ball/on", "collisionStay",  "/synth/sustain", "maxRate", 30)   # per-contact, per body
s("/gscore/scene/ball/on", "collisionEnter", "/synth/hit", "layer", "percussion")  # only when the other body is on layer "percussion" (name or number)
s("/gscore/scene/ball/on", "collisionEnter", "/synth/hit", "mode", "quantized", "quantizeGrid", 0.5)
```

- `collisionStay` reports each body currently touching this rigid body, every frame, throttled per body (like `areaStay` for contacts).
- `layer <name|number>` only fires when the other body is on that collision layer (name registered via `/gscore/physics/layer <n> <name>`, or the bit number).
- `mode`: `immediate` (default) sends at once; `queued` flushes at end of frame; `bundle` sends the frame's events as one OSC bundle; `quantized` holds the event until the next transport beat (grid via `quantizeGrid <beats>`, default 1) — requires the transport to be playing.
```

Re-read the section and confirm fences/lists render and match surrounding style. Add a TOC entry if the document lists one.

- [ ] **Step 3: CHANGELOG `[0.5.0]`** — add above `[0.4.0]` in `CHANGELOG.md`:

```markdown
## [0.5.0] — 2026-06-30

### Added
- **Event-system completion** (spec §19): `collisionStay` continuous-contact events (per-body
  throttled, mirroring `areaStay`); a functional `layer` event filter (matches the other body's
  collision-layer name or number); and the `mode` option — `queued`, `bundle` (one OSC bundle per
  frame), and `quantized` (snapped to the next transport beat via `quantizeGrid`) — via a new
  per-frame emission scheduler. `positionEnter`/`positionExit` were intentionally dropped (redundant
  with area zones and `yAbove`/`yBelow`).
```

- [ ] **Step 4: Version bump** — set `version="0.5.0"` in `addons/gscore_osc/plugin.cfg`, and update the three `"0.4.0"` strings in `addons/gscore_osc/core/OscDispatcher.gd` (grep `0.4.0` for all three) to `"0.5.0"`.

- [ ] **Step 5: CI** — in `.github/workflows/ci.yml`, after the sensor-zones self-test step, add (mirror the existing `./godot` style):

```yaml
      - name: Self-tests — event system
        run: |
          ./godot --headless --path . --script res://tools/test_events.gd 2>&1 | tee events.log
          grep -q "fail=0" events.log && ! grep -q "FAIL:" events.log
```

- [ ] **Step 6: Final verification (both spaces + boot + regressions)**

```
# 3D event tests
"<godot>" --headless --path . --script res://tools/test_events.gd      # expect fail=0
# 2D event tests
printf '[gscore_osc]\nspace="2d"\n' > override.cfg
"<godot>" --headless --path . --script res://tools/test_events.gd      # expect ready (space=2d), fail=0
rm override.cfg
# regressions
"<godot>" --headless --path . --script res://tools/test_zones.gd       # expect fail=0
"<godot>" --headless --path . --script res://tools/test_joints.gd      # expect fail=0
# boot
"<godot>" --headless --path . --quit-after 250                          # ready (space=3d), no SCRIPT ERROR/Parse Error
```
(kill stray Godot before each run). Confirm `git status` clean (no `override.cfg`).

- [ ] **Step 7: Commit**

```bash
git add TUTORIAL.md CHANGELOG.md addons/gscore_osc/plugin.cfg addons/gscore_osc/core/OscDispatcher.gd .github/workflows/ci.yml
git commit -m "docs(events): tutorial + changelog 0.5.0 + CI event self-test"
```

---

## Self-review notes (for the implementer)

- Switching the emission sites to `ctx.emitter.emit` must preserve immediate-mode behavior exactly — the Task 2 regression run of `test_zones.gd` guards this.
- `colliding_others`/`layer_names_for` mirror `overlapping_others`/`is_area`; keep them next to those in each backend.
- `collisionStay` only fires for rigid bodies with contacts while simulating; the test enables physics + gravity and lets the ball settle.
- Do NOT commit `override.cfg`. Do NOT modify `GScoreEvents`/`OscDispatcher` routing (only the version strings in `OscDispatcher`).
