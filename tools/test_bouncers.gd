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
		osc.dispatcher.dispatch("/gscore/scene/bmp/collider", ["circle", 0.15])
		var nshapes := 0
		for c in body.get_children():
			if c is CollisionShape2D or c is CollisionShape3D:
				nshapes += 1
		check(nshapes == 1, "collider override replaces the default shape (no double shape)")
		osc.dispatcher.dispatch("/gscore/scene/bmp/bouncer", ["strength", 3.0, "gain", 0.9])
		check(osc.reactors._bouncers.get("bmp", {}).get("strength", -1) == 3.0, "bouncer strength stored")
		check(osc.reactors._bouncers.get("bmp", {}).get("gain", -1) == 0.9, "bouncer gain stored")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
