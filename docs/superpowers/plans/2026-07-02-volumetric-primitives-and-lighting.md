# Volumetric Primitives & Lighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add volumetric mesh primitives (`sphere`, `box`/`cube`, `cylinder`, `capsule`, `cone`) and a default lighting rig with lit materials to MusicScene's 3D mode, so 3D scenes can look genuinely 3D — while remaining fully backward-compatible.

**Architecture:** Extend the existing 3D backend `MSSpatial3D` with the new primitives, a `_lit()` material helper, per-object material verbs, an `ensure_lighting()` rig (mirroring `ensure_camera()`), and a `/ms/light` handler. 2D gets no-op/alias twins. Material choice is keyed on the creation type name plus a global `scene shading` mode.

**Tech Stack:** Godot 4.7, GDScript. Headless `SceneTree` self-tests run via `--script`, wired into GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-07-02-volumetric-primitives-and-lighting-design.md`

**Conventions:**
- GDScript files use **TAB** indentation — copy the code blocks verbatim (tabs, not spaces).
- Below, `godot` means your Godot 4.7 binary (CI uses `./godot`). Tests run in the project's configured space; `project.godot` sets `space="3d"`, so CI exercises the 3D branch.
- Test scripts follow the existing pattern (`tools/test_sizable.gd`): `extends SceneTree`, a `_process` frame counter, `check(cond, msg)`, and a final `DONE pass=N fail=M` line. CI greps `fail=0` and the absence of `FAIL:`.

---

### Task 1: `_lit` material, classification helpers, and the `sphere` primitive

Adds the lit-material helper and the `sphere` primitive (a lit `SphereMesh`), refactors `circle` to share the sphere-mesh builder while staying unshaded, and introduces the material chooser + global-mode field that later tasks build on.

**Files:**
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (add fields/helpers; edit the `circle` case; add `sphere` case)
- Test: `tools/test_volumetric.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/test_volumetric.gd`:

```gdscript
extends SceneTree
## Headless test for volumetric primitives and their default materials.
## Space-aware: 3D asserts real meshes/materials; 2D asserts fallbacks create without error.
##   <godot> --headless --path . --script res://tools/test_volumetric.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _mesh_of(osc, id):
	var obj = osc.registry.get_object(id)
	return obj.node.mesh if obj != null and obj.node is MeshInstance3D else null

func _unshaded(node) -> bool:
	return node.material_override != null \
		and node.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	var d = osc.dispatcher
	if _f == 2:
		d.dispatch("/ms/scene", ["reset"])
		d.dispatch("/ms/scene/sph", ["new", "sphere"])
		d.dispatch("/ms/scene/sph2", ["new", "sphere", 0.06])
		d.dispatch("/ms/scene/cir", ["new", "circle"])
	elif _f == 4:
		if osc.space == "3d":
			var sph = osc.registry.get_object("sph").node
			var cir = osc.registry.get_object("cir").node
			check(sph.mesh is SphereMesh, "sphere -> SphereMesh")
			check(absf((sph.mesh as SphereMesh).radius - 0.3) < 0.001, "sphere default radius 0.3 world")
			check(absf((_mesh_of(osc, "sph2") as SphereMesh).radius - 0.3) < 0.01, "sphere 0.06 -> radius 0.3 world")
			check(not _unshaded(sph), "sphere is lit by default")
			check(cir.mesh is SphereMesh, "circle still a SphereMesh (unchanged geometry)")
			check(_unshaded(cir), "circle stays unshaded by default")
		else:
			check(osc.registry.get_object("sph") != null, "2D: sphere created")
			check(osc.registry.get_object("cir") != null, "2D: circle created")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tools/test_volumetric.gd`
Expected: `FAIL:` lines (e.g. `sphere -> SphereMesh` fails because `new sphere` errors "Unknown built-in type" and the object/mesh is null) and `fail>0`.

- [ ] **Step 3: Add the fields and helpers**

In `addons/musicscene/core/MSSpatial3D.gd`, add these fields right after `var ctx = null` (near line 15):

```gdscript
var ctx = null
var shade_mode: String = "auto"          # global material default: auto | shaded | flat
```

Add these helpers in the `# --- helpers ---` section (near the existing `_unshaded`, around line 564):

```gdscript
func _lit(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _is_volumetric_solid(type: String) -> bool:
	return type in ["sphere", "box", "cube", "cylinder", "capsule", "cone"]


func _shaded_forceable(type: String) -> bool:
	return _is_volumetric_solid(type) or type == "rect"


## Pick the default material for a freshly-created primitive, honoring the global shade_mode.
func _material_for(type: String, color: Color) -> StandardMaterial3D:
	var lit := _is_volumetric_solid(type)          # "auto" per-type default
	match shade_mode:
		"flat": lit = false
		"shaded": lit = _shaded_forceable(type)
	return _lit(color) if lit else _unshaded(color)


func _sphere_mesh(args: Array) -> SphereMesh:
	var r := 0.3
	if args.size() > 0:
		r = length_to_world(_pf(args, 0, 0.06), ctx.mapper.app_mode)
	var s := SphereMesh.new(); s.radius = r; s.height = r * 2.0
	return s
```

- [ ] **Step 4: Edit the `circle` case and add the `sphere` case**

In `create_primitive`, replace the existing `"circle":` arm (lines 224-233) with:

```gdscript
		"circle":
			var mi := MeshInstance3D.new(); mi.name = "Circle"
			# Unchanged: a SphereMesh with an unshaded material (the flat INScore token).
			mi.mesh = _sphere_mesh(args)
			mi.material_override = _material_for("circle", Color(0.95, 0.55, 0.45))
			return mi
		"sphere":
			var mi := MeshInstance3D.new(); mi.name = "Sphere"
			# Same geometry as circle, but lit by default.
			mi.mesh = _sphere_mesh(args)
			mi.material_override = _material_for("sphere", Color(0.65, 0.72, 0.85))
			return mi
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tools/test_volumetric.gd`
Expected: all `PASS:` lines, final `DONE pass=6 fail=0`.

- [ ] **Step 6: Commit**

```bash
git add addons/musicscene/core/MSSpatial3D.gd tools/test_volumetric.gd
git commit -m "feat(3d): lit sphere primitive + material helpers (circle stays flat)"
```

---

### Task 2: `box`/`cube`, `cylinder`, `capsule`, `cone` primitives + colliders

Adds the remaining volumetric meshes (lit by default) and the matching `cylinder`/`capsule` collider shapes.

**Files:**
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (new `create_primitive` cases; new `make_collider` cases)
- Modify: `addons/musicscene/physics/MSPhysicsWorld.gd` (route `cylinder`/`capsule` collider commands — `handle_collider` has its own allow-list)
- Test: `tools/test_volumetric.gd` (extend)

- [ ] **Step 1: Extend the failing test**

In `tools/test_volumetric.gd`, in the `if _f == 2:` block, add after the existing `new` dispatches:

```gdscript
		d.dispatch("/ms/scene/bx", ["new", "box"])
		d.dispatch("/ms/scene/cy", ["new", "cylinder"])
		d.dispatch("/ms/scene/cap", ["new", "capsule"])
		d.dispatch("/ms/scene/cn", ["new", "cone"])
		d.dispatch("/ms/scene/cyc", ["new", "cylinder"])
		d.dispatch("/ms/scene/cyc/physics", ["enable", "static"])   # body must exist before a collider attaches
		d.dispatch("/ms/scene/cyc/collider", ["cylinder", 0.06, 0.16])
		d.dispatch("/ms/scene/capc", ["new", "capsule"])
		d.dispatch("/ms/scene/capc/physics", ["enable", "static"])
		d.dispatch("/ms/scene/capc/collider", ["capsule", 0.06, 0.2])
```

In the `if osc.space == "3d":` branch, add:

```gdscript
			check((_mesh_of(osc, "bx") as BoxMesh).size.is_equal_approx(Vector3(0.6, 0.6, 0.6)), "box default 0.6^3 world")
			check(_mesh_of(osc, "cy") is CylinderMesh, "cylinder -> CylinderMesh")
			check(_mesh_of(osc, "cap") is CapsuleMesh, "capsule -> CapsuleMesh")
			var cone_m = _mesh_of(osc, "cn")
			check(cone_m is CylinderMesh and absf((cone_m as CylinderMesh).top_radius) < 0.0001, "cone -> CylinderMesh with top_radius 0")
			check(not _unshaded(osc.registry.get_object("bx").node), "box lit by default")
			var cyc_cs = null
			for c in osc.registry.get_object("cyc").node.get_children():
				if c is CollisionShape3D: cyc_cs = c
			check(cyc_cs != null and cyc_cs.shape is CylinderShape3D, "collider cylinder -> CylinderShape3D")
			var capc_cs = null
			for c in osc.registry.get_object("capc").node.get_children():
				if c is CollisionShape3D: capc_cs = c
			check(capc_cs != null and capc_cs.shape is CapsuleShape3D, "collider capsule -> CapsuleShape3D")
```

In the `else:` (2D) branch, add:

```gdscript
			check(osc.registry.get_object("bx") != null, "2D: box created")
			check(osc.registry.get_object("cy") != null, "2D: cylinder created")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tools/test_volumetric.gd`
Expected: new `FAIL:` lines for box/cylinder/capsule/cone (`Unknown built-in type`) and the collider checks; `fail>0`.

- [ ] **Step 3: Add the primitive cases**

In `create_primitive`, add these arms just before the final `_:` default arm (after the `"notation":` arm, around line 258):

```gdscript
		"box", "cube":
			var mi := MeshInstance3D.new(); mi.name = "Box"
			var w := 0.6
			var h := 0.6
			var d := 0.6
			if args.size() > 0:
				var wn := _pf(args, 0, 0.12)
				w = length_to_world(wn, ctx.mapper.app_mode)
				h = length_to_world(_pf(args, 1, wn), ctx.mapper.app_mode)
				d = length_to_world(_pf(args, 2, wn), ctx.mapper.app_mode)
			var b := BoxMesh.new(); b.size = Vector3(w, h, d)
			mi.mesh = b
			mi.material_override = _material_for(type, Color(0.6, 0.7, 0.85))
			return mi
		"cylinder":
			var mi := MeshInstance3D.new(); mi.name = "Cylinder"
			var r := 0.3
			var hh := 0.8
			if args.size() > 0:
				r = length_to_world(_pf(args, 0, 0.06), ctx.mapper.app_mode)
				hh = length_to_world(_pf(args, 1, 0.16), ctx.mapper.app_mode)
			var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = hh
			mi.mesh = c
			mi.material_override = _material_for(type, Color(0.6, 0.7, 0.85))
			return mi
		"capsule":
			var mi := MeshInstance3D.new(); mi.name = "Capsule"
			var r := 0.3
			var hh := 0.9
			if args.size() > 0:
				r = length_to_world(_pf(args, 0, 0.06), ctx.mapper.app_mode)
				hh = length_to_world(_pf(args, 1, 0.18), ctx.mapper.app_mode)
			hh = maxf(hh, r * 2.0)          # Godot CapsuleMesh requires height >= 2*radius
			var c := CapsuleMesh.new(); c.radius = r; c.height = hh
			mi.mesh = c
			mi.material_override = _material_for(type, Color(0.6, 0.7, 0.85))
			return mi
		"cone":
			var mi := MeshInstance3D.new(); mi.name = "Cone"
			var r := 0.3
			var hh := 0.8
			if args.size() > 0:
				r = length_to_world(_pf(args, 0, 0.06), ctx.mapper.app_mode)
				hh = length_to_world(_pf(args, 1, 0.16), ctx.mapper.app_mode)
			var c := CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = r; c.height = hh
			mi.mesh = c
			mi.material_override = _material_for(type, Color(0.6, 0.7, 0.85))
			return mi
```

- [ ] **Step 4: Add the collider cases**

In `make_collider`, add these arms after the `"circle", "sphere":` arm (around line 445):

```gdscript
			"cylinder":
				var cy := CylinderShape3D.new()
				cy.radius = length_to_world(_pf(params, 0, 0.05), mode)
				cy.height = length_to_world(_pf(params, 1, 0.16), mode)
				cs.shape = cy
			"capsule":
				var cap := CapsuleShape3D.new()
				cap.radius = length_to_world(_pf(params, 0, 0.05), mode)
				cap.height = maxf(length_to_world(_pf(params, 1, 0.18), mode), cap.radius * 2.0)
				cs.shape = cap
```

- [ ] **Step 4b: Route the new collider kinds**

`make_collider` is only reached through the collider router, which keeps its own allow-list. In `addons/musicscene/physics/MSPhysicsWorld.gd` `handle_collider`, add after the `"sphere":` arm (around line 127):

```gdscript
			"cylinder": a.set_collider("cylinder", args.slice(1))
			"capsule": a.set_collider("capsule", args.slice(1))
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tools/test_volumetric.gd`
Expected: all `PASS:`, final `DONE pass=13 fail=0`.

- [ ] **Step 6: Commit**

```bash
git add addons/musicscene/core/MSSpatial3D.gd addons/musicscene/physics/MSPhysicsWorld.gd tools/test_volumetric.gd
git commit -m "feat(3d): box/cylinder/capsule/cone primitives + cylinder/capsule colliders"
```

---

### Task 3: 2D fallbacks for the new primitives

So the dimension-agnostic API never errors in 2D: `box`/`cube` → rect, `cylinder`/`capsule`/`cone` → rect, `sphere` → filled circle.

**Files:**
- Modify: `addons/musicscene/core/MSSpatial2D.gd` (`create_primitive`)
- Test: `tools/test_volumetric.gd` (already asserts creation in its 2D branch — run under a 2D override)

- [ ] **Step 1: Add the fallback cases**

In `addons/musicscene/core/MSSpatial2D.gd` `create_primitive`, change the `"rect":` arm label to also catch box/cube, and the `"circle":` arm label to also catch sphere, and add a cylinder/capsule/cone arm. Concretely, change:

```gdscript
		"rect":
```
to
```gdscript
		"rect", "box", "cube", "cylinder", "capsule", "cone":
```
and change:
```gdscript
		"circle":
```
to
```gdscript
		"circle", "sphere":
```

(`box`/`cube`/`cylinder`/`capsule`/`cone` all render as a rectangle in 2D; `sphere` renders as the filled circle. The `Primitive.Kind.RECT`/`CIRCLE` bodies are unchanged.)

- [ ] **Step 2: Verify it builds without errors (parse check)**

Run: `godot --headless --import --path . 2>&1 | tee import.log`
Expected: no `SCRIPT ERROR` / `Parse Error` for `MSSpatial2D.gd`.

- [ ] **Step 3: Verify the 2D branch of the test (optional local run)**

Create a temporary root override so the autoload runs in 2D (this file is gitignored per project convention):

```bash
cat > override.cfg <<'EOF'
[MusicScene]
space="2d"
EOF
godot --headless --path . --script res://tools/test_volumetric.gd
rm override.cfg
```
Expected: the 2D branch runs — `PASS: 2D: sphere created`, `PASS: 2D: box created`, `PASS: 2D: cylinder created`, `DONE ... fail=0`.

- [ ] **Step 4: Commit**

```bash
git add addons/musicscene/core/MSSpatial2D.gd
git commit -m "feat(2d): alias new volumetric primitives to nearest flat shape"
```

---

### Task 4: Per-object material verbs — `shaded`, `metallic`, `roughness`

Adds the three per-object verbs (3D acts on the `StandardMaterial3D`; 2D no-ops).

**Files:**
- Modify: `addons/musicscene/core/MSObject.gd` (`apply_command`)
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (`set_shaded`/`set_metallic`/`set_roughness`)
- Modify: `addons/musicscene/core/MSSpatial2D.gd` (no-op twins)
- Test: `tools/test_material_mode.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/test_material_mode.gd`:

```gdscript
extends SceneTree
## Headless test for per-object material verbs and the global shading toggle (3D only).
##   <godot> --headless --path . --script res://tools/test_material_mode.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _mat(osc, id):
	var obj = osc.registry.get_object(id)
	return obj.node.material_override if obj != null and obj.node is MeshInstance3D else null

func _lit(osc, id) -> bool:
	var m = _mat(osc, id)
	return m != null and m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if osc.space != "3d":
		print("DONE pass=0 fail=0")   # 3D-only test; skip in 2D
		return true
	var d = osc.dispatcher
	if _f == 2:
		d.dispatch("/ms/scene", ["reset"])
		d.dispatch("/ms/scene/s", ["new", "sphere"])
		d.dispatch("/ms/scene/c", ["new", "circle"])
	elif _f == 4:
		check(_lit(osc, "s"), "sphere lit by default")
		check(not _lit(osc, "c"), "circle unshaded by default")
		d.dispatch("/ms/scene/s", ["shaded", 0])
		d.dispatch("/ms/scene/c", ["shaded", 1])
		d.dispatch("/ms/scene/s", ["metallic", 0.5])
		d.dispatch("/ms/scene/s", ["roughness", 0.2])
	elif _f == 6:
		check(not _lit(osc, "s"), "shaded 0 -> sphere unshaded")
		check(_lit(osc, "c"), "shaded 1 -> circle lit")
		check(absf(_mat(osc, "s").metallic - 0.5) < 0.001, "metallic set to 0.5")
		check(absf(_mat(osc, "s").roughness - 0.2) < 0.001, "roughness set to 0.2")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tools/test_material_mode.gd`
Expected: `FAIL:` on the `shaded 0`/`metallic`/`roughness` checks (unknown command → material unchanged); `fail>0`.

- [ ] **Step 3: Add the verbs to `apply_command`**

In `addons/musicscene/core/MSObject.gd`, in the `apply_command` `match cmd:` block, add after the `"color":` line (line 72):

```gdscript
		"shaded": ctx.spatial.set_shaded(node, _arg_bool(args, 0, true))
		"metallic": ctx.spatial.set_metallic(node, _argf(args, 0))
		"roughness": ctx.spatial.set_roughness(node, _argf(args, 0))
```

- [ ] **Step 4: Add the 3D implementations**

In `addons/musicscene/core/MSSpatial3D.gd`, add after `set_color` (around line 194):

```gdscript
func set_shaded(node: Node, b: bool) -> void:
	if node is MeshInstance3D:
		var mat := _material_of(node)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if b else BaseMaterial3D.SHADING_MODE_UNSHADED


func set_metallic(node: Node, v: float) -> void:
	if node is MeshInstance3D:
		_material_of(node).metallic = clampf(v, 0.0, 1.0)


func set_roughness(node: Node, v: float) -> void:
	if node is MeshInstance3D:
		_material_of(node).roughness = clampf(v, 0.0, 1.0)
```

- [ ] **Step 5: Add the 2D no-ops**

In `addons/musicscene/core/MSSpatial2D.gd`, add after `set_color` (around line 148):

```gdscript
func set_shaded(_node: Node, _b: bool) -> void:
	pass


func set_metallic(_node: Node, _v: float) -> void:
	pass


func set_roughness(_node: Node, _v: float) -> void:
	pass
```

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless --path . --script res://tools/test_material_mode.gd`
Expected: all `PASS:`, final `DONE pass=6 fail=0`.

- [ ] **Step 7: Commit**

```bash
git add addons/musicscene/core/MSObject.gd addons/musicscene/core/MSSpatial3D.gd addons/musicscene/core/MSSpatial2D.gd tools/test_material_mode.gd
git commit -m "feat(3d): per-object shaded/metallic/roughness verbs (2D no-op)"
```

---

### Task 5: Default lighting rig — `ensure_lighting()`

Adds a lazy key+fill `DirectionalLight3D` rig, invoked next to `ensure_camera()`, that bails if the running scene already provides a light.

**Files:**
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (fields + `ensure_lighting` + helpers)
- Modify: `addons/musicscene/core/MSSpatial2D.gd` (no-op twins)
- Modify: `addons/musicscene/nodes/MSRoot.gd:110` (call site)
- Test: `tools/test_lighting.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/test_lighting.gd`:

```gdscript
extends SceneTree
## Headless test for the default lighting rig and /ms/light commands (3D only).
##   <godot> --headless --path . --script res://tools/test_lighting.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _dir_lights(osc) -> Array:
	var out := []
	for c in osc.get_children():
		if c is DirectionalLight3D: out.append(c)
	return out

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if osc.space != "3d":
		print("DONE pass=0 fail=0")   # 3D-only test; skip in 2D
		return true
	if _f == 2:
		# _has_dir_light() drives the "skip if the scene already lights itself" guard.
		# Test the predicate directly (headless --script has no current_scene, so the
		# skip branch is otherwise never exercised).
		var lit := Node3D.new(); lit.add_child(DirectionalLight3D.new())
		check(osc.spatial._has_dir_light(lit), "_has_dir_light finds a light in a tree")
		lit.free()
		var dark := Node3D.new(); dark.add_child(Node3D.new())
		check(not osc.spatial._has_dir_light(dark), "_has_dir_light false when tree has no light")
		dark.free()
	if _f == 3:
		var lights = _dir_lights(osc)
		check(lights.size() >= 2, "key + fill DirectionalLight3D created")
		osc.spatial.ensure_lighting()   # idempotent
		check(_dir_lights(osc).size() == lights.size(), "ensure_lighting is idempotent")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tools/test_lighting.gd`
Expected: `FAIL: key + fill DirectionalLight3D created` (no lights yet); `fail>0`.

- [ ] **Step 3: Add the fields + `ensure_lighting` (3D)**

In `addons/musicscene/core/MSSpatial3D.gd`, add fields after the `shade_mode` field from Task 1:

```gdscript
var _key_light: DirectionalLight3D = null
var _fill_light: DirectionalLight3D = null
```

Add these methods right after `ensure_camera()` (around line 54):

```gdscript
func ensure_lighting() -> void:
	if _key_light != null and is_instance_valid(_key_light):
		return
	var tree = ctx.get_tree()
	if tree != null and tree.current_scene != null and _has_dir_light(tree.current_scene):
		return   # the running scene already provides its own lighting; don't double it
	_key_light = DirectionalLight3D.new()
	_key_light.name = "MSKeyLight"
	_key_light.rotation_degrees = Vector3(-50, -35, 0)
	_key_light.light_energy = 1.0
	_key_light.shadow_enabled = false
	ctx.add_child(_key_light)
	_fill_light = DirectionalLight3D.new()
	_fill_light.name = "MSFillLight"
	_fill_light.rotation_degrees = Vector3(-20, 145, 0)
	_fill_light.light_energy = 0.35
	_fill_light.shadow_enabled = false
	ctx.add_child(_fill_light)
	if ctx.verbose:
		print("[MusicSceneOSC] auto-created 3D lighting (key + fill)")


func _has_dir_light(n: Node) -> bool:
	if n is DirectionalLight3D:
		return true
	for c in n.get_children():
		if _has_dir_light(c):
			return true
	return false
```

- [ ] **Step 4: Add the 2D no-op**

In `addons/musicscene/core/MSSpatial2D.gd`, add after its `ensure_camera()` (around line 30):

```gdscript
func ensure_lighting() -> void:
	pass
```

- [ ] **Step 5: Wire the call site**

In `addons/musicscene/nodes/MSRoot.gd`, change line 110 from:

```gdscript
	spatial.ensure_camera()
```
to
```gdscript
	spatial.ensure_camera()
	spatial.ensure_lighting()
```

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless --path . --script res://tools/test_lighting.gd`
Expected: all `PASS:`, final `DONE pass=4 fail=0`.

- [ ] **Step 7: Commit**

```bash
git add addons/musicscene/core/MSSpatial3D.gd addons/musicscene/core/MSSpatial2D.gd addons/musicscene/nodes/MSRoot.gd tools/test_lighting.gd
git commit -m "feat(3d): default key+fill directional lighting rig (ensure_lighting)"
```

---

### Task 6: `/ms/light` command handler

Adds `dir`/`color`/`energy`/`ambient`/`shadows`/`reset` and routes the namespace.

**Files:**
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (`handle_light`, `reset_lighting`, helpers)
- Modify: `addons/musicscene/core/MSSpatial2D.gd` (no-op)
- Modify: `addons/musicscene/core/OscDispatcher.gd` (route `"light"`)
- Test: `tools/test_lighting.gd` (extend)

- [ ] **Step 1: Extend the failing test**

In `tools/test_lighting.gd`, replace the `if _f == 3:` block with:

```gdscript
	if _f == 3:
		var lights = _dir_lights(osc)
		check(lights.size() >= 2, "key + fill DirectionalLight3D created")
		osc.spatial.ensure_lighting()   # idempotent
		check(_dir_lights(osc).size() == lights.size(), "ensure_lighting is idempotent")
		var d = osc.dispatcher
		d.dispatch("/ms/light", ["energy", 2.0])
		d.dispatch("/ms/light", ["ambient", 0.7])
		d.dispatch("/ms/light", ["color", 1.0, 0.5, 0.25])
		d.dispatch("/ms/light", ["shadows", 1])
	elif _f == 5:
		var key = osc.get_node_or_null("MSKeyLight")
		var fill = osc.get_node_or_null("MSFillLight")
		check(key != null and absf(key.light_energy - 2.0) < 0.001, "energy -> key light 2.0")
		check(fill != null and absf(fill.light_energy - 0.7) < 0.001, "ambient -> fill light 0.7")
		check(key != null and key.light_color.is_equal_approx(Color(1.0, 0.5, 0.25)), "color -> key light")
		check(key != null and key.shadow_enabled, "shadows 1 -> key shadows on")
		osc.dispatcher.dispatch("/ms/light", ["reset"])
	elif _f == 7:
		var key = osc.get_node_or_null("MSKeyLight")
		check(key != null and absf(key.light_energy - 1.0) < 0.001 and not key.shadow_enabled, "reset restores key light defaults")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

(Delete the old `print("DONE ...")`/`return true` that was inside the previous `if _f == 3:` block — it now lives in the `elif _f == 7:` block.)

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tools/test_lighting.gd`
Expected: `FAIL:` on the energy/ambient/color/shadows checks (unknown namespace `/ms/light`); `fail>0`.

- [ ] **Step 3: Add `handle_light` + `reset_lighting` + helpers (3D)**

In `addons/musicscene/core/MSSpatial3D.gd`, add after `reset_lighting` slot — place these right after the `_has_dir_light` helper from Task 5:

```gdscript
func handle_light(rest, args: Array) -> void:
	ensure_lighting()
	if _key_light == null or not is_instance_valid(_key_light):
		ctx.error("internal_error", "/ms/light", "no active light"); return
	var verb: String
	var p: Array
	if rest.size() > 0:
		verb = str(rest[0]).to_lower(); p = args
	else:
		verb = str(args[0]).to_lower() if args.size() > 0 else ""; p = args.slice(1)
	match verb:
		"dir":
			var dir := Vector3(_pf(p, 0, 0.0), _pf(p, 1, -1.0), _pf(p, 2, 0.0))
			if dir.length() > 0.0001:
				var o: Vector3 = _key_light.global_position
				_key_light.look_at_from_position(o, o + dir.normalized(), _safe_up(dir))
		"color":
			_key_light.light_color = Color(_pf(p, 0, 1.0), _pf(p, 1, 1.0), _pf(p, 2, 1.0))
		"energy":
			_key_light.light_energy = _pf(p, 0, 1.0)
		"ambient":
			if _fill_light != null and is_instance_valid(_fill_light):
				_fill_light.light_energy = _pf(p, 0, 0.35)
		"shadows":
			_key_light.shadow_enabled = _arg_truthy(p, 0)
		"reset":
			reset_lighting()
		_:
			ctx.error("bad_arguments", "/ms/light", "Unknown light cmd: " + verb)


func reset_lighting() -> void:
	if _key_light != null and is_instance_valid(_key_light):
		_key_light.rotation_degrees = Vector3(-50, -35, 0)
		_key_light.light_color = Color.WHITE
		_key_light.light_energy = 1.0
		_key_light.shadow_enabled = false
	if _fill_light != null and is_instance_valid(_fill_light):
		_fill_light.light_energy = 0.35


func _safe_up(d: Vector3) -> Vector3:
	return Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD


func _arg_truthy(a: Array, i: int) -> bool:
	if i >= a.size():
		return false
	var v = a[i]
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	if v is String:
		return v == "1" or v.to_lower() == "true"
	return false
```

- [ ] **Step 4: Add the 2D no-op**

In `addons/musicscene/core/MSSpatial2D.gd`, add after its `ensure_lighting()`:

```gdscript
func handle_light(_rest, _args: Array) -> void:
	pass
```

- [ ] **Step 5: Route the namespace**

In `addons/musicscene/core/OscDispatcher.gd`, in `dispatch`'s `match head:`, add after the `"camera":` case (line 40):

```gdscript
		"light":
			ctx.spatial.handle_light(parts.slice(2), args)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless --path . --script res://tools/test_lighting.gd`
Expected: all `PASS:`, final `DONE pass=9 fail=0` (2 from the `_f==2` predicate checks + 2 rig checks + 4 command checks + 1 reset check).

- [ ] **Step 7: Commit**

```bash
git add addons/musicscene/core/MSSpatial3D.gd addons/musicscene/core/MSSpatial2D.gd addons/musicscene/core/OscDispatcher.gd tools/test_lighting.gd
git commit -m "feat(3d): /ms/light commands (dir/color/energy/ambient/shadows/reset)"
```

---

### Task 7: Global `scene shading auto|shaded|flat` toggle

Adds the scene-global material-mode command (applies to existing objects and biases new ones), and resets it on `scene reset`.

**Files:**
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (`set_global_shade_mode`)
- Modify: `addons/musicscene/core/MSSpatial2D.gd` (no-op)
- Modify: `addons/musicscene/core/OscDispatcher.gd` (`scene shading` verb + reset)
- Test: `tools/test_material_mode.gd` (extend)

- [ ] **Step 1: Extend the failing test**

In `tools/test_material_mode.gd`, replace the `elif _f == 6:` block's final two lines (`print(...)` and `return true`) — i.e. change the tail so it continues to further frames:

Replace:
```gdscript
		check(absf(_mat(osc, "s").roughness - 0.2) < 0.001, "roughness set to 0.2")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```
with:
```gdscript
		check(absf(_mat(osc, "s").roughness - 0.2) < 0.001, "roughness set to 0.2")
		d.dispatch("/ms/scene/r", ["new", "rect"])
		d.dispatch("/ms/scene", ["shading", "flat"])
	elif _f == 8:
		check(not _lit(osc, "s") and not _lit(osc, "c"), "shading flat -> all unshaded")
		d.dispatch("/ms/scene", ["shading", "shaded"])
	elif _f == 10:
		check(_lit(osc, "s"), "shading shaded -> sphere lit")
		check(_lit(osc, "r"), "shading shaded -> rect lit")
		check(not _lit(osc, "c"), "shading shaded -> circle still flat")
		d.dispatch("/ms/scene", ["shading", "auto"])
	elif _f == 12:
		check(_lit(osc, "s"), "shading auto -> sphere lit")
		check(not _lit(osc, "r"), "shading auto -> rect flat")
		check(not _lit(osc, "c"), "shading auto -> circle flat")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tools/test_material_mode.gd`
Expected: `FAIL:` on the `shading flat/shaded/auto` checks (unknown scene verb `shading`); `fail>0`.

- [ ] **Step 3: Add `set_global_shade_mode` (3D)**

In `addons/musicscene/core/MSSpatial3D.gd`, add after the `set_roughness` method from Task 4:

```gdscript
func set_global_shade_mode(mode: String) -> void:
	if not (mode in ["auto", "shaded", "flat"]):
		ctx.error("bad_arguments", "/ms/scene", "Unknown shading mode: " + mode)
		return
	shade_mode = mode
	for id in ctx.registry.list_ids():
		var obj = ctx.registry.get_object(id)
		if obj == null or not (obj.node is MeshInstance3D):
			continue
		var lit: bool
		match mode:
			"flat": lit = false
			"shaded": lit = _shaded_forceable(obj.type_hint)
			_: lit = _is_volumetric_solid(obj.type_hint)   # auto
		set_shaded(obj.node, lit)
```

- [ ] **Step 4: Add the 2D no-op**

In `addons/musicscene/core/MSSpatial2D.gd`, add after `set_roughness`:

```gdscript
func set_global_shade_mode(_mode: String) -> void:
	pass
```

- [ ] **Step 5: Wire the dispatcher**

In `addons/musicscene/core/OscDispatcher.gd`, in `_handle_scene`'s empty-`rest` `match _s(args, 0):` block, add a `"shading"` case after `"list"`/`"tree"` (around line 205, before the `_:` default):

```gdscript
			"shading": ctx.spatial.set_global_shade_mode(_s(args, 1))
```

Update that block's `_:` error message to include the new verb — change:
```gdscript
				_: ctx.error("bad_arguments", "/ms/scene", "Expected clear|reset|list|tree")
```
to
```gdscript
				_: ctx.error("bad_arguments", "/ms/scene", "Expected clear|reset|list|tree|shading")
```

In the same file, in the `"reset":` case of that block (around line 194-204), add this line at the end of the reset body (after `ctx.mapper.physics_mode = ...`):

```gdscript
				ctx.spatial.set_global_shade_mode("auto")
```

- [ ] **Step 6: Run test to verify it passes**

Run: `godot --headless --path . --script res://tools/test_material_mode.gd`
Expected: all `PASS:`, final `DONE pass=13 fail=0`.

- [ ] **Step 7: Commit**

```bash
git add addons/musicscene/core/MSSpatial3D.gd addons/musicscene/core/MSSpatial2D.gd addons/musicscene/core/OscDispatcher.gd tools/test_material_mode.gd
git commit -m "feat(3d): global scene shading auto|shaded|flat toggle"
```

---

### Task 8: Version bump, docs, and spec/memory updates

Bumps the version to 0.10.0, documents everything, and marks workstreams (a)+(b) done in the future-phase spec + memory. Softens the stale "3D is really 2D" comment.

**Files:**
- Modify: `addons/musicscene/core/OscDispatcher.gd` (version string, 3 occurrences)
- Modify: `addons/musicscene/core/MSSpatial3D.gd` (`body_set_planar` docstring)
- Modify: `README.md`, `TUTORIAL.md`, `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-07-02-true-3d-future-phase.md`
- Modify: memory `C:/Users/Stefaan Himpe/.claude/projects/D--Projects-MusicScene/memory/true-3d-future-phase.md`

- [ ] **Step 1: Bump the version string (3 places)**

In `addons/musicscene/core/OscDispatcher.gd`, replace `"0.9.0"` with `"0.10.0"` in all 3 occurrences — line 34 (`version` reply in `dispatch`), line 85 (`version` reply in `_handle_root`), and line 92 (the `"MusicScene", "0.9.0"` pair in `_handle_info`). Grep to confirm: `grep -n '0\.9\.0' addons/musicscene/core/OscDispatcher.gd` should return exactly those 3 lines.

- [ ] **Step 2: Soften the stale planar comment**

In `addons/musicscene/core/MSSpatial3D.gd`, in the `body_set_planar` docstring (around line 366-369), change:
```gdscript
## Pin a body to the z=0 plane (MusicScene's 3D is really 2D-in-a-plane). Without this, collisions and
```
to
```gdscript
## Pin a body to the z=0 plane — an opt-in constraint for flat/2.5D scenes. Without this, collisions and
```

- [ ] **Step 3: Update `CHANGELOG.md`**

Add at the top of the changelog entries (follow the existing format/date style):

```markdown
## [0.10.0] - 2026-07-02

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
```

- [ ] **Step 4: Update `README.md`**

In the command reference (near where `new`/primitives and `/ms/camera` are documented), add a
volumetric-primitives + lighting section. Insert this block after the camera command reference:

```markdown
### Volumetric primitives & lighting (3D)

Volumetric mesh primitives (lit by default):

    new sphere [r]                 lit ball (r in app coord mode; default 0.3 world)
    new box [w] [h] [d]            lit box (alias: cube; h,d default to w; default 0.6^3)
    new cylinder [r] [h]           lit cylinder (default r 0.3, h 0.8)
    new capsule [r] [h]            lit capsule (default r 0.3, h 0.9; h clamped >= 2r)
    new cone [r] [h]               lit cone (default r 0.3, h 0.8)

`circle` is unchanged — a flat/unshaded token (same geometry as `sphere`). `collider cylinder`/
`collider capsule` match the new meshes.

Per-object material:

    /ms/scene/<id> shaded [1|0]     lit vs unshaded
    /ms/scene/<id> metallic <0..1>
    /ms/scene/<id> roughness <0..1>
    /ms/scene shading auto|shaded|flat   global default (auto=per-type, flat=all unshaded,
                                             shaded=solids + rect panels lit; circle stays flat)

Lighting (a default key + fill light is added automatically):

    /ms/light dir <x> <y> <z>       aim the key light along a world direction
    /ms/light color <r> <g> <b>
    /ms/light energy <e>
    /ms/light ambient <e>           fill-light strength
    /ms/light shadows <0|1>         opt-in, off by default
    /ms/light reset

In 2D these material/light commands are no-ops and the volumetric names alias to flat shapes.
```

- [ ] **Step 5: Update `TUTORIAL.md`**

Add a new section before "## Next steps" (around line 1044):

```markdown
## Volumetric shapes & lighting (3D)

In 3D mode you can build real solids, not just flat tokens:

    new mysphere sphere            # a lit ball
    new mybox box 0.4 0.4 0.4      # a lit box
    new mycyl cylinder 0.2 0.6     # a lit cylinder (radius, height)

These are **lit** by default. MusicScene adds a default key + fill light to 3D scenes automatically, so
solids read as volumes out of the box (it steps aside if your scene already has a light). `circle`
stays flat/unshaded — it's the classic INScore token; use `sphere` when you want a 3D ball.

Tweak the look per object:

    /ms/scene/mybox roughness 0.2      # shinier
    /ms/scene/mybox metallic 0.8
    /ms/scene/mysphere shaded 0        # force flat

Or globally: `/ms/scene shading flat` for the classic all-flat look, `shaded` to also light flat
`rect` panels (walls/floors), `auto` for the default. Adjust the light with `/ms/light energy 2`,
`/ms/light dir 0 -1 -0.5`, `/ms/light color 1 0.9 0.8`, or turn on shadows with
`/ms/light shadows 1`.
```

- [ ] **Step 6: Update the future-phase spec**

In `docs/superpowers/specs/2026-07-02-true-3d-future-phase.md`, change the `**Status**` line at the top to note (a)+(b) landed:

```markdown
**Status: (a) volumetric primitives + (b) lighting LANDED in 0.10.0** (see
`2026-07-02-volumetric-primitives-and-lighting-design.md`). **(c) runtime model loading still
deferred / backlog.**
```

- [ ] **Step 7: Update the memory**

Edit `C:/Users/Stefaan Himpe/.claude/projects/D--Projects-MusicScene/memory/true-3d-future-phase.md` — change the "How to apply" line to record that (a)+(b) shipped in 0.10.0 and only (c) remains:

```markdown
**How to apply:** (a) volumetric primitives + (b) lighting/lit materials **shipped in 0.10.0**
(spec `2026-07-02-volumetric-primitives-and-lighting-design.md`; plan
`2026-07-02-volumetric-primitives-and-lighting.md`). Only **(c) runtime glTF/model loading** remains
deferred. Keep additions opt-in; `circle` stays flat, `sphere` is the lit ball. Related: the `planar`
opt-in lock (v0.8.0).
```

- [ ] **Step 8: Verify no parse errors and commit**

Run: `godot --headless --import --path . 2>&1 | tee import.log`
Expected: no `SCRIPT ERROR` / `Parse Error`.

```bash
git add addons/musicscene/core/OscDispatcher.gd addons/musicscene/core/MSSpatial3D.gd README.md TUTORIAL.md CHANGELOG.md docs/superpowers/specs/2026-07-02-true-3d-future-phase.md
git commit -m "docs: volumetric primitives + lighting (0.10.0); mark 3D phase (a)+(b) done"
```

(The memory file lives outside the repo; it is saved separately, not committed.)

---

### Task 9: Wire the new tests into CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add three CI steps**

In `.github/workflows/ci.yml`, after the "Self-tests — sizable primitives" step (line 83), add:

```yaml
      - name: Self-tests — volumetric primitives
        run: |
          ./godot --headless --path . --script res://tools/test_volumetric.gd 2>&1 | tee volumetric.log
          grep -q "fail=0" volumetric.log && ! grep -q "FAIL:" volumetric.log

      - name: Self-tests — material mode
        run: |
          ./godot --headless --path . --script res://tools/test_material_mode.gd 2>&1 | tee materialmode.log
          grep -q "fail=0" materialmode.log && ! grep -q "FAIL:" materialmode.log

      - name: Self-tests — lighting
        run: |
          ./godot --headless --path . --script res://tools/test_lighting.gd 2>&1 | tee lighting.log
          grep -q "fail=0" lighting.log && ! grep -q "FAIL:" lighting.log
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run volumetric / material-mode / lighting self-tests"
```

---

## Self-Review

**Spec coverage:**
- (a) volumetric primitives → Tasks 1–2 (sphere/box/cylinder/capsule/cone + colliders); 2D fallback → Task 3. ✓
- (b) lit materials + defaults → Task 1 (`_lit`, per-type default), per-object verbs → Task 4, global toggle → Task 7. ✓
- (b) lighting rig → Task 5; `/ms/light` → Task 6. ✓
- Version 0.10.0, docs, spec/memory, planar comment → Task 8. ✓
- Tests + CI → each feature task + Task 9. ✓
- Non-goals (glTF, multi-light, shadows-by-default) → not implemented. ✓

**Type/name consistency:** `shade_mode` field, `_is_volumetric_solid`/`_shaded_forceable`/`_material_for`/`_sphere_mesh`/`_lit` helpers, `set_shaded`/`set_metallic`/`set_roughness`/`set_global_shade_mode`/`ensure_lighting`/`handle_light`/`reset_lighting` methods, and node names `MSKeyLight`/`MSFillLight` are used identically across the tasks that define and consume them. Verbs `shaded`/`metallic`/`roughness` (object) and `shading` (scene) and the `/ms/light` sub-verbs match between dispatcher, backend, and tests.

**Backward compatibility:** `circle`/`rect`/`text`/notation untouched; lights skipped when the scene already has one and only affect lit materials; new verbs/namespaces are additive.
