extends SceneTree
## Regression: setting `pos` on a RigidBody must stick even while physics is SIMULATING.
## (A simulating body otherwise reverts a plain global_position assignment to its own state.)
## Run:  <godot> --headless --path . --script res://tools/test_rigid_pos.gd   (space-aware)
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
	if _f == 3:
		# Gravity keeps the body AWAKE so the physics server actively integrates it — this is what
		# reverts a plain global_position assignment back to the body's cached (origin) state.
		osc.dispatcher.dispatch("/gscore/physics", ["gravity", 0.0, -1.0, 0.0])
		osc.dispatcher.dispatch("/gscore/physics", ["enable", 1])
	if _f == 6:
		osc.dispatcher.dispatch("/gscore/scene/note", ["new", "circle"])
	if _f == 10:
		osc.dispatcher.dispatch("/gscore/scene/note/physics", ["enable", "rigid"])
	if _f == 16:
		osc.dispatcher.dispatch("/gscore/scene/note", ["pos", 0.3, 0.5, 0.0])
	if _f == 25:
		# x is independent of vertical gravity: if pos stuck it stays 0.3; on the bug it reverts to -1.
		var note = osc.registry.get_object("note")
		var p = osc.spatial.get_position_norm(note.node, osc.mapper.app_mode)
		check(absf(p.x - 0.3) < 0.06, "rigid pos x sticks while simulating (x=%.3f, want 0.3, bug=>-1)" % p.x)
	if _f == 28:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
