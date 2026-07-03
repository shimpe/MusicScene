extends SceneTree
## Headless test for the default lighting rig and /gscore/light commands (3D only).
##   <godot> --headless --path . --script res://tools/test_lighting.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _dir_lights(osc) -> Array:
	var out := []
	for c in osc.get_children():
		if c is DirectionalLight3D: out.append(c)
	return out

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if osc.space != "3d":
		print("DONE pass=0 fail=0")   # 3D-only test; skip in 2D
		return true
	if _f == 3:
		var lights = _dir_lights(osc)
		check(lights.size() >= 2, "key + fill DirectionalLight3D created")
		osc.spatial.ensure_lighting()   # idempotent
		check(_dir_lights(osc).size() == lights.size(), "ensure_lighting is idempotent")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
