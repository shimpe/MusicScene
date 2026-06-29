extends RefCounted
## Turns Godot physics callbacks into OSC. Builds the canonical event-data dictionary, applies
## the matching GScoreEventBinding (intensity threshold, cooldown/rate, filters, payload), sends
## to the bound target, and always emits the canonical /gscore/event/physics message.

const PHYSICS_EVENTS := [
	"collisionEnter", "collisionExit", "areaEnter", "areaExit", "sleep", "wake",
]


static func emit(ctx, obj, event: String, other: Node) -> void:
	var data := _build_data(ctx, obj, event, other)

	# Canonical broadcast for every physics event.
	ctx.send_event("/gscore/event/physics", [
		event, data["self"], data["other"], data["intensity"],
		data["x"], data["y"], data["vx"], data["vy"],
	])

	var binding = obj.event_bindings.get(event)
	if binding == null:
		return
	if not binding.should_emit(data["intensity"], data["time"], data["other"], data["layer"]):
		return
	binding.mark(data["time"])
	ctx.send_event(binding.target, binding.build_args(data))


## Per-frame threshold events (velocityAbove/Below, yAbove/Below). Uses the binding's
## min_intensity as the threshold and edge-detects to avoid spamming.
static func check_continuous(ctx, obj) -> void:
	if obj.event_bindings.is_empty():
		return
	var node = obj.node
	if not (node is Node2D):
		return
	var data := _build_data(ctx, obj, "continuous", null)
	var speed: float = data["speed"]
	var y: float = data["y"]
	for event in ["velocityAbove", "velocityBelow", "yAbove", "yBelow"]:
		var b = obj.event_bindings.get(event)
		if b == null:
			continue
		var cond := false
		match event:
			"velocityAbove": cond = speed > b.min_intensity
			"velocityBelow": cond = speed < b.min_intensity
			"yAbove": cond = y > b.min_intensity
			"yBelow": cond = y < b.min_intensity
		if cond and not b.state and b.should_emit(9999.0, data["time"], data["other"], data["layer"]):
			b.mark(data["time"])
			ctx.send_event(b.target, b.build_args(data))
		b.state = cond


static func _build_data(ctx, obj, event: String, other: Node) -> Dictionary:
	var node = obj.node
	var pmode: String = ctx.mapper.physics_mode
	var pos_px: Vector2 = (node as Node2D).global_position if node is Node2D else Vector2.ZERO
	var pos_norm: Vector2 = ctx.mapper.point_from_pixels(pos_px, pmode)

	var vel_px := Vector2.ZERO
	var ang_vel := 0.0
	var mass := 1.0
	if node is RigidBody2D:
		var rb := node as RigidBody2D
		vel_px = rb.linear_velocity
		ang_vel = rb.angular_velocity
		mass = rb.mass
	var vel_norm: Vector2 = ctx.mapper.vector_from_pixels(vel_px, pmode)
	var speed := vel_norm.length()

	var other_id := ""
	var other_px := pos_px
	if other != null:
		other_id = ctx.registry.id_for_node(other)
		if other_id == "":
			other_id = String(other.name)
		if other is Node2D:
			other_px = (other as Node2D).global_position

	var normal := pos_px - other_px
	var n := normal.normalized() if normal.length() > 0.0 else Vector2.ZERO

	return {
		"self": obj.osc_id,
		"other": other_id,
		"x": pos_norm.x,
		"y": pos_norm.y,
		"worldx": pos_px.x,
		"worldy": pos_px.y,
		"vx": vel_norm.x,
		"vy": vel_norm.y,
		"speed": speed,
		"relativespeed": speed,
		"intensity": speed,
		"impulse": speed * mass,
		"normalx": n.x,
		"normaly": -n.y,
		"time": float(Time.get_ticks_msec()) / 1000.0,
		"beat": ctx.transport.beat if ctx.transport != null else 0.0,
		"mass": mass,
		"angle": rad_to_deg((node as Node2D).rotation) if node is Node2D else 0.0,
		"angularvelocity": ang_vel,
		"layer": "",
	}
