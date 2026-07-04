extends RefCounted
## Controls the active 3D Camera3D over OSC (/ms/camera ...). 3D only; in 2D every command errors.
## Holds per-frame tracking state (target/follow); MSRoot._process calls step(delta).

var ctx = null
var _mode: String = "none"        # none | target | follow
var _target_id: String = ""
var _offset: Vector3 = Vector3.ZERO   # world-space camera->object offset, for follow
var _up: Vector3 = Vector3(0, 1, 0)

func _init(p_ctx) -> void:
	ctx = p_ctx

func _cam():
	if not ctx.spatial.is_3d():
		return null
	ctx.spatial.ensure_camera()
	var vp = ctx.get_viewport()
	return vp.get_camera_3d() if vp != null else null

func handle(rest, args: Array) -> void:
	if not ctx.spatial.is_3d():
		ctx.error("bad_arguments", "/ms/camera", "camera control is only available in 3d space")
		return
	var verb: String
	var p: Array
	if rest.size() > 0:
		verb = str(rest[0]).to_lower(); p = args
	else:
		verb = str(args[0]).to_lower() if args.size() > 0 else ""; p = args.slice(1)
	var cam = _cam()
	if cam == null:
		ctx.error("internal_error", "/ms/camera", "no active camera"); return
	var mode: String = ctx.mapper.app_mode
	match verb:
		"pos":
			cam.global_position = ctx.spatial.to_world_point(_f(p, 0), _f(p, 1), _f(p, 2), mode)
			_mode = "none"
		"lookat":
			_aim(cam, ctx.spatial.to_world_point(_f(p, 0), _f(p, 1), _f(p, 2), mode))
			_mode = "none"
		"up":
			var u := Vector3(_f(p, 0), _f(p, 1, 1.0), _f(p, 2))
			_up = u.normalized() if u.length() > 0.0001 else Vector3(0, 1, 0)
		"target":
			var candidate := str(p[0]) if p.size() > 0 else ""
			if ctx.registry.get_object(candidate) == null:
				ctx.error("unknown_object", "/ms/camera", "Unknown target: " + candidate); return
			_target_id = candidate
			_mode = "target"
		"follow":
			_start_follow(cam, p, mode)
		"fov":
			cam.fov = _f(p, 0, 60.0)
		"projection":
			_set_projection(cam, str(p[0]) if p.size() > 0 else "perspective")
		"orthosize":
			cam.size = ctx.spatial.length_to_world(_f(p, 0, 1.0), mode)
		"reset":
			reset()
		"info":
			_reply_info(cam, mode)
		_:
			ctx.error("bad_arguments", "/ms/camera", "Unknown camera cmd: " + verb)

func _aim(cam, target_world: Vector3) -> void:
	var look_dir: Vector3 = target_world - cam.global_position
	if look_dir.length() > 0.0001 and look_dir.normalized().cross(_up).length() > 0.0001:
		cam.look_at(target_world, _up)

func _set_projection(cam, s: String) -> void:
	match s.to_lower():
		"orthographic", "ortho":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE

func _start_follow(cam, p: Array, mode: String) -> void:
	var candidate := str(p[0]) if p.size() > 0 else ""
	var obj = ctx.registry.get_object(candidate)
	if obj == null or not obj.is_valid():
		ctx.error("unknown_object", "/ms/camera", "Unknown follow target: " + candidate); return
	_target_id = candidate
	_mode = "follow"
	var op: Vector3 = (obj.node as Node3D).global_position
	_offset = cam.global_position - op
	if p.size() > 1:
		var d: float = ctx.spatial.length_to_world(_f(p, 1, 0.0), mode)
		_offset = (_offset.normalized() * d) if _offset.length() > 0.0001 else Vector3(0, 0, d)
	if _offset.length() < 0.0001:
		_offset = Vector3(0, 0, ctx.spatial.default_camera_dist())

func reset() -> void:
	_mode = "none"; _target_id = ""; _up = Vector3(0, 1, 0)
	if not ctx.spatial.is_3d():
		return
	var cam = _cam()
	if cam != null:
		ctx.spatial.configure_default_camera(cam)

func step(_delta: float) -> void:
	if _mode == "none" or not ctx.spatial.is_3d():
		return
	var cam = _cam()
	if cam == null:
		return
	var obj = ctx.registry.get_object(_target_id)
	if obj == null or not obj.is_valid() or not (obj.node is Node3D):
		_mode = "none"; return
	var op: Vector3 = (obj.node as Node3D).global_position
	if _mode == "follow":
		cam.global_position = op + _offset
	_aim(cam, op)

func _reply_info(cam, mode: String) -> void:
	var np: Vector3 = ctx.spatial.from_world_point(cam.global_position, mode)
	var proj := "orthographic" if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective"
	ctx.reply("camera", ["pos", np.x, np.y, np.z, "fov", cam.fov, "projection", proj, "tracking", _mode, _target_id])

func _f(a: Array, i: int, def: float = 0.0) -> float:
	if i < a.size():
		var v = a[i]
		if v is float or v is int:
			return float(v)
		if v is String and v.is_valid_float():
			return float(v)
	return def
