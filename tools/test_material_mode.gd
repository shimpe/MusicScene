extends SceneTree
## Headless test for per-object material verbs and the global shading toggle (3D only).
##   <godot> --headless --path . --script res://tools/test_material_mode.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _mat(osc, id):
	var obj = osc.registry.get_object(id)
	return obj.node.material_override if obj != null and obj.node is MeshInstance3D else null

func _lit(osc, id) -> bool:
	var m = _mat(osc, id)
	return m != null and m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if osc.space != "3d":
		print("DONE pass=0 fail=0")   # 3D-only test; skip in 2D
		return true
	var d = osc.dispatcher
	if _f == 2:
		d.dispatch("/ms/scene", ["reset"])
		d.dispatch("/ms/scene/s", ["new", "sphere"])
		d.dispatch("/ms/scene/c", ["new", "circle"])
	elif _f == 4:
		check(_lit(osc, "s"), "sphere lit by default")
		check(not _lit(osc, "c"), "circle unshaded by default")
		d.dispatch("/ms/scene/s", ["shaded", 0])
		d.dispatch("/ms/scene/c", ["shaded", 1])
		d.dispatch("/ms/scene/s", ["metallic", 0.5])
		d.dispatch("/ms/scene/s", ["roughness", 0.2])
	elif _f == 6:
		check(not _lit(osc, "s"), "shaded 0 -> sphere unshaded")
		check(_lit(osc, "c"), "shaded 1 -> circle lit")
		check(absf(_mat(osc, "s").metallic - 0.5) < 0.001, "metallic set to 0.5")
		check(absf(_mat(osc, "s").roughness - 0.2) < 0.001, "roughness set to 0.2")
		d.dispatch("/ms/scene/r", ["new", "rect"])
		d.dispatch("/ms/scene", ["shading", "flat"])
	elif _f == 8:
		check(not _lit(osc, "s") and not _lit(osc, "c"), "shading flat -> all unshaded")
		check(not _lit(osc, "r"), "shading flat -> rect unshaded")
		d.dispatch("/ms/scene", ["shading", "shaded"])
		d.dispatch("/ms/scene/r2", ["new", "rect"])   # created while shade_mode == shaded
	elif _f == 10:
		check(_lit(osc, "s"), "shading shaded -> sphere lit")
		check(_lit(osc, "r"), "shading shaded -> rect lit")
		check(not _lit(osc, "c"), "shading shaded -> circle still flat")
		check(_lit(osc, "r2"), "rect created under shaded mode is lit (create-time honors mode)")
		d.dispatch("/ms/scene", ["shading", "auto"])
	elif _f == 12:
		check(_lit(osc, "s"), "shading auto -> sphere lit")
		check(not _lit(osc, "r"), "shading auto -> rect flat")
		check(not _lit(osc, "c"), "shading auto -> circle flat")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
