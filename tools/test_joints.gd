extends SceneTree
## Headless joint tests. Run:
##   <godot> --headless --path . --script res://tools/test_joints.gd
## Tests whichever spatial backend is active (gscore_osc/space). Run once per space.
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
	if _f == 5:
		check(osc.joints != null, "ctx.joints exists")
		check(osc.joints.list_ids().is_empty(), "joints map starts empty")
	if _f == 10:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
