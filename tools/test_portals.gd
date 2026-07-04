extends SceneTree
## Headless test for portals: creation, config, teleport, velocity-preservation, cooldown, multi-target.
##   <godot> --headless --path . --script res://tools/test_portals.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _px(osc, id: String) -> float:
	var o = osc.registry.get_object(id)
	if o == null or o.physics_adapter == null or o.physics_adapter.body == null:
		return -1.0
	return osc.spatial.point_to_norm(osc.spatial.body_global_position(o.physics_adapter.body), osc.mapper.physics_mode).x

func _vx(osc, id: String) -> float:
	var o = osc.registry.get_object(id)
	if o == null or o.physics_adapter == null or o.physics_adapter.body == null:
		return 0.0
	return osc.spatial.body_get_velocity(o.physics_adapter.body).x

func _mk_portal(osc, id: String, x: float, y: float) -> void:
	osc.dispatcher.dispatch("/ms/scene/" + id, ["new", "portal"])
	osc.dispatcher.dispatch("/ms/scene/" + id + "/collider", ["circle", 0.1])
	osc.dispatcher.dispatch("/ms/scene/" + id, ["pos", x, y, 0.0])

func _mk_ball(osc, id: String, x: float, y: float) -> void:
	osc.dispatcher.dispatch("/ms/scene/" + id, ["new", "sphere", 0.03])
	osc.dispatcher.dispatch("/ms/scene/" + id + "/physics", ["enable", "rigid"])
	osc.dispatcher.dispatch("/ms/scene/" + id + "/physics", ["gravityscale", 0.0])
	osc.dispatcher.dispatch("/ms/scene/" + id + "/collider", ["sphere", 0.03])
	osc.dispatcher.dispatch("/ms/scene/" + id, ["pos", x, y, 0.0])
	osc.dispatcher.dispatch("/ms/scene/" + id + "/physics", ["velocity", 0.6, 0.0, 0.0])

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 3:
		osc.dispatcher.dispatch("/ms/physics", ["enable", 1])
		# --- creation + config (prt) ---
		osc.dispatcher.dispatch("/ms/scene/prt", ["new", "portal"])
		var obj = osc.registry.get_object("prt")
		check(obj != null, "portal object created")
		check(obj != null and obj.type_hint == "portal", "type_hint is portal")
		var body = obj.physics_adapter.body if (obj != null and obj.physics_adapter != null) else null
		check(body != null and osc.spatial.is_area(body), "portal body is an Area")
		osc.dispatcher.dispatch("/ms/scene/prt/portal", ["link", "a", "b"])
		check(osc.reactors._portals.get("prt", []) == ["a", "b"], "portal link stored")
		osc.dispatcher.dispatch("/ms/scene/prt/portal", ["unlink"])
		check(not osc.reactors._portals.has("prt"), "portal unlink clears targets")
		# --- teleport + cooldown (mutual pa <-> pb) ---
		_mk_portal(osc, "pa", 0.3, 0.5)
		_mk_portal(osc, "pb", 0.7, 0.5)
		osc.dispatcher.dispatch("/ms/scene/pa/portal", ["link", "pb"])
		osc.dispatcher.dispatch("/ms/scene/pb/portal", ["link", "pa"])
		_mk_ball(osc, "ball", 0.15, 0.5)
		# --- multi-target (qa -> qb OR qc, both at x~0.7) ---
		_mk_portal(osc, "qa", 0.3, 0.85)
		_mk_portal(osc, "qb", 0.7, 0.88)
		_mk_portal(osc, "qc", 0.7, 0.82)
		osc.dispatcher.dispatch("/ms/scene/qa/portal", ["link", "qb", "qc"])
		_mk_ball(osc, "ball2", 0.15, 0.85)
	if _f == 40:
		check(_px(osc, "ball") > 0.6, "ball teleported from A (~0.3) across to B (~0.7)")
		check(_vx(osc, "ball") > 0.0, "ball velocity preserved through the portal (+x)")
		check(_px(osc, "ball2") > 0.6, "ball2 reached one of the multi-targets (qb or qc at x~0.7)")
	if _f == 70:
		check(_px(osc, "ball") > 0.85, "cooldown prevented ping-pong: ball flew past B instead of oscillating back to A")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
