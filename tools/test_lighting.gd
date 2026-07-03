extends SceneTree
## Headless test for the default lighting rig and /gscore/light commands (3D only).
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
	var osc = root.get_node_or_null("GScoreOSC")
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
		var d = osc.dispatcher
		d.dispatch("/gscore/light", ["energy", 2.0])
		d.dispatch("/gscore/light", ["ambient", 0.7])
		d.dispatch("/gscore/light", ["color", 1.0, 0.5, 0.25])
		d.dispatch("/gscore/light", ["shadows", 1])
	elif _f == 5:
		var key = osc.get_node_or_null("GScoreKeyLight")
		var fill = osc.get_node_or_null("GScoreFillLight")
		check(key != null and absf(key.light_energy - 2.0) < 0.001, "energy -> key light 2.0")
		check(fill != null and absf(fill.light_energy - 0.7) < 0.001, "ambient -> fill light 0.7")
		check(key != null and key.light_color.is_equal_approx(Color(1.0, 0.5, 0.25)), "color -> key light")
		check(key != null and key.shadow_enabled, "shadows 1 -> key shadows on")
		osc.dispatcher.dispatch("/gscore/light", ["reset"])
	elif _f == 7:
		var key = osc.get_node_or_null("GScoreKeyLight")
		check(key != null and absf(key.light_energy - 1.0) < 0.001 and not key.shadow_enabled, "reset restores key light defaults")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
