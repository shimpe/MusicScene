extends SceneTree
## Headless test for volumetric primitives and their default materials.
## Space-aware: 3D asserts real meshes/materials; 2D asserts fallbacks create without error.
##   <godot> --headless --path . --script res://tools/test_volumetric.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _mesh_of(osc, id):
	var obj = osc.registry.get_object(id)
	return obj.node.mesh if obj != null and obj.node is MeshInstance3D else null

func _unshaded(node) -> bool:
	return node.material_override != null \
		and node.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	var d = osc.dispatcher
	if _f == 2:
		d.dispatch("/gscore/scene", ["reset"])
		d.dispatch("/gscore/scene/sph", ["new", "sphere"])
		d.dispatch("/gscore/scene/sph2", ["new", "sphere", 0.06])
		d.dispatch("/gscore/scene/cir", ["new", "circle"])
		d.dispatch("/gscore/scene/bx", ["new", "box"])
		d.dispatch("/gscore/scene/cy", ["new", "cylinder"])
		d.dispatch("/gscore/scene/cap", ["new", "capsule"])
		d.dispatch("/gscore/scene/cn", ["new", "cone"])
		d.dispatch("/gscore/scene/cyc", ["new", "cylinder"])
		d.dispatch("/gscore/scene/cyc/physics", ["enable", "static"])
		d.dispatch("/gscore/scene/cyc/collider", ["cylinder", 0.06, 0.16])
		d.dispatch("/gscore/scene/capc", ["new", "capsule"])
		d.dispatch("/gscore/scene/capc/physics", ["enable", "static"])
		d.dispatch("/gscore/scene/capc/collider", ["capsule", 0.06, 0.2])
	elif _f == 4:
		if osc.space == "3d":
			var sph = osc.registry.get_object("sph").node
			var cir = osc.registry.get_object("cir").node
			check(sph.mesh is SphereMesh, "sphere -> SphereMesh")
			check(absf((sph.mesh as SphereMesh).radius - 0.3) < 0.001, "sphere default radius 0.3 world")
			check(absf((_mesh_of(osc, "sph2") as SphereMesh).radius - 0.3) < 0.01, "sphere 0.06 -> radius 0.3 world")
			check(not _unshaded(sph), "sphere is lit by default")
			check(cir.mesh is SphereMesh, "circle still a SphereMesh (unchanged geometry)")
			check(_unshaded(cir), "circle stays unshaded by default")
			check((_mesh_of(osc, "bx") as BoxMesh).size.is_equal_approx(Vector3(0.6, 0.6, 0.6)), "box default 0.6^3 world")
			check(_mesh_of(osc, "cy") is CylinderMesh, "cylinder -> CylinderMesh")
			check(_mesh_of(osc, "cap") is CapsuleMesh, "capsule -> CapsuleMesh")
			var cone_m = _mesh_of(osc, "cn")
			check(cone_m is CylinderMesh and absf((cone_m as CylinderMesh).top_radius) < 0.0001, "cone -> CylinderMesh with top_radius 0")
			check(not _unshaded(osc.registry.get_object("bx").node), "box lit by default")
			var cyc_cs = null
			for c in osc.registry.get_object("cyc").node.get_children():
				if c is CollisionShape3D: cyc_cs = c
			check(cyc_cs != null and cyc_cs.shape is CylinderShape3D, "collider cylinder -> CylinderShape3D")
			var capc_cs = null
			for c in osc.registry.get_object("capc").node.get_children():
				if c is CollisionShape3D: capc_cs = c
			check(capc_cs != null and capc_cs.shape is CapsuleShape3D, "collider capsule -> CapsuleShape3D")
		else:
			check(osc.registry.get_object("sph") != null, "2D: sphere created")
			check(osc.registry.get_object("cir") != null, "2D: circle created")
			check(osc.registry.get_object("bx") != null, "2D: box created")
			check(osc.registry.get_object("cy") != null, "2D: cylinder created")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
