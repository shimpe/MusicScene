# Collision Reactors (Bouncers & Portals) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two Area-based collision reactors to MusicScene — **bouncers** (mirror-reflect a colliding body's velocity + add an outward impulse) and **portals** (teleport a colliding body to a random linked partner) — working in both 2D and 3D, plus a rich generative pinball SuperCollider example.

**Architecture:** Reactors are `Area2D/3D` sensor objects (like zones). A new manager `MSReactors` stores per-object config and does the reflect/teleport work; it is invoked from the existing collision hook `MSPhysicsAdapter._on_area_enter`, dispatching on `MSObject.type_hint`. All geometry/actuation is done in **world space** through `ctx.spatial` (dimension-agnostic).

**Tech Stack:** Godot 4.7 GDScript (TAB indentation), OSC over UDP, headless `SceneTree` self-tests, SuperCollider for the example.

**Conventions (apply to every task):**
- GDScript uses **TAB** indentation. Every new `.gd` file needs a committed `.gd.uid` sidecar — generate it with `"/d/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --import --path .`
- Run a headless test with: `timeout 90 "/d/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --headless --path . --script res://tools/<name>.gd` — success line is exactly `DONE pass=N fail=0` and no line starting with `FAIL:`.
- Tests must pass in **both** spaces. Default `ms/space` is `3d`. To run a test in 2D, temporarily set the project setting, OR (preferred, no file mutation) the test itself is written space-agnostically and is run once as-is (3d) in CI; where a task's test is space-sensitive it is noted.
- Commit message trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Do **not** touch or commit any unrelated working-tree files.

---

## File Structure

| File | Responsibility |
|---|---|
| `addons/musicscene/physics/MSReactors.gd` (new) | The reactor manager: per-id config (bouncer params, portal links), `configure_bouncer`/`configure_portal`, `on_contact` dispatch, `_bounce`, `_teleport`, portal cooldown. |
| `addons/musicscene/core/MSSpatial2D.gd` / `MSSpatial3D.gd` | Add `body_set_velocity_world`, `is_dynamic`, `reactor_normal`, and `"bouncer"`/`"portal"` cases in `create_primitive`. |
| `addons/musicscene/core/MSFactory.gd` | Register `bouncer`/`portal` in `BUILTIN_TYPES`. |
| `addons/musicscene/core/MSRegistry.gd` | Auto-enable the area adapter for a newly-created bouncer/portal. |
| `addons/musicscene/physics/MSPhysicsAdapter.gd` | Call `ctx.reactors.on_contact(obj, other)` from `_on_area_enter`. |
| `addons/musicscene/core/OscDispatcher.gd` | Route `/ms/scene/<id>/bouncer` and `/portal` subsystems; bump version. |
| `addons/musicscene/nodes/MSRoot.gd` | Construct `ctx.reactors`. |
| `tools/test_bouncers.gd`, `tools/test_portals.gd` (new) | Headless behavior tests. |
| `.github/workflows/ci.yml` | Run the two new tests. |
| `README.md`, `TUTORIAL.md`, `ADVANCED.md`, `CHANGELOG.md`, `plugin.cfg` | Docs + version 0.12.0. |
| `examples/supercollider/example_pinball.scd` (new) | Rich generative pinball example. |

---

## Task 1: New object types `new bouncer` / `new portal`

Create bouncer/portal as `Area`-based objects with a default collider and the area adapter auto-enabled, tagged via `type_hint`. No reactor behavior yet.

**Files:**
- Modify: `addons/musicscene/core/MSFactory.gd` (BUILTIN_TYPES)
- Modify: `addons/musicscene/core/MSSpatial2D.gd` (`create_primitive`)
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (`create_primitive`)
- Modify: `addons/musicscene/core/MSRegistry.gd` (`create_builtin`)
- Modify: `addons/musicscene/physics/MSPhysicsWorld.gd` (add a public `enable_area(obj)` helper)
- Create: `tools/test_bouncers.gd`, `tools/test_portals.gd`

- [ ] **Step 1: Write the failing creation tests.**

Create `tools/test_bouncers.gd`:
```gdscript
extends SceneTree
## Headless test for bouncer objects (creation now; reflection added later).
##   <godot> --headless --path . --script res://tools/test_bouncers.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 3:
		osc.dispatcher.dispatch("/ms/scene/bmp", ["new", "bouncer"])
		var obj = osc.registry.get_object("bmp")
		check(obj != null, "bouncer object created")
		check(obj != null and obj.type_hint == "bouncer", "type_hint is bouncer")
		var body = obj.physics_adapter.body if (obj != null and obj.physics_adapter != null) else null
		check(body != null and osc.ctx.spatial.is_area(body), "bouncer body is an Area (area adapter auto-enabled)")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```
Create `tools/test_portals.gd` (identical but `portal`/`prt`):
```gdscript
extends SceneTree
## Headless test for portal objects (creation now; teleport added later).
##   <godot> --headless --path . --script res://tools/test_portals.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 3:
		osc.dispatcher.dispatch("/ms/scene/prt", ["new", "portal"])
		var obj = osc.registry.get_object("prt")
		check(obj != null, "portal object created")
		check(obj != null and obj.type_hint == "portal", "type_hint is portal")
		var body = obj.physics_adapter.body if (obj != null and obj.physics_adapter != null) else null
		check(body != null and osc.ctx.spatial.is_area(body), "portal body is an Area (area adapter auto-enabled)")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```
(First confirm the exact accessors: `osc.registry.get_object(id)`, `obj.physics_adapter`, `obj.type_hint`, `osc.ctx.spatial.is_area(body)`, and how the autoload exposes `ctx`/`registry`/`dispatcher` — read `nodes/MSRoot.gd` and `tools/test_zones.gd` which already uses `osc.registry.get_object(...)` and `.physics_adapter.body`. Adjust accessor names to match if they differ, e.g. `osc.ctx` vs `osc` for spatial.)

- [ ] **Step 2: Run both tests, confirm they FAIL** (unknown type `bouncer`/`portal` → object not created).

- [ ] **Step 3: Register the types.** In `addons/musicscene/core/MSFactory.gd`, add `"bouncer", "portal"` to `BUILTIN_TYPES`.

- [ ] **Step 4: Add the primitive cases.** In BOTH `MSSpatial2D.gd` and `MSSpatial3D.gd`, inside `create_primitive`, add cases that build the SAME node as the existing `"area"` case:
```gdscript
		"bouncer", "portal":
			return _make_area_primitive(args)   # whatever the "area" case does; clone it
```
Read the existing `"area"` branch (`MSSpatial2D.gd` ~lines 224-229, `MSSpatial3D.gd` ~lines 375-380) and reproduce its node construction for these two type names (an `Area2D`/`Area3D` with a default `CollisionShape` + a small visual, exactly as `"area"` does). If the area branch is a couple of inline lines, just add `"bouncer", "portal"` to that same case's match list.

- [ ] **Step 5: Auto-enable the area adapter on creation.** In `addons/musicscene/core/MSRegistry.create_builtin`, after `obj.type_hint = type`, add:
```gdscript
	if type == "bouncer" or type == "portal":
		ctx.physics_world.enable_area(obj)
```
Add the helper to `addons/musicscene/physics/MSPhysicsWorld.gd`:
```gdscript
## Ensure this object has an active Area adapter (used by bouncers/portals at creation).
func enable_area(obj) -> void:
	_ensure_adapter(obj).enable("area")
```
(Confirm `_ensure_adapter` and `enable("area")` names against `MSPhysicsWorld.handle_object` / `MSPhysicsAdapter.enable`; the `handle_object` "enable" case already calls this path.)

- [ ] **Step 6: Generate `.uid`s, run both tests.** Run `--headless --import` (creates `tools/test_bouncers.gd.uid`, `tools/test_portals.gd.uid`; confirm no `SCRIPT ERROR`/`Parse Error`). Then run both tests — each must print `DONE pass=3 fail=0` with no `FAIL:`.

- [ ] **Step 7: Commit.**
```bash
git add addons/musicscene/core/MSFactory.gd addons/musicscene/core/MSSpatial2D.gd addons/musicscene/core/MSSpatial3D.gd addons/musicscene/core/MSRegistry.gd addons/musicscene/physics/MSPhysicsWorld.gd tools/test_bouncers.gd tools/test_bouncers.gd.uid tools/test_portals.gd tools/test_portals.gd.uid
git commit -m "feat(reactors): new bouncer/portal Area object types"
```

---

## Task 2: MSReactors manager — config, wiring, dispatch hook

Add the manager with config storage + a stubbed `on_contact`, wire it into `ctx`, route the OSC config subsystems, and call it from the collision hook. Still no reflect/teleport math (that's Tasks 3-4) — but config must round-trip and the hook must fire.

**Files:**
- Create: `addons/musicscene/physics/MSReactors.gd`
- Modify: `addons/musicscene/nodes/MSRoot.gd` (construct `ctx.reactors`)
- Modify: `addons/musicscene/core/OscDispatcher.gd` (`_handle_scene_subsystem`: `bouncer`/`portal` cases)
- Modify: `addons/musicscene/physics/MSPhysicsAdapter.gd` (`_on_area_enter` hook)
- Modify: `tools/test_bouncers.gd`, `tools/test_portals.gd` (add config assertions)

- [ ] **Step 1: Write the manager (config + stub).** Create `addons/musicscene/physics/MSReactors.gd`:
```gdscript
extends RefCounted
## Collision reactors: bouncers (mirror-reflect + impulse) and portals (random teleport).
## Config is keyed by object id; behavior fires from MSPhysicsAdapter._on_area_enter via on_contact().

var ctx

# id -> { "strength": float, "gain": float, "min_speed": float }
var _bouncers: Dictionary = {}
# id -> Array[String] of target ids
var _portals: Dictionary = {}
# body instance id -> cooldown expiry (ms) after a teleport, to stop ping-pong
var _recent: Dictionary = {}

const PORTAL_COOLDOWN_MS := 250
const PORTAL_NUDGE := 0.02   # normalized-space exit offset along travel direction

func _init(context) -> void:
	ctx = context

func configure_bouncer(obj, args: Array) -> void:
	var cfg: Dictionary = _bouncers.get(obj.osc_id, {"strength": 0.0, "gain": 1.0, "min_speed": 0.0})
	var i := 0
	while i + 1 < args.size():
		match str(args[i]).to_lower():
			"strength": cfg["strength"] = float(args[i + 1])
			"gain": cfg["gain"] = float(args[i + 1])
			"minspeed": cfg["min_speed"] = float(args[i + 1])
		i += 2
	_bouncers[obj.osc_id] = cfg

func configure_portal(obj, args: Array) -> void:
	var cmd := str(args[0]).to_lower() if args.size() > 0 else ""
	match cmd:
		"link":
			var ids: Array = []
			for j in range(1, args.size()):
				ids.append(str(args[j]))
			_portals[obj.osc_id] = ids
		"unlink":
			_portals.erase(obj.osc_id)
		_:
			ctx.error("bad_arguments", "/ms/scene/" + obj.osc_id + "/portal", "Expected link|unlink")

func on_contact(obj, other: Node) -> void:
	if not ctx.spatial.is_dynamic(other):
		return
	match obj.type_hint:
		"bouncer": _bounce(obj, other)
		"portal": _teleport(obj, other)

func _bounce(_obj, _other: Node) -> void:
	pass   # implemented in Task 3

func _teleport(_obj, _other: Node) -> void:
	pass   # implemented in Task 4
```

- [ ] **Step 2: Add the `is_dynamic` spatial helper.** In `MSSpatial2D.gd` add `func is_dynamic(node: Node) -> bool: return node is RigidBody2D`; in `MSSpatial3D.gd` add `func is_dynamic(node: Node) -> bool: return node is RigidBody3D`.

- [ ] **Step 3: Construct the manager.** In `nodes/MSRoot.gd`, where the other managers are created (near `physics_world`, `joints`, `events`), add `ctx.reactors = MSReactors.new(ctx)` with a `const MSReactors := preload("res://addons/musicscene/physics/MSReactors.gd")` at the top (match the existing preload/manager-construction style — read how `physics_world`/`events` are constructed and assigned onto `ctx`).

- [ ] **Step 4: Route the OSC subsystems.** In `core/OscDispatcher.gd` `_handle_scene_subsystem`, add:
```gdscript
		"bouncer": ctx.reactors.configure_bouncer(obj, args)
		"portal": ctx.reactors.configure_portal(obj, args)
```

- [ ] **Step 5: Fire the hook.** In `physics/MSPhysicsAdapter.gd` `_on_area_enter(other)`, after the existing `CollisionEvents.emit(ctx, obj, "areaEnter", other)`, add:
```gdscript
	if ctx.reactors != null:
		ctx.reactors.on_contact(obj, other)
```

- [ ] **Step 6: Extend the tests with config assertions.** In `tools/test_bouncers.gd`, after the creation checks (still at `_f == 3`, before printing DONE), add:
```gdscript
		osc.dispatcher.dispatch("/ms/scene/bmp/bouncer", ["strength", 3.0, "gain", 0.9])
		check(osc.ctx.reactors._bouncers.get("bmp", {}).get("strength", -1) == 3.0, "bouncer strength stored")
		check(osc.ctx.reactors._bouncers.get("bmp", {}).get("gain", -1) == 0.9, "bouncer gain stored")
```
and update the DONE count expectation to `pass=5`. In `tools/test_portals.gd`, add:
```gdscript
		osc.dispatcher.dispatch("/ms/scene/prt/portal", ["link", "a", "b"])
		check(osc.ctx.reactors._portals.get("prt", []) == ["a", "b"], "portal link stored")
```
and update to `pass=4`. (Confirm the autoload path to the manager: `osc.ctx.reactors` vs `osc.reactors` — match how the test reaches `spatial`/`registry`.)

- [ ] **Step 7: Run import + both tests.** `test_bouncers` → `DONE pass=5 fail=0`; `test_portals` → `DONE pass=4 fail=0`; no parse errors.

- [ ] **Step 8: Commit.**
```bash
git add addons/musicscene/physics/MSReactors.gd addons/musicscene/core/MSSpatial2D.gd addons/musicscene/core/MSSpatial3D.gd addons/musicscene/nodes/MSRoot.gd addons/musicscene/core/OscDispatcher.gd addons/musicscene/physics/MSPhysicsAdapter.gd tools/test_bouncers.gd tools/test_portals.gd
git commit -m "feat(reactors): manager, config commands, dispatch hook (behavior stubbed)"
```

---

## Task 3: Bouncer reflection

Implement `_bounce`: read the body velocity, compute the outward surface normal from the bouncer's shape/orientation, mirror-reflect, add the outward `strength` kick, and set the body's velocity — all in world space.

**Files:**
- Modify: `addons/musicscene/core/MSSpatial2D.gd` / `MSSpatial3D.gd` (`body_set_velocity_world`, `reactor_normal`)
- Modify: `addons/musicscene/physics/MSReactors.gd` (`_bounce`)
- Modify: `tools/test_bouncers.gd` (reflection asserts)

- [ ] **Step 1: Write failing reflection tests.** In `tools/test_bouncers.gd`, add a NEW body + a circle bouncer and assert reflection at a later frame. Replace the single `_f == 3` block structure with staged frames:
```gdscript
	if _f == 3:
		# circle bouncer at origin-ish; strength gives an outward kick
		osc.dispatcher.dispatch("/ms/scene/bmp", ["new", "bouncer"])
		osc.dispatcher.dispatch("/ms/scene/bmp/collider", ["circle", 0.15])
		osc.dispatcher.dispatch("/ms/scene/bmp", ["pos", 0.5, 0.5, 0.0])
		osc.dispatcher.dispatch("/ms/scene/bmp/bouncer", ["strength", 2.0, "gain", 1.0])
		# a ball to the LEFT of the bouncer moving RIGHT (+x) into it
		osc.dispatcher.dispatch("/ms/scene/ball", ["new", "sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/ms/scene/ball/collider", ["sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball", ["pos", 0.34, 0.5, 0.0])
		osc.dispatcher.dispatch("/ms/scene/ball/physics", ["velocity", 0.6, 0.0, 0.0])
	if _f == 4:
		_v_before = _ball_vx(osc)
		check(_v_before > 0.0, "ball moving +x before contact")
	if _f == 30:
		var vx_after = _ball_vx(osc)
		check(vx_after < 0.0, "ball x-velocity reversed by bouncer (mirror reflection)")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false

var _v_before := 0.0
func _ball_vx(osc) -> float:
	var b = osc.registry.get_object("ball")
	if b == null or b.physics_adapter == null: return 0.0
	return osc.ctx.spatial.body_get_velocity(b.physics_adapter.body).x
```
Keep the earlier creation/config `check()`s from Tasks 1-2 (adjust the final DONE `pass=` count to the new total). NOTE: give the ball enough travel; if frame 30 is too early/late for the ball to reach the bouncer at 0.6 units/s from 0.34→0.5, tune the start position/velocity/frame so it reliably makes contact (the ball must enter the bouncer's 0.15 area before frame 30). Prefer starting the ball already close (0.34 vs bouncer 0.5, radius 0.15 → contact around x≈0.35) so contact happens within a few frames.

- [ ] **Step 2: Run test, confirm the reflection assert FAILS** (`_bounce` is a stub, so vx stays positive).

- [ ] **Step 3: Add the world-space velocity setter + normal helper.** In `MSSpatial2D.gd`:
```gdscript
## Set a body's velocity directly in world/raw units (no coordinate-mode conversion).
func body_set_velocity_world(body: Node, v) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).linear_velocity = v

## Outward world-space unit normal at the contact between reactor and other.
## Circle collider -> center-to-center; box collider -> the face `other` is moving into.
func reactor_normal(reactor: Node, other: Node):
	var rpos: Vector2 = body_global_position(reactor)
	var opos: Vector2 = body_global_position(other)
	if not _reactor_is_box(reactor):
		var d: Vector2 = opos - rpos
		return d.normalized() if d.length() > 0.0 else Vector2.UP
	var v: Vector2 = body_get_velocity(other)
	if v.length() < 0.001:
		var d2: Vector2 = opos - rpos
		return d2.normalized() if d2.length() > 0.0 else Vector2.UP
	var rot: float = (reactor as Node2D).global_rotation if reactor is Node2D else 0.0
	var axes := [Vector2(cos(rot), sin(rot)), Vector2(-sin(rot), cos(rot))]
	var vhat: Vector2 = v.normalized()
	var best: Vector2 = Vector2.UP
	var bestdot: float = -1e30
	for a in axes:
		for s in [1.0, -1.0]:
			var face: Vector2 = a * s
			var d3: float = -vhat.dot(face)
			if d3 > bestdot:
				bestdot = d3; best = face
	return best

## True if the reactor's collision shape is a rectangle/box (else treat as round).
func _reactor_is_box(reactor: Node) -> bool:
	for c in reactor.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			return true
	return false
```
In `MSSpatial3D.gd` add the 3D equivalents (`RigidBody3D.linear_velocity`; `reactor_normal` using `Vector3` and the node's `global_transform.basis` columns x/y/z as the three axes; `_reactor_is_box` checks `CollisionShape3D` + `BoxShape3D`):
```gdscript
func body_set_velocity_world(body: Node, v) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).linear_velocity = v

func reactor_normal(reactor: Node, other: Node):
	var rpos: Vector3 = body_global_position(reactor)
	var opos: Vector3 = body_global_position(other)
	if not _reactor_is_box(reactor):
		var d: Vector3 = opos - rpos
		return d.normalized() if d.length() > 0.0 else Vector3.UP
	var v: Vector3 = body_get_velocity(other)
	if v.length() < 0.001:
		var d2: Vector3 = opos - rpos
		return d2.normalized() if d2.length() > 0.0 else Vector3.UP
	var b: Basis = (reactor as Node3D).global_transform.basis if reactor is Node3D else Basis.IDENTITY
	var axes := [b.x.normalized(), b.y.normalized(), b.z.normalized()]
	var vhat: Vector3 = v.normalized()
	var best: Vector3 = Vector3.UP
	var bestdot: float = -1e30
	for a in axes:
		for s in [1.0, -1.0]:
			var face: Vector3 = a * s
			var d3: float = -vhat.dot(face)
			if d3 > bestdot:
				bestdot = d3; best = face
	return best

func _reactor_is_box(reactor: Node) -> bool:
	for c in reactor.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return true
	return false
```
(If the collider is nested one level deeper than a direct child, recurse or search — check where `make_collider` attaches the `CollisionShape` relative to the Area body; adjust `_reactor_is_box` to find it.)

- [ ] **Step 4: Implement `_bounce`.** Replace the stub in `MSReactors.gd`:
```gdscript
func _bounce(obj, other: Node) -> void:
	var cfg: Dictionary = _bouncers.get(obj.osc_id, {"strength": 0.0, "gain": 1.0, "min_speed": 0.0})
	var strength: float = cfg.get("strength", 0.0)
	var gain: float = cfg.get("gain", 1.0)
	var min_speed: float = cfg.get("min_speed", 0.0)
	var v = ctx.spatial.body_get_velocity(other)
	var n = ctx.spatial.reactor_normal(obj.node, other)
	var v_ref = v - 2.0 * v.dot(n) * n     # mirror reflection
	var v_out = v_ref * gain + n * strength # + outward impulse kick
	var outward: float = v_out.dot(n)
	if outward < min_speed:                 # guarantee it leaves the bouncer
		v_out += n * (min_speed - outward)
	ctx.spatial.body_set_velocity_world(other, v_out)
```
(`obj.node` is the reactor's Godot node — confirm the accessor name on `MSObject`; it may be `obj.node`. `v`, `n`, `v_out` are `Vector2` in 2D and `Vector3` in 3D; the arithmetic is identical for both, so no per-dimension branching here.)

- [ ] **Step 5: Run the test — reflection now passes** (`DONE pass=<total> fail=0`, `ball x-velocity reversed`). If the ball tunnels through without contact, tune positions/frames so it reliably enters the area.

- [ ] **Step 6: Add a box-bouncer reflection assert.** Add a second sub-scenario (new ids `wall`/`ball2`) at a later frame: a box bouncer (`collider box 0.02 0.4` in 3D / `collider rect 0.02 0.4` in 2D — a thin vertical wall) at x=0.6, a ball to its left moving +x; assert the ball leaves with negative x-velocity (reflected off the wall's face). Update the DONE count. If 2D `collider rect` vs 3D `collider box` differ, branch on `osc.ctx.spatial` class or read the space setting; keep the assertion the same (x-velocity reversed).

- [ ] **Step 7: Commit.**
```bash
git add addons/musicscene/core/MSSpatial2D.gd addons/musicscene/core/MSSpatial3D.gd addons/musicscene/physics/MSReactors.gd tools/test_bouncers.gd
git commit -m "feat(reactors): bouncer mirror reflection + impulse kick"
```

---

## Task 4: Portal teleport

Implement `_teleport`: pick a random resolvable target, teleport the body there (preserving velocity, with an exit nudge), and set a cooldown to prevent ping-pong.

**Files:**
- Modify: `addons/musicscene/physics/MSReactors.gd` (`_teleport`)
- Modify: `tools/test_portals.gd` (teleport asserts)

- [ ] **Step 1: Write failing teleport test.** In `tools/test_portals.gd`, stage: portal A at (0.3,0.5), portal B at (0.8,0.5), `A link B`, a ball entering A; assert the ball's position jumps near B and its velocity is preserved:
```gdscript
	if _f == 3:
		osc.dispatcher.dispatch("/ms/scene/pa", ["new", "portal"])
		osc.dispatcher.dispatch("/ms/scene/pa/collider", ["circle", 0.1])
		osc.dispatcher.dispatch("/ms/scene/pa", ["pos", 0.3, 0.5, 0.0])
		osc.dispatcher.dispatch("/ms/scene/pb", ["new", "portal"])
		osc.dispatcher.dispatch("/ms/scene/pb/collider", ["circle", 0.1])
		osc.dispatcher.dispatch("/ms/scene/pb", ["pos", 0.8, 0.5, 0.0])
		osc.dispatcher.dispatch("/ms/scene/pa/portal", ["link", "pb"])
		osc.dispatcher.dispatch("/ms/scene/ball", ["new", "sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/ms/scene/ball/collider", ["sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball", ["pos", 0.2, 0.5, 0.0])
		osc.dispatcher.dispatch("/ms/scene/ball/physics", ["velocity", 0.5, 0.0, 0.0])   # heads into A
	if _f == 40:
		var b = osc.registry.get_object("ball")
		var pnorm = osc.ctx.spatial.point_to_norm(osc.ctx.spatial.body_global_position(b.physics_adapter.body), osc.ctx.mapper.physics_mode)
		check(pnorm.x > 0.6, "ball teleported across to portal B (x jumped from ~0.3 to ~0.8)")
		var vx = osc.ctx.spatial.body_get_velocity(b.physics_adapter.body).x
		check(vx > 0.0, "ball velocity preserved through the portal (+x)")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```
Keep the Task-1/2 creation+config checks; set the final `pass=` accordingly. Tune frames so the ball reaches A (from 0.2 at 0.5/s it enters A's 0.1 area around x≈0.2..0.3 quickly), and frame 40 is after the teleport.

- [ ] **Step 2: Run test, confirm teleport assert FAILS** (stub → ball stays near x≈0.3, never crosses to 0.8).

- [ ] **Step 3: Implement `_teleport`.** Replace the stub in `MSReactors.gd`:
```gdscript
func _teleport(obj, other: Node) -> void:
	var now: int = Time.get_ticks_msec()
	var bid: int = other.get_instance_id()
	# prune + cooldown check
	if _recent.has(bid):
		if now < _recent[bid]:
			return                 # just arrived somewhere; ignore to avoid ping-pong
		_recent.erase(bid)
	var targets: Array = _portals.get(obj.osc_id, [])
	var live: Array = []
	for tid in targets:
		var t = ctx.registry.get_object(tid)
		if t != null and t.node != null:
			live.append(t)
	if live.is_empty():
		return
	var dst = live[randi() % live.size()]
	var mode: String = ctx.mapper.physics_mode
	var dst_norm = ctx.spatial.point_to_norm(ctx.spatial.body_global_position(dst.node), mode)
	var v = ctx.spatial.body_get_velocity(other)
	var vnorm = ctx.spatial.vector_to_norm(v, mode)
	var vdir = vnorm.normalized() if vnorm.length() > 0.0 else Vector3.ZERO
	var target = dst_norm + vdir * PORTAL_NUDGE
	ctx.spatial.set_position(other, target.x, target.y, target.z, mode)   # velocity untouched -> preserved
	_recent[bid] = now + PORTAL_COOLDOWN_MS
```
(Confirm `t.node`/`obj.node` accessors and `ctx.mapper.physics_mode` — the latter is used in `MSCollisionEvents._build_data`. `point_to_norm`/`vector_to_norm` return `Vector3` in both dimensions; `set_position`'s z arg is ignored in 2D.)

- [ ] **Step 4: Run test — teleport passes.** Ball jumps to portal B, velocity preserved.

- [ ] **Step 5: Add a cooldown assert and a multi-target assert.** (a) Cooldown: after the teleport frame, assert the ball did NOT immediately teleport again within the cooldown window (e.g. it stays near B for a few frames rather than bouncing back). (b) Multi-target: a portal `link pb pc` with pc at (0.8,0.2); assert the ball ends near pb OR pc. Update the DONE count. Because `randi()` is nondeterministic, assert membership (`near B or near C`), not a specific one.

- [ ] **Step 6: Commit.**
```bash
git add addons/musicscene/physics/MSReactors.gd tools/test_portals.gd
git commit -m "feat(reactors): portal random teleport with cooldown + exit nudge"
```

---

## Task 5: Docs + version bump to 0.12.0

**Files:**
- Modify: `addons/musicscene/core/OscDispatcher.gd` (3× `0.11.0` → `0.12.0`)
- Modify: `addons/musicscene/plugin.cfg` (`version="0.12.0"`)
- Modify: `README.md`, `TUTORIAL.md`, `ADVANCED.md`, `CHANGELOG.md`

- [ ] **Step 1: Bump version.** In `OscDispatcher.gd` replace all three `0.11.0` with `0.12.0`; in `plugin.cfg` set `version="0.12.0"`. Confirm: `grep -n '0\.11\.0' addons/musicscene/core/OscDispatcher.gd` returns nothing; `grep -c '0\.12\.0'` returns 3.

- [ ] **Step 2: README.** Add `bouncer` and `portal` to the object-types list and a short reference block for the new commands:
```
/ms/scene/<id> new bouncer            # Area that mirror-reflects + kicks a body that enters
/ms/scene/<id>/bouncer strength <s> gain <g> minSpeed <m>
/ms/scene/<id> new portal             # Area that teleports an entering body to a random linked portal
/ms/scene/<id>/portal link <id...>    # directional targets;  portal unlink to clear
```
with a one-line note each (reflection uses an exact normal for round/box shapes; portals preserve velocity, have a re-entry cooldown, and are directional).

- [ ] **Step 3: TUTORIAL.** Add a short numbered subsection (place it after the sensors/joints material, before "Next steps") introducing bouncers and portals with `s()`-helper examples:
```python
# a bumper that kicks any ball that touches it
s("/ms/scene/bump1", "new", "bouncer")
s("/ms/scene/bump1/collider", "sphere", 0.12)
s("/ms/scene/bump1", "pos", 0.5, 0.6, 0.0)
s("/ms/scene/bump1/bouncer", "strength", 3.0)   # outward kick; gain defaults to 1.0

# two portals; a ball entering p1 pops out of p2 keeping its speed
s("/ms/scene/p1", "new", "portal"); s("/ms/scene/p1/collider", "sphere", 0.1); s("/ms/scene/p1", "pos", 0.2, 0.5, 0.0)
s("/ms/scene/p2", "new", "portal"); s("/ms/scene/p2/collider", "sphere", 0.1); s("/ms/scene/p2", "pos", 0.8, 0.5, 0.0)
s("/ms/scene/p1/portal", "link", "p2")
```
and add a bullet in "Next steps" pointing to `examples/supercollider/example_pinball.scd`.

- [ ] **Step 4: ADVANCED.** Add a "Collision reactors" section covering the mechanics + gotchas: reactors are pass-through Areas (they don't physically block; use static walls with `bounce` for containment); the normal is exact for round and box colliders (velocity-selected face, honors rotation); `strength`/`minSpeed` are in world units; portals are directional (`A link B` ≠ `B link A`), pick a target uniformly at random, preserve velocity, and use a ~250 ms re-entry cooldown; reactors still emit `areaEnter`, so `on areaEnter …` bindings drive sound/scoring.

- [ ] **Step 5: CHANGELOG.** Add a `## [0.12.0] — 2026-07-04` entry (em-dash) above `[0.11.0]`, describing bouncers, portals, and the pinball example.

- [ ] **Step 6: Verify + commit.** Run `--headless --import` (no parse errors from the version edits). Then:
```bash
git add addons/musicscene/core/OscDispatcher.gd addons/musicscene/plugin.cfg README.md TUTORIAL.md ADVANCED.md CHANGELOG.md
git commit -m "docs: bouncers & portals (0.12.0)"
```

---

## Task 6: Wire the tests into CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add two steps** after the existing OSC-output self-test steps (match the existing pattern exactly — `tee` to a log, then `grep -q "fail=0" && ! grep -q "FAIL:"`):
```yaml
      - name: Self-tests — bouncers
        run: |
          ./godot --headless --path . --script res://tools/test_bouncers.gd 2>&1 | tee bouncers.log
          grep -q "fail=0" bouncers.log && ! grep -q "FAIL:" bouncers.log

      - name: Self-tests — portals
        run: |
          ./godot --headless --path . --script res://tools/test_portals.gd 2>&1 | tee portals.log
          grep -q "fail=0" portals.log && ! grep -q "FAIL:" portals.log
```

- [ ] **Step 2: Confirm both tests are green locally**, then commit.
```bash
git add .github/workflows/ci.yml
git commit -m "ci: run bouncers + portals self-tests"
```

---

## Task 7: Rich generative pinball SuperCollider example

Author `examples/supercollider/example_pinball.scd`: a self-contained, **busy** generative pinball table. SuperCollider drives the board over OSC **and** synthesises every sound locally (no external synth), like the pachinko/chaos-globe examples. Build it in **3D with planar physics** (reuse the pachinko approach: bodies pinned to a plane, camera facing it) so the 0.10.0 lighting/materials look good.

**Richness requirements — the table must have a LOT happening:**
- **Multiball**: 3–5 balls launched (staggered), each recycled at the drain and relaunched → the table is never empty.
- **Bumpers**: ≥ 6 bouncer bumpers scattered on the field, varied `strength` and colors, each with an `on areaEnter` binding to a bumper-sound address (pitch/brightness tracks ball speed via `otherspeed`/`intensity` in the payload).
- **Portals**: ≥ 2 portal pairs (directional links) placed to warp balls across the table, each with an `on areaEnter` binding to a "whoosh" address.
- **Scoring targets**: ≥ 8 pentatonic **sensor zones** (existing `physics enable area` + `on areaEnter`/`areaStay`) arranged in banks across two octaves; zone → pitch, emitting a bell-note address.
- **Containment**: outer walls as **static bodies with `bounce`** (existing) so balls stay on the table; a **drain zone** across the bottom that emits a thunk and triggers relaunch.
- **Pins/obstacles**: a scatter of small static pins (spheres) the balls rattle against.
- **Visuals**: colored balls, glowing/colored bumpers, lit 3D materials, a fitted camera.

**SuperCollider synthesis — ≥ 5 SynthDefs** producing layered generative music:
1. bumper "ding" — bright metallic/FM blip, pitch & brightness from ball speed;
2. portal "whoosh" — swept filtered noise;
3. target bell — pentatonic sine/bell, panned by zone position;
4. drain "thunk" — low percussive body;
5. a sustained bass/pad tied to the number of balls in play (or a slow arpeggio) for a musical bed.
Wire `OSCdef`/`OSCFunc` responders for each emitted address; keep everything on one output; boot-and-go.

**Header**: document the run steps (boot the Godot project in 3D, evaluate the block) and the caveat "mind that no other instance holds 7401", consistent with the other example headers.

- [ ] **Step 1: Author the file** `examples/supercollider/example_pinball.scd` meeting every richness + synthesis requirement above. Model the OSC-sending helper, structure, and drain/relaunch loop on `examples/supercollider/example_pachinko.scd`; model the SynthDef/OSCdef style on it too.

- [ ] **Step 2: Verify OSC command correctness.** Cross-check every `/ms/...` address and argument used in the file against the actual implemented commands (this repo): `new bouncer/portal/sphere`, `collider`, `physics enable rigid|static|area`, `physics bounce`, `physics planar`, `bouncer strength …`, `portal link …`, `on areaEnter …`, `payload …`, `color`, `pos`, gravity. Fix any mismatch. (If `sclang` is available on PATH, run `sclang -D examples/supercollider/example_pinball.scd`-style parse only if it won't try to boot the server; otherwise a manual syntax read is the gate — SC cannot run in CI.)

- [ ] **Step 3: Add a TUTORIAL "Next steps" bullet** for the pinball example (if not already added in Task 5 Step 3), and ensure the CHANGELOG 0.12.0 entry mentions it.

- [ ] **Step 4: Commit.**
```bash
git add examples/supercollider/example_pinball.scd TUTORIAL.md CHANGELOG.md
git commit -m "example(sc): rich generative pinball using bouncers, portals, zones"
```

---

## Final review

After Task 7: dispatch a final holistic review of the whole feature (correctness of the reflection/teleport math and coordinate handling, 2D+3D parity, docs accuracy vs code, and the pinball example's command correctness + richness), fix anything material, then use `superpowers:finishing-a-development-branch`.
