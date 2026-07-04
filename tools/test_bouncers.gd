extends SceneTree
## Headless test for bouncer objects (creation now; reflection added later).
##   <godot> --headless --path . --script res://tools/test_bouncers.gd
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
		osc.dispatcher.dispatch("/gscore/scene/bmp", ["new", "bouncer"])
		var obj = osc.registry.get_object("bmp")
		check(obj != null, "bouncer object created")
		check(obj != null and obj.type_hint == "bouncer", "type_hint is bouncer")
		var body = obj.physics_adapter.body if (obj != null and obj.physics_adapter != null) else null
		check(body != null and osc.spatial.is_area(body), "bouncer body is an Area (area adapter auto-enabled)")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
