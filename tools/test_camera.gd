extends SceneTree
## Headless camera tests. Run:  <godot> --headless --path . --script res://tools/test_camera.gd
## Space-aware: in 3D it exercises the camera; in 2D it asserts the guard.
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1; print("PASS: ", msg)
	else:
		_fail += 1; print("FAIL: ", msg)

func cam(osc):
	return osc.get_viewport().get_camera_3d()

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if not osc.spatial.is_3d():
		if _f == 3:
			osc.camera.handle([], ["pos", 0.0, 0.0, 1.0])   # must be a guarded no-op, not a crash
			check(osc.get_viewport().get_camera_3d() == null, "2D: camera command is a guarded no-op")
		if _f == 6:
			print("DONE pass=%d fail=%d" % [_pass, _fail]); return true
		return false
	# --- 3D ---
	if _f == 3:
		osc.camera.handle([], ["pos", 0.3, 0.2, 0.5])
	if _f == 5:
		var c = cam(osc)
		var want = osc.spatial.to_world_point(0.3, 0.2, 0.5, osc.mapper.app_mode)
		check(c != null and c.global_position.distance_to(want) < 0.01, "camera pos set to normalized point")
		osc.camera.handle([], ["fov", 45])
		osc.camera.handle([], ["projection", "orthographic"])
		osc.camera.handle([], ["orthosize", 1.0])
	if _f == 7:
		var c = cam(osc)
		check(absf(c.fov - 45.0) < 0.1, "camera fov set")
		check(c.projection == Camera3D.PROJECTION_ORTHOGONAL, "camera projection orthographic")
		check(absf(c.size - osc.spatial.length_to_world(1.0, osc.mapper.app_mode)) < 0.1, "camera orthoSize set")
		osc.camera.handle([], ["reset"])
	if _f == 9:
		var c = cam(osc)
		check(absf(c.fov - 60.0) < 0.1, "reset restores fov 60")
		check(c.projection == Camera3D.PROJECTION_PERSPECTIVE, "reset restores perspective")
		check(c.global_position.distance_to(Vector3(0, 0, osc.spatial.default_camera_dist())) < 0.01, "reset restores default position")
	if _f == 12:
		print("DONE pass=%d fail=%d" % [_pass, _fail]); return true
	return false
