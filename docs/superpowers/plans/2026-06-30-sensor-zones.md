# Sensors & Trigger Zones — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `areaStay` continuous presence events (per-body throttled) and literal payload constants to the MusicScene area/event system, completing spec §12.

**Architecture:** Reuse the existing per-frame continuous-event path (`MSCollisionEvents.check_continuous`) and the existing event-binding option machinery. Five small, focused changes: literal handling in `build_args`; other-centric fields in `_build_data`; a per-body throttle on `MSEventBinding`; an `areaStay` emitter in `check_continuous` plus two backend helpers; then docs/CI. `areaStay`/`payload` registration already works through the generic event-binding path — no dispatcher/handler changes.

**Tech Stack:** Godot 4.7, GDScript. Tests are headless SceneTree scripts run via `godot --headless --path . --script res://tools/<t>.gd`, printing `PASS:`/`FAIL:`. Some checks are pure unit tests on `MSEventBinding`/`MSCollisionEvents` (preloaded directly); others drive the live `MusicSceneOSC` autoload.

**Engine binary:** `D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`

---

## Background the engineer needs

- **Run a test:** `"D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://tools/test_zones.gd`. Before each run, free the UDP port: `powershell -Command "Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } | Stop-Process -Force -ErrorAction SilentlyContinue"`. AV may lock git objects — retry `git add`/`commit` on failure.
- **GDScript 4.7 gotchas:** `:=` cannot infer a type from an untyped value (anything off `ctx`/`obj`/a Variant `.get()`); use explicit `var x: T = ...` or untyped `var x = ...`. Use `str(v)` not `String(v)` to coerce a Variant to String.
- **`MSEventBinding`** (`addons/musicscene/events/MSEventBinding.gd`) is a `RefCounted` holding one event binding: `event`, `target`, `min_intensity`, `cooldown`, `max_rate`, `layer_filter`, `other_filter`, `payload` (field-name list; empty → `DEFAULT_FIELDS`), `_last_emit`, `state`. `should_emit(intensity, now, other_id, layer)`, `mark(now)`, `build_args(data)`, `_match(other_id)`.
- **`MSCollisionEvents`** (`addons/musicscene/physics/MSCollisionEvents.gd`) is a class of `static` funcs. `emit(ctx, obj, event, other)` handles discrete callbacks; `check_continuous(ctx, obj)` runs each physics frame (from `MSPhysicsAdapter.physics_step`, which runs while `ctx.physics_world.is_simulating()`); `_build_data(ctx, obj, event, other) -> Dictionary` builds the canonical event-data dict (keys are lowercase: `self`, `other`, `x`, `y`, `z`, `vx`, `vy`, `speed`, `intensity`, `time`, `layer`, …).
- **Spatial backends** (`addons/musicscene/core/MSSpatial2D.gd` / `MSSpatial3D.gd`) already expose `body_global_position`, `body_get_velocity`, `point_to_norm(p, mode)`, `vector_to_norm(v, mode)` used by `_build_data` — reuse them dimension-agnostically.
- **Registration already works:** `/ms/scene/zoneA/on areaStay /zone/presence maxRate 20` lands in `obj.event_bindings["areaStay"]` (not an input event) with `max_rate=20`; `/ms/scene/zoneA/payload areaStay …` sets that binding's `payload`. Do NOT modify `MSEvents` or `OscDispatcher`.

## File structure

| File | Change |
|---|---|
| `addons/musicscene/events/MSEventBinding.gd` | literal handling in `build_args`; `_last_emit_other` + `should_emit_other`/`mark_other`/`prune_others`; `_passes_filters` refactor |
| `addons/musicscene/physics/MSCollisionEvents.gd` | other-centric fields in `_build_data`; `areaStay` block in `check_continuous` |
| `addons/musicscene/core/MSSpatial2D.gd` + `MSSpatial3D.gd` | `is_area`, `overlapping_others` |
| `tools/test_zones.gd` | new headless test (built up across tasks) |
| `TUTORIAL.md`, `CHANGELOG.md`, `addons/musicscene/plugin.cfg`, `.github/workflows/ci.yml` | docs, version, CI |

---

## Task 1: Literal payload tags in `build_args`

**Files:** Modify `addons/musicscene/events/MSEventBinding.gd`. Test: `tools/test_zones.gd`.

- [ ] **Step 1: Write the failing test** — create `tools/test_zones.gd`:

```gdscript
extends SceneTree
## Headless sensor/zone tests. Run:
##   <godot> --headless --path . --script res://tools/test_zones.gd
## Space-aware (run once per space). Mixes unit checks (preloaded classes) with
## integration checks (live MusicSceneOSC autoload).
const EB := preload("res://addons/musicscene/events/MSEventBinding.gd")
const CE := preload("res://addons/musicscene/physics/MSCollisionEvents.gd")
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
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 2:
		var b = EB.new()
		b.payload = ["self", "other", "=A"]
		var out = b.build_args({"self": "zoneA", "other": "note17"})
		check(out == ["zoneA", "note17", "A"], "literal =A in payload -> 'A'")
		var b2 = EB.new()
		b2.payload = ["self", "'B", "missingfield"]
		var out2 = b2.build_args({"self": "z"})
		check(out2 == ["z", "B", 0], "literal 'B passes through; unknown field -> 0")
	if _f == 5:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run to verify it fails**

Run: `"D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://tools/test_zones.gd`
Expected: `FAIL: literal =A in payload -> 'A'` (build_args treats `=A` as an unknown field → `0`).

- [ ] **Step 3: Implement literal handling** — replace `build_args` in `MSEventBinding.gd`:

```gdscript
func build_args(data: Dictionary) -> Array:
	var fields: Array = payload if not payload.is_empty() else DEFAULT_FIELDS
	var out: Array = []
	for f in fields:
		var s := str(f)
		if s.begins_with("'") or s.begins_with("="):
			out.append(s.substr(1))             # literal string (case preserved)
		else:
			var key := s.to_lower()
			out.append(data[key] if data.has(key) else 0)
	return out
```

- [ ] **Step 4: Run to verify it passes**

Run the same command. Expected: `PASS: literal =A in payload -> 'A'`, `PASS: literal 'B passes through; unknown field -> 0`, `DONE pass=2 fail=0`.

- [ ] **Step 5: Commit**

```bash
git add addons/musicscene/events/MSEventBinding.gd tools/test_zones.gd
git commit -m "feat(zones): literal constant payload tags ('A / =A)"
```

---

## Task 2: Other-centric fields in `_build_data`

**Files:** Modify `addons/musicscene/physics/MSCollisionEvents.gd`. Test: `tools/test_zones.gd`.

- [ ] **Step 1: Add the failing test** — extend `tools/test_zones.gd`. Add a helper and an assertion block. Add this helper method (top-level on the script):

```gdscript
func _make_zone_and_body(osc) -> void:
	osc.dispatcher.dispatch("/ms/scene/zoneA", ["new", "circle"])
	osc.dispatcher.dispatch("/ms/scene/zoneA/physics", ["enable", "area"])
	osc.dispatcher.dispatch("/ms/scene/zoneA/collider", ["circle", 0.3])
	osc.dispatcher.dispatch("/ms/scene/zoneA", ["pos", 0.0, 0.0, 0.0])
	osc.dispatcher.dispatch("/ms/scene/ball", ["new", "circle"])
	osc.dispatcher.dispatch("/ms/scene/ball/physics", ["enable", "rigid"])
	osc.dispatcher.dispatch("/ms/scene/ball/collider", ["circle", 0.05])
	osc.dispatcher.dispatch("/ms/scene/ball", ["pos", 0.1, 0.0, 0.0])
```

Insert these frame blocks (and bump DONE to `_f == 8`):

```gdscript
	if _f == 4:
		_make_zone_and_body(osc)
	if _f == 6:
		var zone = osc.registry.get_object("zoneA")
		var body = osc.registry.get_object("ball")
		var bnode = body.physics_adapter.body
		var data = CE._build_data(osc, zone, "areaStay", bnode)
		check(data.has("otherx") and data.has("otherspeed"), "data has other-centric fields")
		check(str(data["other"]) == "ball", "data.other resolves to 'ball'")
		check(absf(float(data["otherx"]) - 0.1) < 0.05, "data.otherx ~= ball normalized x (0.1)")
```

Change the existing DONE block from `if _f == 5:` to:
```gdscript
	if _f == 8:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
```

- [ ] **Step 2: Run to verify it fails**

Expected: `FAIL: data has other-centric fields` (the keys don't exist yet).

- [ ] **Step 3: Implement other-centric fields** — in `MSCollisionEvents._build_data`, replace the `if other != null:` block with:

```gdscript
	var other_id := ""
	var other_w = pos_w
	var other_norm := Vector3.ZERO
	var other_vel_norm := Vector3.ZERO
	if other != null:
		other_id = ctx.registry.id_for_node(other)
		if other_id == "":
			other_id = str(other.name)
		other_w = sp.body_global_position(other)
		other_norm = sp.point_to_norm(other_w, pmode)
		other_vel_norm = sp.vector_to_norm(sp.body_get_velocity(other), pmode)
```

Then add these keys to the returned dictionary (alongside the existing `"vx"`/`"vy"` etc. — place them before `"time"`):

```gdscript
		"otherx": other_norm.x, "othery": other_norm.y, "otherz": other_norm.z,
		"othervx": other_vel_norm.x, "othervy": other_vel_norm.y, "othervz": other_vel_norm.z,
		"otherspeed": other_vel_norm.length(),
```

> `point_to_norm` and `vector_to_norm` already return `Vector3` in both backends; `body_get_velocity` returns the backend's native vector and `vector_to_norm` normalizes it. For a non-rigid `other`, `body_get_velocity` returns zero.

- [ ] **Step 4: Run to verify it passes**

Expected: `PASS: data has other-centric fields`, `PASS: data.other resolves to 'ball'`, `PASS: data.otherx ~= ball normalized x (0.1)`, `DONE pass=5 fail=0`.

- [ ] **Step 5: Commit**

```bash
git add addons/musicscene/physics/MSCollisionEvents.gd tools/test_zones.gd
git commit -m "feat(zones): other-centric data fields (otherx/othery/otherspeed...)"
```

---

## Task 3: Per-body throttle on `MSEventBinding`

**Files:** Modify `addons/musicscene/events/MSEventBinding.gd`. Test: `tools/test_zones.gd`.

- [ ] **Step 1: Add the failing test** — insert before the DONE block (bump DONE to `_f == 11`):

```gdscript
	if _f == 9:
		var b = EB.new()
		b.max_rate = 20.0   # gap = 0.05s
		check(b.should_emit_other("n1", 1.0, 100.0, ""), "n1 first emit allowed")
		b.mark_other("n1", 100.0)
		check(not b.should_emit_other("n1", 1.0, 100.01, ""), "n1 throttled within gap")
		check(b.should_emit_other("n2", 1.0, 100.01, ""), "n2 has its own timer")
		check(b.should_emit_other("n1", 1.0, 100.10, ""), "n1 allowed after gap")
		b.mark_other("n1", 100.0); b.mark_other("n2", 100.0)
		b.prune_others({"n1": true})
		check(b._last_emit_other.has("n1") and not b._last_emit_other.has("n2"), "prune drops absent bodies")
```

Change DONE block to:
```gdscript
	if _f == 11:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
```

- [ ] **Step 2: Run to verify it fails**

Expected: a parse error or `FAIL` on `should_emit_other` (method doesn't exist).

- [ ] **Step 3: Implement the per-body throttle** — in `MSEventBinding.gd`:

Add the member (near `var _last_emit: float = -1.0`):
```gdscript
var _last_emit_other: Dictionary = {}     # other_id -> last emit time (seconds)
```

Refactor the shared filter checks out of `should_emit` and add the per-other variants. Replace the existing `should_emit` with:

```gdscript
func _passes_filters(intensity: float, other_id: String, layer: String) -> bool:
	if intensity < min_intensity:
		return false
	if other_filter != "" and not _match(other_id):
		return false
	if layer_filter != "" and layer != layer_filter:
		return false
	return true


func should_emit(intensity: float, now: float, other_id: String, layer: String) -> bool:
	if not _passes_filters(intensity, other_id, layer):
		return false
	var gap := 0.0
	if cooldown > 0.0:
		gap = cooldown
	if max_rate > 0.0:
		gap = maxf(gap, 1.0 / max_rate)
	if gap > 0.0 and _last_emit >= 0.0 and (now - _last_emit) < gap:
		return false
	return true


func should_emit_other(other_id: String, intensity: float, now: float, layer: String) -> bool:
	if not _passes_filters(intensity, other_id, layer):
		return false
	var gap := 0.0
	if cooldown > 0.0:
		gap = cooldown
	if max_rate > 0.0:
		gap = maxf(gap, 1.0 / max_rate)
	var last: float = _last_emit_other.get(other_id, -1.0)
	if gap > 0.0 and last >= 0.0 and (now - last) < gap:
		return false
	return true


func mark_other(other_id: String, now: float) -> void:
	_last_emit_other[other_id] = now


func prune_others(active: Dictionary) -> void:
	for k in _last_emit_other.keys():
		if not active.has(k):
			_last_emit_other.erase(k)
```

> `Dictionary.keys()` returns a fresh array, so erasing during the `prune_others` loop is safe.

- [ ] **Step 4: Run to verify it passes**

Expected: the four `should_emit_other` checks + `prune drops absent bodies` PASS, `DONE pass=9 fail=0`.

- [ ] **Step 5: Commit**

```bash
git add addons/musicscene/events/MSEventBinding.gd tools/test_zones.gd
git commit -m "feat(zones): per-body maxRate throttle on event bindings"
```

---

## Task 4: `areaStay` emitter + backend `is_area`/`overlapping_others`

**Files:** Modify `addons/musicscene/physics/MSCollisionEvents.gd`, `addons/musicscene/core/MSSpatial2D.gd`, `addons/musicscene/core/MSSpatial3D.gd`. Test: `tools/test_zones.gd`.

- [ ] **Step 1: Add the failing test** — insert these blocks before DONE (bump DONE to `_f == 30`). This enables physics, registers an `areaStay` binding, and asserts the binding accrues a per-body timer for the contained body, then that it's pruned when the body leaves:

```gdscript
	if _f == 13:
		osc.dispatcher.dispatch("/ms/physics", ["enable", 1])
		osc.dispatcher.dispatch("/ms/scene/zoneA/on", ["areaStay", "/zone/presence", "maxRate", 20])
	if _f == 14:
		var zone = osc.registry.get_object("zoneA")
		check(osc.spatial.is_area(zone.node), "zone node is an area")
		check(osc.spatial.overlapping_others(zone.node).size() >= 1, "zone overlaps the ball")
	if _f == 20:
		var zone = osc.registry.get_object("zoneA")
		var b = zone.event_bindings.get("areaStay")
		check(b != null, "areaStay binding registered")
		check(b != null and b._last_emit_other.has("ball"), "areaStay emitted for contained body (per-body timer set)")
	if _f == 22:
		osc.dispatcher.dispatch("/ms/scene/ball", ["pos", 0.9, 0.0, 0.0])  # move ball out of the zone
	if _f == 28:
		var zone = osc.registry.get_object("zoneA")
		var b = zone.event_bindings.get("areaStay")
		check(b != null and not b._last_emit_other.has("ball"), "left body's per-body timer is pruned")
```

Change DONE block to:
```gdscript
	if _f == 30:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
```

- [ ] **Step 2: Run to verify it fails**

Expected: `FAIL` (or parse error) on `osc.spatial.is_area` — the method doesn't exist yet.

- [ ] **Step 3: Add backend helpers** — append to the Joints/Physics area of `MSSpatial2D.gd`:

```gdscript
func is_area(node: Node) -> bool:
	return node is Area2D


func overlapping_others(node: Node) -> Array:
	if node is Area2D:
		var out: Array = []
		out.append_array((node as Area2D).get_overlapping_bodies())
		out.append_array((node as Area2D).get_overlapping_areas())
		return out
	return []
```

And the 3D analog in `MSSpatial3D.gd`:

```gdscript
func is_area(node: Node) -> bool:
	return node is Area3D


func overlapping_others(node: Node) -> Array:
	if node is Area3D:
		var out: Array = []
		out.append_array((node as Area3D).get_overlapping_bodies())
		out.append_array((node as Area3D).get_overlapping_areas())
		return out
	return []
```

- [ ] **Step 4: Add the `areaStay` block to `check_continuous`** — in `MSCollisionEvents.gd`, after the existing `for event in ["velocityAbove", ...]` loop (still inside `check_continuous`), add:

```gdscript
	var sb = obj.event_bindings.get("areaStay")
	if sb != null and ctx.spatial.is_area(node):
		var active := {}
		for other in ctx.spatial.overlapping_others(node):
			var odata := _build_data(ctx, obj, "areaStay", other)
			var oid := str(odata["other"])
			active[oid] = true
			if sb.should_emit_other(oid, odata["intensity"], odata["time"], odata["layer"]):
				sb.mark_other(oid, odata["time"])
				ctx.send_event(sb.target, sb.build_args(odata))
		sb.prune_others(active)
```

> `var odata := _build_data(...)` infers `Dictionary` (the function is typed `-> Dictionary`); `var sb = obj.event_bindings.get(...)` is untyped because `.get()` returns a Variant. Continuous events emit only to their bound target (no canonical `/ms/event/physics` mirror), so the per-body `maxRate` actually bounds traffic.

- [ ] **Step 5: Run to verify it passes**

Run the test. Expected (default 3D space): `PASS: zone node is an area`, `PASS: zone overlaps the ball`, `PASS: areaStay binding registered`, `PASS: areaStay emitted for contained body (per-body timer set)`, `PASS: left body's per-body timer is pruned`, `DONE pass=14 fail=0`.

If `zone overlaps the ball` fails, the ball/zone colliders aren't overlapping — confirm both got colliders and physics is on default layer 1 (no layer/mask commands were sent, so defaults apply). If `per-body timer set` fails but overlap passed, confirm `check_continuous` runs (physics was enabled at f13) and the `areaStay` block is inside `check_continuous`.

- [ ] **Step 6: Commit**

```bash
git add addons/musicscene/physics/MSCollisionEvents.gd addons/musicscene/core/MSSpatial2D.gd addons/musicscene/core/MSSpatial3D.gd tools/test_zones.gd
git commit -m "feat(zones): areaStay continuous presence emitter + backend area helpers"
```

---

## Task 5: 2D verification, tutorial, CHANGELOG, version, CI, final checks

**Files:** Modify `TUTORIAL.md`, `CHANGELOG.md`, `addons/musicscene/plugin.cfg`, `addons/musicscene/core/OscDispatcher.gd`, `.github/workflows/ci.yml`.

- [ ] **Step 1: Verify the 2D backend** — Godot reads a root `override.cfg` to override settings. Create `override.cfg` at the repo root containing:
```
[MusicScene]
space="2d"
```
Then: kill stray Godot, run `… --script res://tools/test_zones.gd`, confirm `ready (space=2d)` and `fail=0`. Then **delete `override.cfg`** (`rm override.cfg`; it is gitignored from the joints work — confirm it is not tracked and not left in the tree). If a 2D assertion fails, it is a real 2D bug (likely `is_area`/`overlapping_others` or a coordinate issue) — diagnose, fix the 2D production code minimally, re-run, and note it.

- [ ] **Step 2: Add a tutorial section** — in `TUTORIAL.md`, add a "Sensors & trigger zones" section after the physics/joints material (match the file's heading level and the `s("/address", "verb", …)` notation). Insert this content (as real markdown, not wrapped in an outer fence):

```markdown
## Sensors & trigger zones

An **area** is a sensor: it reports when bodies enter, leave, or stay inside it — ideal for form
sections, presence, and spatial triggers.

```
s("/ms/scene/zoneA", "new", "rect")
s("/ms/scene/zoneA/physics", "enable", "area")
s("/ms/scene/zoneA/collider", "rect", 0.4, 0.3)

s("/ms/scene/zoneA/on", "areaEnter", "/form/section")
s("/ms/scene/zoneA/on", "areaExit",  "/form/leave")
```

Enter/exit fire as bodies cross the boundary. Add a **constant tag** to the payload with a `=` (or `'`)
prefix — handy for labelling which section fired:

```
s("/ms/scene/zoneA/payload", "areaEnter", "self", "other", "=A")
# -> /form/section zoneA note17 A
```

### Continuous presence — `areaStay`

`areaStay` reports each body **currently inside** the zone, every physics frame, throttled
**per body** by `maxRate` (Hz):

```
s("/ms/scene/zoneA/on", "areaStay", "/zone/presence", "maxRate", 20)
s("/ms/scene/zoneA/payload", "areaStay", "self", "other", "otherx", "othery", "otherspeed")
s("/ms/physics", "enable", 1)
# -> /zone/presence zoneA note17 0.12 -0.03 0.4   (~20 Hz per contained body)
```

Use the `other*` payload fields (`otherx`, `othery`, `otherz`, `othervx`, `othervy`, `othervz`,
`otherspeed`) to report where each contained body is and how fast it's moving — `x`/`y`/`speed`
describe the zone itself. Filters apply per body: `other <id|prefix*>` and `layer <name>` restrict
which bodies stream.

> `areaStay` runs while the simulation is on (`/ms/physics enable 1`); enter/exit fire
> independently. Constants live in `payload` (the `on` command's trailing tokens are option pairs).
```

- [ ] **Step 2b: Verify the tutorial fences** — re-read the section; confirm the nested code fences and the inline `=A`/`other*` references render and match surrounding style.

- [ ] **Step 3: CHANGELOG `[0.4.0]`** — add above the `[0.3.0]` entry in `CHANGELOG.md`:

```markdown
## [0.4.0] — 2026-06-30

### Added
- **Sensors & trigger zones** (spec §12): `areaStay` continuous presence events, emitted per physics
  frame for each body inside an area and throttled **per body** by `maxRate`. New other-centric
  payload fields (`otherx/othery/otherz/othervx/othervy/othervz/otherspeed`) report each contained
  body's position and velocity. Event payloads can now carry **literal constants** via a `'`/`=`
  prefix (e.g. `payload areaEnter self other =A`). Area enter/exit, filters and rate-limiting were
  already supported.
```

- [ ] **Step 4: Version bump** — set `version="0.4.0"` in `addons/musicscene/plugin.cfg`, and update the three `"0.3.0"` version strings in `addons/musicscene/core/OscDispatcher.gd` (grep `0.3.0` to find all three) to `"0.4.0"`.

- [ ] **Step 5: CI** — in `.github/workflows/ci.yml`, after the joints self-test step, add a `test_zones.gd` step mirroring the existing style (same `./godot` invocation):

```yaml
      - name: Self-tests — sensor zones
        run: |
          ./godot --headless --path . --script res://tools/test_zones.gd 2>&1 | tee zones.log
          grep -q "fail=0" zones.log && ! grep -q "FAIL:" zones.log
```

- [ ] **Step 6: Final verification (both spaces + boot)**

3D: kill stray Godot, run `… --script res://tools/test_zones.gd` → `fail=0`.
2D: `printf '[MusicScene]\nspace="2d"\n' > override.cfg`, kill stray Godot, run → `ready (space=2d)`, `fail=0`, then `rm override.cfg`.
Boot: kill stray Godot, run `… --headless --path . --quit-after 250` → `ready (space=3d)`, no `SCRIPT ERROR`/`Parse Error`.
Confirm `git status` clean (no `override.cfg`).

- [ ] **Step 7: Commit**

```bash
git add TUTORIAL.md CHANGELOG.md addons/musicscene/plugin.cfg addons/musicscene/core/OscDispatcher.gd .github/workflows/ci.yml
git commit -m "docs(zones): tutorial + changelog 0.4.0 + CI zone self-test"
```

---

## Self-review notes (for the implementer)

- The only Godot-API risk is `Area2D/Area3D.get_overlapping_bodies()`/`get_overlapping_areas()` (stable in 4.7) and that an area needs `monitoring` on (already set by `make_body("area")`) plus a collider (the test adds one).
- `_build_data` is `static` — call it as `CE._build_data(osc, zone, "areaStay", bnode)` in tests.
- Do NOT commit `override.cfg`.
- `areaStay`/`payload` registration needs no `MSEvents`/`OscDispatcher` change — if you find yourself editing those, stop and re-read §2 of the spec.
