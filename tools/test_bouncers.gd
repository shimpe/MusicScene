extends SceneTree
## Headless test for bouncer objects: creation, config, and mirror reflection (circle + box).
##   <godot> --headless --path . --script res://tools/test_bouncers.gd
var _f := 0
var _pass := 0
var _fail := 0
var _spd_before := 0.0
var _ball_reflected := false
var _ball2_reflected := false
var _ball_speed_after := 0.0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _vx(osc, id: String) -> float:
	var o = osc.registry.get_object(id)
	if o == null or o.physics_adapter == null or o.physics_adapter.body == null:
		return 0.0
	return osc.spatial.body_get_velocity(o.physics_adapter.body).x

func _speed(osc, id: String) -> float:
	var o = osc.registry.get_object(id)
	if o == null or o.physics_adapter == null or o.physics_adapter.body == null:
		return 0.0
	return osc.spatial.body_get_velocity(o.physics_adapter.body).length()

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 3:
		osc.dispatcher.dispatch("/ms/physics", ["enable", 1])
		# --- creation + config (bmp) ---
		osc.dispatcher.dispatch("/ms/scene/bmp", ["new", "bouncer"])
		var obj = osc.registry.get_object("bmp")
		check(obj != null, "bouncer object created")
		check(obj != null and obj.type_hint == "bouncer", "type_hint is bouncer")
		var body = obj.physics_adapter.body if (obj != null and obj.physics_adapter != null) else null
		check(body != null and osc.spatial.is_area(body), "bouncer body is an Area")
		osc.dispatcher.dispatch("/ms/scene/bmp/collider", ["circle", 0.15])
		var nshapes := 0
		for c in body.get_children():
			if c is CollisionShape2D or c is CollisionShape3D:
				nshapes += 1
		check(nshapes == 1, "collider override replaces the default shape (no double shape)")
		osc.dispatcher.dispatch("/ms/scene/bmp/bouncer", ["strength", 3.0, "gain", 0.9])
		check(osc.reactors._bouncers.get("bmp", {}).get("strength", -1) == 3.0, "bouncer strength stored")
		check(osc.reactors._bouncers.get("bmp", {}).get("gain", -1) == 0.9, "bouncer gain stored")
		# --- circle bouncer reflection (cb + ball, gravity off) ---
		osc.dispatcher.dispatch("/ms/scene/cb", ["new", "bouncer"])
		osc.dispatcher.dispatch("/ms/scene/cb/collider", ["circle", 0.15])
		osc.dispatcher.dispatch("/ms/scene/cb", ["pos", 0.5, 0.75, 0.0])
		osc.dispatcher.dispatch("/ms/scene/cb/bouncer", ["strength", 2.0, "gain", 1.0])
		osc.dispatcher.dispatch("/ms/scene/ball", ["new", "sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/ms/scene/ball/physics", ["gravityscale", 0.0])
		osc.dispatcher.dispatch("/ms/scene/ball/collider", ["sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball", ["pos", 0.2, 0.75, 0.0])
		osc.dispatcher.dispatch("/ms/scene/ball/physics", ["velocity", 0.6, 0.0, 0.0])
		# --- box wall reflection (wall + ball2) ---
		osc.dispatcher.dispatch("/ms/scene/wall", ["new", "bouncer"])
		osc.dispatcher.dispatch("/ms/scene/wall/collider", ["box", 0.2, 0.3, 0.3])
		osc.dispatcher.dispatch("/ms/scene/wall", ["pos", 0.5, 0.3, 0.0])
		osc.dispatcher.dispatch("/ms/scene/wall/bouncer", ["strength", 1.0, "gain", 1.0])
		osc.dispatcher.dispatch("/ms/scene/ball2", ["new", "sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball2/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/ms/scene/ball2/physics", ["gravityscale", 0.0])
		osc.dispatcher.dispatch("/ms/scene/ball2/collider", ["sphere", 0.03])
		osc.dispatcher.dispatch("/ms/scene/ball2", ["pos", 0.2, 0.3, 0.0])
		osc.dispatcher.dispatch("/ms/scene/ball2/physics", ["velocity", 0.6, 0.0, 0.0])
	if _f == 6:
		check(_vx(osc, "ball") > 0.0, "ball moving +x before contact")
		_spd_before = _speed(osc, "ball")
	if _f > 6:
		# Latch reflection whenever it happens — robust to physics-timing variance / exact contact frame.
		if not _ball_reflected and _vx(osc, "ball") < 0.0:
			_ball_reflected = true
			_ball_speed_after = _speed(osc, "ball")
		if not _ball2_reflected and _vx(osc, "ball2") < 0.0:
			_ball2_reflected = true
	if _f == 100:
		check(_ball_reflected, "ball reflected off circle bouncer (vx reversed)")
		check(_ball2_reflected, "ball2 reflected off box wall (vx reversed)")
		check(_ball_speed_after > _spd_before, "strength boosts the ball's outgoing speed above its incoming speed")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
