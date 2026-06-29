extends RefCounted
## Global 2D physics control and the router for per-object physics/collider commands.
##
## Gravity is applied by us as an explicit per-body force each physics step (managed bodies run
## with gravity_scale 0), so OSC clients get full, immediate control regardless of project
## settings, and "physics enable 0 / pause 1" cleanly freezes managed bodies.

const Adapter := preload("res://addons/gscore_osc/physics/GScorePhysicsAdapter.gd")
const Collider := preload("res://addons/gscore_osc/physics/GScoreColliderBuilder.gd")

var ctx = null

var enabled: bool = false
var paused: bool = false
var gravity_norm: Vector2 = Vector2.ZERO   # in physics coord units
var debug: bool = false
var layer_names: Dictionary = {}           # number -> name

var _adapters: Array = []                   # GScorePhysicsAdapter


func _init(p_ctx) -> void:
	ctx = p_ctx


func is_simulating() -> bool:
	return enabled and not paused


# --- Global commands -----------------------------------------------------

func handle_global(args: Array) -> void:
	var cmd := String(args[0]) if args.size() > 0 else ""
	match cmd:
		"enable":
			enabled = _b(args, 1, true)
			_apply_freeze_state()
		"pause":
			paused = _b(args, 1, true)
			_apply_freeze_state()
		"gravity":
			gravity_norm = Vector2(_f(args, 1), _f(args, 2))
		"coord":
			var mode := String(args[1]) if args.size() > 1 else ""
			if ctx.mapper.is_valid_mode(mode):
				ctx.mapper.physics_mode = mode
			else:
				ctx.error("bad_arguments", "/gscore/physics", "Bad coord mode: " + mode)
		"debug":
			debug = _b(args, 1, true)
			if ctx.is_inside_tree():
				ctx.get_tree().debug_collisions_hint = debug
			for a in _adapters:
				if a.is_valid():
					a.set_debug(debug)
		_:
			ctx.error("bad_arguments", "/gscore/physics", "Unknown physics cmd: " + cmd)


func handle_layer(args: Array) -> void:
	var num := int(_f(args, 0, 0))
	var name := String(args[1]) if args.size() > 1 else ""
	if num >= 1:
		layer_names[num] = name


func layer_bit(value) -> int:
	# Accept a layer number or a registered layer name.
	if value is int or value is float:
		return 1 << (int(value) - 1)
	var s := String(value)
	if s.is_valid_int():
		return 1 << (s.to_int() - 1)
	for num in layer_names.keys():
		if layer_names[num] == s:
			return 1 << (num - 1)
	return 1


# --- Per-object routing --------------------------------------------------

func handle_object(obj, args: Array) -> void:
	var cmd := String(args[0]) if args.size() > 0 else ""
	if cmd == "enable":
		var kind := String(args[1]) if args.size() > 1 else "rigid"
		_ensure_adapter(obj).enable(kind)
		_apply_freeze_state()
		return
	if obj.physics_adapter == null:
		ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/physics",
			"Enable physics first: /gscore/scene/%s/physics enable <static|rigid|area>" % obj.osc_id)
		return
	var a = obj.physics_adapter
	match cmd:
		"mass": a.set_mass(_f(args, 1, 1.0))
		"gravityscale", "gravityScale": a.gravity_scale = _f(args, 1, 1.0)
		"friction": a.set_friction(_f(args, 1, 0.0))
		"bounce": a.set_bounce(_f(args, 1, 0.0))
		"damping": a.set_damping(_f(args, 1, 0.0), _f(args, 2, 0.0))
		"velocity": a.set_velocity(_f(args, 1), _f(args, 2))
		"angularvelocity", "angularVelocity": a.set_angular_velocity(_f(args, 1))
		"force": a.apply_force(_f(args, 1), _f(args, 2))
		"impulse": a.apply_impulse(_f(args, 1), _f(args, 2))
		"torque": a.apply_torque(_f(args, 1))
		"lockrotation", "lockRotation": a.set_lock_rotation(_b(args, 1, true))
		"freeze": a.set_freeze(_b(args, 1, true))
		"bindtransform", "bindTransform": a.bind_transform = _b(args, 1, true)
		"layer": a.set_layer(args[1] if args.size() > 1 else 1)
		"mask": a.set_mask(args.slice(1))
		_:
			ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/physics",
				"Unknown physics cmd: " + cmd)


func handle_collider(obj, args: Array) -> void:
	if obj.physics_adapter == null:
		# Allow defining a collider then enabling; create a default rigid adapter lazily.
		_ensure_adapter(obj)
	var a = obj.physics_adapter
	var cmd := String(args[0]) if args.size() > 0 else ""
	match cmd:
		"auto": a.set_collider(Collider.auto(a.visual, ctx.mapper, ctx.mapper.physics_mode))
		"rect": a.set_collider(Collider.rect(_f(args, 1, 0.1), _f(args, 2, 0.1), ctx.mapper, ctx.mapper.physics_mode))
		"circle": a.set_collider(Collider.circle(_f(args, 1, 0.05), ctx.mapper, ctx.mapper.physics_mode))
		"polygon": a.set_collider(Collider.polygon(args.slice(1), ctx.mapper, ctx.mapper.physics_mode))
		"disabled": a.set_collider_disabled(_b(args, 1, true))
		"offset": a.set_collider_offset(_f(args, 1), _f(args, 2))
		_:
			ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/collider",
				"Unknown collider cmd: " + cmd)


func _ensure_adapter(obj):
	if obj.physics_adapter == null:
		var a = Adapter.new(obj, ctx)
		obj.physics_adapter = a
		_adapters.append(a)
	return obj.physics_adapter


func register_adapter(a) -> void:
	if a not in _adapters:
		_adapters.append(a)


func remove_adapter(a) -> void:
	_adapters.erase(a)


# --- Per-frame -----------------------------------------------------------

func physics_step(delta: float) -> void:
	# Prune dead adapters.
	for i in range(_adapters.size() - 1, -1, -1):
		if not _adapters[i].is_valid():
			_adapters.remove_at(i)
	if not is_simulating():
		return
	var g_px: Vector2 = ctx.mapper.vector_to_pixels(gravity_norm.x, gravity_norm.y, ctx.mapper.physics_mode)
	for a in _adapters:
		a.physics_step(delta, g_px)


func _apply_freeze_state() -> void:
	var sim := is_simulating()
	for a in _adapters:
		if a.is_valid():
			a.set_world_frozen(not sim)


# --- helpers -------------------------------------------------------------

func _f(args: Array, i: int, def: float = 0.0) -> float:
	if i < args.size():
		var x = args[i]
		if x is float or x is int:
			return float(x)
		if x is String and x.is_valid_float():
			return float(x)
	return def


func _b(args: Array, i: int, def: bool = false) -> bool:
	if i >= args.size():
		return def
	var x = args[i]
	if x is bool:
		return x
	if x is int or x is float:
		return float(x) != 0.0
	if x is String:
		return x == "1" or x.to_lower() == "true"
	return def
