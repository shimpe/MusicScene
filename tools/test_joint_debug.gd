extends SceneTree
## Headless test for the joint debug overlay (/gscore/physics debug). Space-aware.
##   <godot> --headless --path . --script res://tools/test_joint_debug.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _joint_node(osc):
	return osc.objects_root.get_node_or_null("hinge1_joint")

func _debug_child(osc):
	var jn = _joint_node(osc)
	return jn.get_node_or_null("JointDebug") if jn != null else null

func _surface_ok(dbg) -> bool:
	# 3D: ImmediateMesh with >=1 surface. 2D: a "conn" Line2D with 2 points.
	if dbg is MeshInstance3D:
		var m = (dbg as MeshInstance3D).mesh
		return m != null and m.get_surface_count() >= 1
	var conn = dbg.get_node_or_null("conn")
	return conn != null and conn.points.size() == 2

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	var d = osc.dispatcher
	if _f == 2:
		d.dispatch("/gscore/scene", ["reset"])
		d.dispatch("/gscore/scene/post", ["new", "circle"])
		d.dispatch("/gscore/scene/post/physics", ["enable", "static"])
		d.dispatch("/gscore/scene/post", ["pos", 0.0, 0.5, 0.0])
		d.dispatch("/gscore/scene/arm", ["new", "circle"])
		d.dispatch("/gscore/scene/arm/physics", ["enable", "rigid"])
		d.dispatch("/gscore/scene/arm", ["pos", 0.5, 0.5, 0.0])
		# hinge is 3D-only; 2D has no hinge, so use a pin there. Overlay works for any joint type.
		if osc.space == "3d":
			d.dispatch("/gscore/joint/hinge1", ["new", "hinge", "post", "arm"])
			d.dispatch("/gscore/joint/hinge1", ["axis", 0, 0, 1])
		else:
			d.dispatch("/gscore/joint/hinge1", ["new", "pin", "post", "arm"])
	elif _f == 4:
		check(_joint_node(osc) != null, "joint node created (hinge1_joint)")
		check(_debug_child(osc) == null, "no overlay before debug is enabled")
		d.dispatch("/gscore/physics", ["debug", 1])
	elif _f == 8:
		var dbg = _debug_child(osc)
		check(dbg != null, "overlay created after 'physics debug 1'")
		check(dbg != null and _surface_ok(dbg), "overlay has drawn geometry (connection line)")
		check(dbg != null and dbg.top_level, "overlay is top_level (world space)")
		d.dispatch("/gscore/physics", ["debug", 0])
	elif _f == 12:
		check(_debug_child(osc) == null, "overlay removed after 'physics debug 0'")
		d.dispatch("/gscore/physics", ["debug", 1])
	elif _f == 16:
		check(_debug_child(osc) != null, "overlay re-created when toggled back on")
		d.dispatch("/gscore/scene", ["clear"])
	elif _f == 20:
		check(_joint_node(osc) == null, "scene clear frees joint node (and its overlay child)")
		check(osc.joints.list_ids().is_empty(), "no joints remain after clear")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
