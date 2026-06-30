extends RefCounted
## Turns Godot physics callbacks into OSC. Dimension-agnostic: positions/velocities/masses are
## read through ctx.spatial, so the same logic serves 2D and 3D. Builds the canonical event-data
## dictionary, applies the matching GScoreEventBinding (threshold, cooldown/rate, filters,
## payload), sends to the bound target, and always emits canonical /gscore/event/physics.

const PHYSICS_EVENTS := [
	"collisionEnter", "collisionExit", "areaEnter", "areaExit", "sleep", "wake",
]


static func emit(ctx, obj, event: String, other: Node) -> void:
	var data := _build_data(ctx, obj, event, other)

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
	ctx.emitter.emit(binding.target, binding.build_args(data), binding.mode, binding.quantize_grid)


static func check_continuous(ctx, obj) -> void:
	if obj.event_bindings.is_empty():
		return
	var node = obj.node
	if not (node is Node2D or node is Node3D):
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
			ctx.emitter.emit(b.target, b.build_args(data), b.mode, b.quantize_grid)
		b.state = cond

	var sb = obj.event_bindings.get("areaStay")
	if sb != null and ctx.spatial.is_area(node):
		var active := {}
		for other in ctx.spatial.overlapping_others(node):
			if not is_instance_valid(other):
				continue  # body freed (direct free()) while overlapping; skip stale ref
			var odata := _build_data(ctx, obj, "areaStay", other)
			var oid: String = odata["other"]
			active[oid] = true
			if sb.should_emit_other(odata["intensity"], odata["time"], oid, odata["layer"]):
				sb.mark_other(oid, odata["time"])
				ctx.emitter.emit(sb.target, sb.build_args(odata), sb.mode, sb.quantize_grid)
		sb.prune_others(active)


static func _build_data(ctx, obj, _event: String, other: Node) -> Dictionary:
	var node = obj.node
	var pmode: String = ctx.mapper.physics_mode
	var sp = ctx.spatial

	var pos_w = sp.body_global_position(node)
	var pos_norm: Vector3 = sp.point_to_norm(pos_w, pmode)
	var vel_w = sp.body_get_velocity(node)
	var vel_norm: Vector3 = sp.vector_to_norm(vel_w, pmode)
	var speed := vel_norm.length()
	var mass: float = sp.body_get_mass(node)

	var other_id := ""
	var other_w = pos_w
	var other_norm := Vector3.ZERO
	var other_vel_norm := Vector3.ZERO
	if other != null:
		other_id = ctx.registry.id_for_node(other)
		if other_id == "":
			other_id = str(other.name)
		other_w = sp.body_global_position(other)
		other_norm = sp.point_to_norm(other_w, pmode)
		other_vel_norm = sp.vector_to_norm(sp.body_get_velocity(other), pmode)

	var normal = pos_w - other_w
	var n = normal.normalized() if normal.length() > 0.0 else normal
	var nz: float = n.z if typeof(n) == TYPE_VECTOR3 else 0.0

	return {
		"self": obj.osc_id,
		"other": other_id,
		"x": pos_norm.x, "y": pos_norm.y, "z": pos_norm.z,
		"worldx": pos_w.x, "worldy": pos_w.y, "worldz": pos_w.z if typeof(pos_w) == TYPE_VECTOR3 else 0.0,
		"vx": vel_norm.x, "vy": vel_norm.y, "vz": vel_norm.z,
		"speed": speed, "relativespeed": speed,
		"intensity": speed,
		"impulse": speed * mass,
		"normalx": n.x, "normaly": -n.y, "normalz": nz,
		"otherx": other_norm.x, "othery": other_norm.y, "otherz": other_norm.z,
		"othervx": other_vel_norm.x, "othervy": other_vel_norm.y, "othervz": other_vel_norm.z,
		"otherspeed": other_vel_norm.length(),
		"time": float(Time.get_ticks_msec()) / 1000.0,
		"beat": ctx.transport.beat if ctx.transport != null else 0.0,
		"mass": mass,
		"angle": sp.body_angle(node),
		"angularvelocity": sp.body_angular_velocity(node),
		"layer": ",".join(sp.layer_names_for(other)) if other != null else "",
	}
