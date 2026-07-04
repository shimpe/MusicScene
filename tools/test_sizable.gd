extends SceneTree
## Headless test for sizable primitives: `new circle <r>` and `new rect <w> <h>` (app coord mode),
## and that the auto-collider tracks the sized visual. Space-aware.
##   <godot> --headless --path . --script res://tools/test_sizable.gd
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
		d.dispatch("/ms/scene/cdef", ["new", "circle"])            # default
		d.dispatch("/ms/scene/csmall", ["new", "circle", 0.03])    # sized
		d.dispatch("/ms/scene/rdef", ["new", "rect"])              # default
		d.dispatch("/ms/scene/rsized", ["new", "rect", 0.4, 0.3])  # sized
		d.dispatch("/ms/scene/csmall/physics", ["enable", "rigid"])  # auto-collider from sized mesh
	elif _f == 4:
		if osc.space == "3d":
			var cdef = osc.registry.get_object("cdef").node
			var rdef = osc.registry.get_object("rdef").node
			var rsized = osc.registry.get_object("rsized").node
			check(absf(cdef.mesh.radius - 0.3) < 0.001, "default circle radius unchanged (0.3 world)")
			check(absf(rdef.mesh.size.x - 2.0) < 0.001 and absf(rdef.mesh.size.y - 1.3) < 0.001, "default rect size unchanged (2.0 x 1.3)")
			check(absf(rsized.mesh.size.x - 2.0) < 0.01 and absf(rsized.mesh.size.y - 1.5) < 0.01, "rect 0.4 0.3 -> (2.0, 1.5) world")
			# sized circle radius = 0.03 normalized * H(5) = 0.15 world
			var csmall = osc.registry.get_object("csmall").node
			var vis = null
			for c in csmall.get_children():
				if c is MeshInstance3D: vis = c
			check(vis != null and absf(vis.mesh.radius - 0.15) < 0.01, "circle 0.03 -> sphere radius 0.15 world")
			# auto-collider box should be ~0.3 (2*0.15) -> half 0.15
			var cs = null
			for c in csmall.get_children():
				if c is CollisionShape3D: cs = c
			check(cs != null and cs.shape is BoxShape3D and absf((cs.shape as BoxShape3D).size.x - 0.3) < 0.02, "auto-collider matches the sized circle (~0.3 box)")
		else:
			# 2D: confirm sized primitives build without error (pixel sizing mirrors 3D)
			check(osc.registry.get_object("csmall") != null, "2D: sized circle created")
			check(osc.registry.get_object("rsized") != null, "2D: sized rect created")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
