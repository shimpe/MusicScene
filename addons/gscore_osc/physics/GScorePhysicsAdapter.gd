extends RefCounted
## Per-object physics wrapper, dimension-agnostic: all body/collider specifics go through
## ctx.spatial (GScoreSpatial2D or GScoreSpatial3D). If the object's node is already a physics
## body it is used directly; otherwise the visual node is reparented inside a freshly created
## body and the object's wrapped node becomes that body.
##
## Managed rigid bodies run with built-in gravity disabled and receive gravity as an explicit
## force from GScorePhysicsWorld, so OSC gravity control is exact and freeze/pause are clean.

const CollisionEvents := preload("res://addons/gscore_osc/physics/GScoreCollisionEvents.gd")

var obj = null
var ctx = null
var body: Node = null
var visual: Node = null
var collider: Node = null

var gravity_scale: float = 1.0
var bind_transform: bool = true
var user_frozen: bool = false
var world_frozen: bool = false


func _init(p_obj, p_ctx) -> void:
	obj = p_obj
	ctx = p_ctx


func is_valid() -> bool:
	return is_instance_valid(body)


func _base() -> String:
	return "/gscore/scene/" + obj.osc_id + "/physics"


func _pmode() -> String:
	return ctx.mapper.physics_mode


# --- Enable / body creation ----------------------------------------------

func enable(kind: String) -> void:
	var current: Node = obj.node
	if ctx.spatial.is_physics_body(current):
		body = current
		visual = ctx.spatial.find_visual_child(current)
		ctx.spatial.connect_collision(self, body)
		return

	var new_body = ctx.spatial.make_body(kind.to_lower())
	if new_body == null:
		ctx.error("bad_arguments", _base(), "Unknown body kind: " + kind)
		return
	if not (current is Node2D or current is Node3D):
		ctx.error("unsupported_type", _base(), "Cannot add physics to node type: " + current.get_class())
		new_body.free()
		return

	var parent := current.get_parent()
	var idx := current.get_index()
	var xform = current.transform
	var old_path := str(current.get_path()) if current.is_inside_tree() else ""

	parent.remove_child(current)
	if current is Node2D:
		current.transform = Transform2D.IDENTITY
	elif current is Node3D:
		current.transform = Transform3D.IDENTITY
	new_body.transform = xform
	new_body.add_child(current)
	parent.add_child(new_body)
	parent.move_child(new_body, idx)
	new_body.name = obj.osc_id + "_body"

	body = new_body
	visual = current
	obj.node = new_body
	ctx.registry.update_node_mapping(obj, old_path)
	ctx.spatial.connect_collision(self, body)
	# Auto-create a collision shape matching the visible mesh, so the body can collide and be
	# sensed by areas without a separate `collider` command. It's a one-time primitive shape
	# (no per-frame cost beyond a normal collider), and a later explicit `collider ...` replaces
	# it. Bodies connected by a joint are excluded from colliding with each other by Godot's
	# joint defaults, so this does not disturb hinge/spring setups.
	if collider == null:
		set_collider("auto", [])
	if ctx.verbose:
		print("[GScoreOSC] physics enabled (%s) on '%s'" % [kind.to_lower(), obj.osc_id])


# --- Property setters (delegate to spatial) ------------------------------

func set_mass(m: float) -> void:
	ctx.spatial.body_set_mass(body, m)

func set_friction(f: float) -> void:
	var mat = ctx.spatial.physics_material(body)
	if mat != null:
		mat.friction = f

func set_bounce(b: float) -> void:
	var mat = ctx.spatial.physics_material(body)
	if mat != null:
		mat.bounce = b

func set_damping(lin: float, ang: float) -> void:
	ctx.spatial.body_set_damping(body, lin, ang)

func set_velocity(vx: float, vy: float, vz: float) -> void:
	ctx.spatial.body_set_velocity(body, vx, vy, vz, _pmode())

func set_angular_velocity(a: float) -> void:
	ctx.spatial.body_set_angular_velocity(body, a)

func apply_force(fx: float, fy: float, fz: float) -> void:
	ctx.spatial.body_apply_force(body, fx, fy, fz, _pmode())

func apply_impulse(ix: float, iy: float, iz: float) -> void:
	ctx.spatial.body_apply_impulse(body, ix, iy, iz, _pmode())

func apply_torque(t: float) -> void:
	ctx.spatial.body_apply_torque(body, t)

func set_lock_rotation(b: bool) -> void:
	ctx.spatial.body_set_lock_rotation(body, b)

func set_planar(b: bool) -> void:
	ctx.spatial.body_set_planar(body, b)

func set_freeze(b: bool) -> void:
	user_frozen = b
	_update_freeze()

func set_world_frozen(b: bool) -> void:
	world_frozen = b
	_update_freeze()

func _update_freeze() -> void:
	ctx.spatial.body_set_freeze(body, user_frozen or world_frozen)

func set_layer(value) -> void:
	ctx.spatial.set_layer(body, value)

func set_mask(values: Array) -> void:
	ctx.spatial.set_mask(body, values)


# --- Colliders -----------------------------------------------------------

func set_collider(kind: String, params: Array) -> void:
	if body == null:
		return
	var cs = ctx.spatial.make_collider(kind, params, _pmode(), visual)
	if cs == null:
		ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/collider", "Bad collider: " + kind)
		return
	if collider != null and is_instance_valid(collider):
		collider.queue_free()
	collider = cs
	body.add_child(cs)

func set_collider_disabled(b: bool) -> void:
	ctx.spatial.collider_set_disabled(collider, b)

func set_collider_offset(x: float, y: float, z: float) -> void:
	ctx.spatial.collider_set_offset(collider, x, y, z, _pmode())

func set_debug(_b: bool) -> void:
	pass


# --- Per physics frame ---------------------------------------------------

func physics_step(_delta: float, g_world) -> void:
	if is_instance_valid(body) and not (user_frozen or world_frozen):
		var m: float = ctx.spatial.body_get_mass(body)
		ctx.spatial.body_apply_central_force(body, g_world * m * gravity_scale)
	CollisionEvents.check_continuous(ctx, obj)


# --- Collision signal handlers (connected by spatial.connect_collision) --

func _on_enter(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "collisionEnter", other)

func _on_exit(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "collisionExit", other)

func _on_area_enter(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "areaEnter", other)

func _on_area_exit(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "areaExit", other)

func _on_sleep() -> void:
	CollisionEvents.emit(ctx, obj, "sleep" if ctx.spatial.body_is_sleeping(body) else "wake", null)
