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
	if _f == 13:
		osc.dispatcher.dispatch("/gscore/joint/string1", ["restlength", 0.5])
		osc.dispatcher.dispatch("/gscore/joint/string1", ["stiffness", 0.7])
		osc.dispatcher.dispatch("/gscore/joint/string1", ["damping", 0.2])
	if _f == 16:
		var jn = osc.joints._joints.get("string1")
		check(jn != null and jn.rest_separation > 0.0, "restLength updated rest_separation")
		if osc.spatial.is_3d():
			check(jn.node is SliderJoint3D, "3D spring type is SliderJoint3D")
		else:
			check(jn.node is DampedSpringJoint2D, "2D spring type is DampedSpringJoint2D")
			check((jn.node as DampedSpringJoint2D).stiffness > 50.0, "2D stiffness mapped (0.7 -> >50)")
	if _f == 18:
		osc.dispatcher.dispatch("/gscore/physics", ["enable", 1])
		osc.dispatcher.dispatch("/gscore/joint/string1", ["breakforce", 0.9])
	if _f == 22:
		var note = osc.registry.get_object("note")
		var bd = note.physics_adapter.body if (note != null and note.physics_adapter != null) else null
		check(is_instance_valid(bd), "body valid for overstretch yank at f22")
		if is_instance_valid(bd):
			# 4000 px (2D) / 50 m (3D) — both far exceed the break threshold (~rest * 1.29)
			if bd is Node2D: bd.global_position += Vector2(4000, 0)
			elif bd is Node3D: bd.global_position += Vector3(50, 0, 0)
	if _f == 24 and osc.spatial.is_3d():
		osc.dispatcher.dispatch("/gscore/scene/anc2", ["new", "circle"])
		osc.dispatcher.dispatch("/gscore/scene/anc2/physics", ["enable", "static"])
		osc.dispatcher.dispatch("/gscore/scene/bod2", ["new", "circle"])
		osc.dispatcher.dispatch("/gscore/scene/bod2/physics", ["enable", "rigid"])
		for t in ["pin", "hinge", "conetwist", "generic6dof"]:
			osc.dispatcher.dispatch("/gscore/joint/j_" + t, ["new", t, "anc2", "bod2"])
		osc.dispatcher.dispatch("/gscore/joint/j_generic6dof", ["dof", "liny"])
		osc.dispatcher.dispatch("/gscore/joint/j_generic6dof", ["limit", -0.2, 0.2])
		osc.dispatcher.dispatch("/gscore/joint/j_generic6dof", ["stiffness", 0.6])
	if _f == 26:
		check(not osc.joints.has("string1"), "joint broke and was removed after overstretch")
	if _f == 27 and osc.spatial.is_3d():
		check(osc.joints.has("j_pin"), "3D pin created")
		check(osc.joints.has("j_hinge"), "3D hinge created")
		check(osc.joints.has("j_conetwist"), "3D coneTwist created")
		var g = osc.joints._joints.get("j_generic6dof")
		check(g != null and g.node is Generic6DOFJoint3D, "3D generic6dof created")
		check(g != null and bool(g.node.get("linear_spring_y/enabled")), "generic6dof linY spring enabled via dof")
	if _f == 30:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
