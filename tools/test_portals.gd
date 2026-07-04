extends SceneTree
## Headless test for portal objects (creation now; teleport added later).
##   <godot> --headless --path . --script res://tools/test_portals.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 3:
		osc.dispatcher.dispatch("/gscore/scene/prt", ["new", "portal"])
		var obj = osc.registry.get_object("prt")
		check(obj != null, "portal object created")
		check(obj != null and obj.type_hint == "portal", "type_hint is portal")
		var body = obj.physics_adapter.body if (obj != null and obj.physics_adapter != null) else null
		check(body != null and osc.spatial.is_area(body), "portal body is an Area (area adapter auto-enabled)")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
