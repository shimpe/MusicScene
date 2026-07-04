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
		# 2D backend: /ms/light and lighting-reset must no-op without error.
		var d2 = osc.dispatcher
		d2.dispatch("/ms/light", ["energy", 2.0])
		d2.dispatch("/ms/light", ["dir", 1, 0, 0])
		d2.dispatch("/ms/scene", ["reset"])   # exercises the 2D reset_lighting no-op
		check(true, "2D: /ms/light + scene reset no-op without error")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
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
		# dir aims the key light so its -Z axis points along the given world vector.
		osc.dispatcher.dispatch("/ms/light", ["dir", 1, 0, 0])
		check(key != null and (-key.global_transform.basis.z).dot(Vector3(1, 0, 0)) > 0.99, "dir -> key light aims +x")
		osc.dispatcher.dispatch("/ms/light", ["dir", 0, 1, 0])   # parallel to UP: exercises _safe_up fallback
		check(key != null and (-key.global_transform.basis.z).dot(Vector3(0, 1, 0)) > 0.99, "dir straight-up (safe_up) aims +y")
		osc.dispatcher.dispatch("/ms/light", ["reset"])
	elif _f == 7:
		var key = osc.get_node_or_null("MSKeyLight")
		var fill = osc.get_node_or_null("MSFillLight")
		check(key != null and absf(key.light_energy - 1.0) < 0.001 and not key.shadow_enabled, "reset restores key light energy + shadows")
		check(key != null and key.light_color.is_equal_approx(Color.WHITE), "reset restores key light color")
		check(fill != null and absf(fill.light_energy - 0.35) < 0.001, "reset restores fill light energy")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
