extends SceneTree
## /gscore/scene reset must restore a "like first run" state (keeping safety config).
## Run:  <godot> --headless --path . --script res://tools/test_scene_reset.gd   (space-aware)
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1; print("PASS: ", msg)
	else:
		_fail += 1; print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 3:
		osc.dispatcher.dispatch("/gscore/app/permissions", ["freeNodes", 1])   # safety flag: must be preserved
		osc.dispatcher.dispatch("/gscore/scene/a", ["new", "circle"])
		osc.dispatcher.dispatch("/gscore/scene/a/physics", ["enable", "static"])
		osc.dispatcher.dispatch("/gscore/scene/b", ["new", "circle"])
		osc.dispatcher.dispatch("/gscore/scene/b/physics", ["enable", "rigid"])
		var jt: String = "slider" if osc.spatial.is_3d() else "dampedspring"
		osc.dispatcher.dispatch("/gscore/joint/j", ["new", jt, "a", "b"])
		osc.dispatcher.dispatch("/gscore/scene/b", ["map", 0.0, 10.0, "x", -0.5, 0.5])
		osc.dispatcher.dispatch("/gscore/physics", ["gravity", 0.0, -1.0, 0.0])
		osc.dispatcher.dispatch("/gscore/physics", ["enable", 1])
		if osc.spatial.is_3d():
			osc.camera.handle([], ["pos", 0.5, 0.5, 0.5])   # move camera off default
	if _f == 5:
		check(not osc.registry.list_ids().is_empty(), "precondition: objects exist")
		check(osc.physics_world.is_simulating(), "precondition: physics simulating")
		osc.dispatcher.dispatch("/gscore/scene", ["reset"])
		check(osc.registry.list_ids().is_empty(), "reset clears objects")
		check(osc.joints.list_ids().is_empty(), "reset clears joints")
		check(osc.timemapper._maps.is_empty(), "reset clears time-maps")
		check(not osc.physics_world.is_simulating(), "reset disables physics")
		check(osc.physics_world.gravity_norm == Vector3.ZERO, "reset zeroes gravity")
		check(osc.mapper.app_mode == "normalized", "reset restores coord mode")
		check(osc.permissions.free_nodes == true, "reset preserves permissions (freeNodes still set)")
	if _f == 8:
		if osc.spatial.is_3d():
			var c = osc.get_viewport().get_camera_3d()
			check(c.global_position.distance_to(Vector3(0, 0, osc.spatial.default_camera_dist())) < 0.01, "reset restores default camera framing")
	if _f == 11:
		print("DONE pass=%d fail=%d" % [_pass, _fail]); return true
	return false
