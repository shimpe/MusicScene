extends SceneTree
## Headless test for `/ms/scene/<id>/physics planar <0|1>` (pin a body to the z=0 plane).
## 3D-specific; in 2D it's a no-op (bodies are already planar) and this test just confirms no crash.
##   <godot> --headless --path . --script res://tools/test_planar.gd
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
	var d = osc.dispatcher
	if _f == 2:
		d.dispatch("/ms/scene", ["reset"])
		d.dispatch("/ms/scene/b", ["new", "circle"])
		d.dispatch("/ms/scene/b/physics", ["enable", "rigid"])
		d.dispatch("/ms/scene/b", ["pos", 0.0, 0.5, 0.3])   # start off-plane (z != 0)
		d.dispatch("/ms/physics", ["gravity", 0.0, -1.0, 0.0])
		d.dispatch("/ms/physics", ["enable", 1])
	elif _f == 4:
		var body = osc.registry.get_object("b").node
		if osc.space == "3d":
			d.dispatch("/ms/scene/b/physics", ["planar", 1])
			check(body.axis_lock_linear_z, "planar 1 locks the linear z axis")
		else:
			d.dispatch("/ms/scene/b/physics", ["planar", 1])  # no-op, must not error
			check(true, "planar is a harmless no-op in 2D")
	elif _f == 12:
		# body_set_state applies on the next physics step, so check the z-snap a few frames later
		if osc.space == "3d":
			var body = osc.registry.get_object("b").node
			check(absf(body.global_position.z) < 0.01, "planar 1 snaps the body back to z=0")
		else:
			check(true, "2d ok")
	elif _f == 40:
		var body = osc.registry.get_object("b").node
		if osc.space == "3d":
			check(absf(body.global_position.z) < 0.01, "body stays at z=0 while simulating")
			d.dispatch("/ms/scene/b/physics", ["planar", 0])
			check(not body.axis_lock_linear_z, "planar 0 releases the z axis")
		else:
			check(true, "2d ok")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
