extends RefCounted
## Per-object physics wrapper. If the object's node is already a physics body it is used directly;
## otherwise the visual node is reparented inside a freshly created body (Static/Rigid/Area), and
## the object's wrapped node becomes that body so transforms move the whole thing.
##
## Managed rigid bodies run with gravity_scale 0 and receive gravity as an explicit force from
## GScorePhysicsWorld, so OSC gravity control is exact and freeze/pause behave predictably.

const CollisionEvents := preload("res://addons/gscore_osc/physics/GScoreCollisionEvents.gd")

var obj = null
var ctx = null
var body: Node = null
var visual: Node = null
var collider: CollisionShape2D = null

var gravity_scale: float = 1.0
var bind_transform: bool = true
var user_frozen: bool = false
var world_frozen: bool = false

# Continuous-event bookkeeping (so velocityAbove/yBelow etc. fire on threshold crossings).
var _last_below_y: Dictionary = {}


func _init(p_obj, p_ctx) -> void:
	obj = p_obj
	ctx = p_ctx


func is_valid() -> bool:
	return is_instance_valid(body)


func _base() -> String:
	return "/gscore/scene/" + obj.osc_id + "/physics"


# --- Enable / body creation ----------------------------------------------

func enable(kind: String) -> void:
	var k := kind.to_lower()
	var current: Node = obj.node

	if current is RigidBody2D or current is StaticBody2D or current is Area2D or current is CharacterBody2D:
		body = current
		visual = _find_visual_child(current)
		_connect_signals()
		return

	var new_body := _make_body(k)
	if new_body == null:
		ctx.error("bad_arguments", _base(), "Unknown body kind: " + kind)
		return

	var parent := current.get_parent()
	var idx := current.get_index()
	var xform: Transform2D = current.transform if current is Node2D else Transform2D.IDENTITY
	var old_path := str(current.get_path()) if current.is_inside_tree() else ""

	parent.remove_child(current)
	if current is Node2D:
		current.transform = Transform2D.IDENTITY
	new_body.transform = xform
	new_body.add_child(current)
	parent.add_child(new_body)
	parent.move_child(new_body, idx)
	new_body.name = obj.osc_id + "_body"

	body = new_body
	visual = current
	obj.node = new_body
	ctx.registry.update_node_mapping(obj, old_path)
	_connect_signals()
	if ctx.verbose:
		print("[GScoreOSC] physics enabled (%s) on '%s'" % [k, obj.osc_id])


func _make_body(k: String) -> Node:
	match k:
		"static":
			return StaticBody2D.new()
		"rigid":
			var rb := RigidBody2D.new()
			rb.gravity_scale = 0.0          # we apply gravity ourselves
			rb.contact_monitor = true
			rb.max_contacts_reported = 8
			return rb
		"area":
			var a := Area2D.new()
			a.monitoring = true
			a.monitorable = true
			return a
		_:
			return null


func _find_visual_child(n: Node) -> Node:
	for c in n.get_children():
		if c is CanvasItem and not (c is CollisionShape2D) and not (c is CollisionPolygon2D):
			return c
	return null


# --- Property setters ----------------------------------------------------

func set_mass(m: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).mass = m


func set_friction(f: float) -> void:
	var mat := _phys_mat()
	if mat != null:
		mat.friction = f


func set_bounce(b: float) -> void:
	var mat := _phys_mat()
	if mat != null:
		mat.bounce = b


func set_damping(lin: float, ang: float) -> void:
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		rb.linear_damp = lin
		rb.angular_damp = ang


func set_velocity(vx: float, vy: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).linear_velocity = ctx.mapper.vector_to_pixels(vx, vy, ctx.mapper.physics_mode)


func set_angular_velocity(a: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).angular_velocity = a


func apply_force(fx: float, fy: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_force(ctx.mapper.vector_to_pixels(fx, fy, ctx.mapper.physics_mode))


func apply_impulse(ix: float, iy: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_impulse(ctx.mapper.vector_to_pixels(ix, iy, ctx.mapper.physics_mode))


func apply_torque(t: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_torque_impulse(t)


func set_lock_rotation(b: bool) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).lock_rotation = b


func set_freeze(b: bool) -> void:
	user_frozen = b
	_update_freeze()


func set_world_frozen(b: bool) -> void:
	world_frozen = b
	_update_freeze()


func _update_freeze() -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).freeze = user_frozen or world_frozen


func set_layer(value) -> void:
	if body is CollisionObject2D:
		(body as CollisionObject2D).collision_layer = ctx.physics_world.layer_bit(value)


func set_mask(values: Array) -> void:
	if not (body is CollisionObject2D):
		return
	var mask := 0
	for v in values:
		mask |= ctx.physics_world.layer_bit(v)
	(body as CollisionObject2D).collision_mask = mask


func _phys_mat() -> PhysicsMaterial:
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		if rb.physics_material_override == null:
			rb.physics_material_override = PhysicsMaterial.new()
		return rb.physics_material_override
	if body is StaticBody2D:
		var sb := body as StaticBody2D
		if sb.physics_material_override == null:
			sb.physics_material_override = PhysicsMaterial.new()
		return sb.physics_material_override
	return null


# --- Colliders -----------------------------------------------------------

func set_collider(cs: CollisionShape2D) -> void:
	if body == null:
		return
	# Remove previously created gscore collider.
	if collider != null and is_instance_valid(collider):
		collider.queue_free()
	collider = cs
	body.add_child(cs)


func set_collider_disabled(b: bool) -> void:
	if collider != null:
		collider.disabled = b


func set_collider_offset(x: float, y: float) -> void:
	if collider != null:
		collider.position = ctx.mapper.vector_to_pixels(x, y, ctx.mapper.physics_mode)


func set_debug(_b: bool) -> void:
	pass  # runtime collision-shape drawing relies on SceneTree.debug_collisions_hint


# --- Per physics frame ---------------------------------------------------

func physics_step(_delta: float, g_px: Vector2) -> void:
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		if not rb.freeze:
			rb.apply_central_force(g_px * rb.mass * gravity_scale)
	CollisionEvents.check_continuous(ctx, obj)


# --- Collision signal handlers ------------------------------------------

func _connect_signals() -> void:
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		if not rb.body_entered.is_connected(_on_body_entered):
			rb.body_entered.connect(_on_body_entered)
		if not rb.body_exited.is_connected(_on_body_exited):
			rb.body_exited.connect(_on_body_exited)
		if not rb.sleeping_state_changed.is_connected(_on_sleep_changed):
			rb.sleeping_state_changed.connect(_on_sleep_changed)
	elif body is Area2D:
		var ar := body as Area2D
		if not ar.area_entered.is_connected(_on_area_entered):
			ar.area_entered.connect(_on_area_entered)
		if not ar.area_exited.is_connected(_on_area_exited):
			ar.area_exited.connect(_on_area_exited)
		if not ar.body_entered.is_connected(_on_area_body_entered):
			ar.body_entered.connect(_on_area_body_entered)
		if not ar.body_exited.is_connected(_on_area_body_exited):
			ar.body_exited.connect(_on_area_body_exited)


func _on_body_entered(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "collisionEnter", other)

func _on_body_exited(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "collisionExit", other)

func _on_area_entered(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "areaEnter", other)

func _on_area_exited(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "areaExit", other)

func _on_area_body_entered(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "areaEnter", other)

func _on_area_body_exited(other: Node) -> void:
	CollisionEvents.emit(ctx, obj, "areaExit", other)

func _on_sleep_changed() -> void:
	if body is RigidBody2D:
		var ev := "sleep" if (body as RigidBody2D).sleeping else "wake"
		CollisionEvents.emit(ctx, obj, ev, null)
