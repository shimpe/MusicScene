extends SceneTree
## Regression: /ms/scene clear must clear EVERY scene-bound id-space — objects, joints, and
## time-maps — not leave stale state that a rebuild can re-bind to or that keeps evaluating.
## Run:  <godot> --headless --path . --script res://tools/test_scene_clear.gd   (space-aware)
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
	if _f == 3:
		var jt: String = "slider" if osc.spatial.is_3d() else "dampedspring"
		osc.dispatcher.dispatch("/ms/scene/anchor", ["new", "circle"])
		osc.dispatcher.dispatch("/ms/scene/anchor/physics", ["enable", "static"])
		osc.dispatcher.dispatch("/ms/scene/note", ["new", "circle"])
		osc.dispatcher.dispatch("/ms/scene/note/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/ms/joint/string1", ["new", jt, "anchor", "note"])
		osc.dispatcher.dispatch("/ms/scene/note", ["map", 0.0, 10.0, "x", -0.9, 0.9])  # time-map
	if _f == 5:
		check(osc.joints.has("string1"), "precondition: joint exists")
		check(osc.timemapper._maps.size() == 1, "precondition: time-map exists")
		# Clear, then assert IN THE SAME FRAME that every scene-bound id-space is emptied proactively.
		osc.dispatcher.dispatch("/ms/scene", ["clear"])
		check(osc.registry.list_ids().is_empty(), "scene clear removed scene objects")
		check(osc.joints.list_ids().is_empty(), "scene clear removed joints")
		check(osc.timemapper._maps.is_empty(), "scene clear removed time-maps")
	if _f == 9:
		# Joint NODES are queue_free'd (deferred) — gone a frame later.
		var leftover := 0
		for c in osc.objects_root.get_children():
			if str(c.name).ends_with("_joint") or (c.get_class().findn("Joint") != -1):
				leftover += 1
		check(leftover == 0, "no joint nodes left under objects_root after clear")
	if _f == 12:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
