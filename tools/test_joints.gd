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

func _spring_type(osc) -> String:
	return "slider" if osc.spatial.is_3d() else "dampedspring"

func _make_two_bodies(osc) -> void:
	osc.dispatcher.dispatch("/gscore/scene/anchor", ["new", "circle"])
	osc.dispatcher.dispatch("/gscore/scene/anchor/physics", ["enable", "static"])
	osc.dispatcher.dispatch("/gscore/scene/anchor", ["pos", 0.0, 0.4, 0.0])
	osc.dispatcher.dispatch("/gscore/scene/note", ["new", "circle"])
	osc.dispatcher.dispatch("/gscore/scene/note/physics", ["enable", "rigid"])
	osc.dispatcher.dispatch("/gscore/scene/note", ["pos", 0.0, 0.0, 0.0])

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 5:
		check(osc.joints != null, "ctx.joints exists")
		check(osc.joints.list_ids().is_empty(), "joints map starts empty")
	if _f == 7:
		_make_two_bodies(osc)
	if _f == 9:
		osc.dispatcher.dispatch("/gscore/joint/string1", ["new", _spring_type(osc), "anchor", "note"])
	if _f == 11:
		check(osc.joints.has("string1"), "joint 'string1' created")
		var jn = osc.joints._joints.get("string1")
		check(jn != null and is_instance_valid(jn.node), "joint node is valid")
		check(jn != null and jn.node.get_parent() == osc.objects_root, "joint parented under objects_root")
	if _f == 14:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
