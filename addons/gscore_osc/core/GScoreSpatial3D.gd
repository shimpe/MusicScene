extends RefCounted
## 3D spatial backend. Owns everything dimension-specific for the 3D path: primitives
## (MeshInstance3D / Sprite3D / Label3D / Area3D), normalized<->world mapping, transforms,
## RigidBody3D/StaticBody3D/Area3D physics + Box/Sphere colliders, collision data, an auto
## Camera3D, and camera-ray picking. Selected when gscore_osc/space == "3d".
##
## Normalized space: x/y/z in [-1,1] mapped to a world cube of half-extent H (y-up, +z toward
## the camera). "world" mode uses raw Godot units; "pixels" falls back to world in 3D.

const NotationObject3D := preload("res://addons/gscore_osc/notation/GScoreNotationObject3D.gd")

const H := 5.0          # normalized half-extent in world units
const CAMERA_FOV := 60.0

var ctx = null


func _init(p_ctx) -> void:
	ctx = p_ctx


func is_3d() -> bool:
	return true


func create_objects_root() -> Node:
	var n := Node3D.new()
	n.name = "Objects3D"
	return n


func ensure_camera() -> void:
	var vp = ctx.get_viewport()
	if vp == null or vp.get_camera_3d() != null:
		return
	var cam := Camera3D.new()
	cam.name = "GScoreCamera"
	cam.fov = CAMERA_FOV
	var dist := H / tan(deg_to_rad(CAMERA_FOV * 0.5)) * 1.2
	cam.position = Vector3(0, 0, dist)   # default orientation looks down -Z toward origin
	cam.current = true
	ctx.add_child(cam)
	if ctx.verbose:
		print("[GScoreOSC] auto-created Camera3D at z=%.1f" % dist)


# --- Coordinate mapping --------------------------------------------------

func to_world_point(x: float, y: float, z: float, mode: String) -> Vector3:
	if mode == "normalized":
		return Vector3(x * H, y * H, z * H)
	return Vector3(x, y, z)


func from_world_point(p: Vector3, mode: String) -> Vector3:
	if mode == "normalized":
		return Vector3(p.x / H, p.y / H, p.z / H)
	return p


func to_world_vector(x: float, y: float, z: float, mode: String) -> Vector3:
	if mode == "normalized":
		return Vector3(x * H, y * H, z * H)
	return Vector3(x, y, z)


func from_world_vector(v: Vector3, mode: String) -> Vector3:
	if mode == "normalized":
		return Vector3(v.x / H, v.y / H, v.z / H)
	return v


func length_to_world(s: float, mode: String) -> float:
	return s * H if mode == "normalized" else s


# --- Transforms ----------------------------------------------------------

func set_position(node: Node, x: float, y: float, z: float, mode: String) -> void:
	if node is RigidBody3D:
		(node as Node3D).global_position = to_world_point(x, y, z, mode)
		# Teleport via the physics server so a simulating body doesn't revert it (mirrors 2D).
		PhysicsServer3D.body_set_state((node as RigidBody3D).get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM, (node as Node3D).global_transform)
	elif node is Node3D:
		node.global_position = to_world_point(x, y, z, mode)


func set_axis(node: Node, axis: int, value: float, mode: String) -> void:
	var cur := get_position_norm(node, mode)
	match axis:
		0: cur.x = value
		1: cur.y = value
		2: cur.z = value
	set_position(node, cur.x, cur.y, cur.z, mode)


func get_position_norm(node: Node, mode: String) -> Vector3:
	if node is Node3D:
		return from_world_point((node as Node3D).global_position, mode)
	return Vector3.ZERO


func set_scale(node: Node, sx: float, sy: float, sz: float) -> void:
	if node is Node3D:
		node.scale = Vector3(sx, sy, sz)


func get_scale(node: Node):
	return node.scale if node is Node3D else Vector3.ONE


func set_rotation(node: Node, args: Array, _mode: String) -> void:
	if not (node is Node3D):
		return
	if args.size() >= 3:
		node.rotation_degrees = Vector3(float(args[0]), float(args[1]), float(args[2]))
	elif args.size() >= 1:
		# Single value: in-plane rotation about Z (screen-facing), mirroring 2D.
		node.rotation_degrees = Vector3(0, 0, float(args[0]))


func get_rotation_deg(node: Node):
	return node.rotation_degrees if node is Node3D else Vector3.ZERO


func set_size(node: Node, w: float, h: float, mode: String) -> void:
	var ww := length_to_world(w, mode)
	var hw := length_to_world(h, mode)
	if node.has_method("gscore_set_size"):
		node.gscore_set_size(ww, hw)
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var aabb := mi.mesh.get_aabb()
		var s := mi.scale
		if aabb.size.x > 0:
			s.x = ww / aabb.size.x
		if aabb.size.y > 0:
			s.y = hw / aabb.size.y
		mi.scale = s


func get_size_norm(node: Node, mode: String) -> Vector2:
	var sz := Vector3(1, 1, 1)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		sz = mi.mesh.get_aabb().size * mi.scale
	elif node.has_method("gscore_get_world_size"):
		sz = node.gscore_get_world_size()
	if mode == "normalized":
		return Vector2(sz.x / H, sz.y / H)
	return Vector2(sz.x, sz.y)


func set_opacity(node: Node, a: float) -> void:
	if node.has_method("gscore_set_opacity"):
		node.gscore_set_opacity(a)
	elif node is MeshInstance3D:
		var mat := _material_of(node)
		var c := mat.albedo_color
		c.a = clampf(a, 0.0, 1.0)
		mat.albedo_color = c
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	elif "modulate" in node:
		var m: Color = node.modulate
		m.a = clampf(a, 0.0, 1.0)
		node.modulate = m


func get_opacity(node: Node) -> float:
	if node is MeshInstance3D and (node as MeshInstance3D).material_override is StandardMaterial3D:
		return ((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a
	if "modulate" in node:
		return node.modulate.a
	return 1.0


func set_color(node: Node, c: Color) -> void:
	if node.has_method("gscore_set_color"):
		node.gscore_set_color(c)
	elif node is MeshInstance3D:
		_material_of(node).albedo_color = c
	elif "modulate" in node:
		node.modulate = c


# --- Factory -------------------------------------------------------------

func create_primitive(type: String, args: Array) -> Node:
	match type:
		"group":
			var g := Node3D.new(); g.name = "Group"; return g
		"text":
			var l := Label3D.new(); l.name = "Text"
			if args.size() > 0:
				l.text = str(args[0])
			l.font_size = 96
			l.pixel_size = 0.01
			l.double_sided = true
			l.modulate = Color(0.9, 0.92, 1.0)
			return l
		"rect":
			var mi := MeshInstance3D.new(); mi.name = "Rect"
			var q := QuadMesh.new(); q.size = Vector2(2.0, 1.3)
			mi.mesh = q
			mi.material_override = _unshaded(Color(0.8, 0.85, 0.95))
			return mi
		"circle":
			var mi := MeshInstance3D.new(); mi.name = "Circle"
			var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0
			mi.mesh = s
			mi.material_override = _unshaded(Color(0.95, 0.55, 0.45))
			return mi
		"line":
			var mi := MeshInstance3D.new(); mi.name = "Line"
			mi.mesh = _line_mesh(args)
			mi.material_override = _unshaded(Color(0.9, 0.9, 0.95))
			return mi
		"image", "sprite":
			var sp := Sprite3D.new(); sp.name = "Sprite"
			sp.pixel_size = 0.01
			sp.double_sided = true
			sp.shaded = false
			if args.size() > 0:
				var tex := _load_texture(str(args[0]))
				if tex == null:
					ctx.error("load_failed", "/gscore/scene", "Could not load image: " + str(args[0]))
				else:
					sp.texture = tex
			return sp
		"area":
			var a := Area3D.new(); a.name = "Area"; a.monitoring = true; a.monitorable = true
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new(); box.size = Vector3(1, 1, 1)
			col.shape = box; a.add_child(col)
			return a
		"notation":
			var n := NotationObject3D.new(); n.name = "Notation"; return n
		_:
			ctx.error("bad_arguments", "/gscore/scene", "Unknown built-in type: " + type)
			return null


func create_notation(osc_id: String) -> Node:
	var n := NotationObject3D.new()
	n.name = "Notation"
	n.setup(ctx, osc_id)
	return n


func is_notation(node: Node) -> bool:
	return node is NotationObject3D


# --- Physics -------------------------------------------------------------

func is_physics_body(node: Node) -> bool:
	return node is PhysicsBody3D or node is Area3D


func make_body(kind: String) -> Node:
	match kind:
		"static":
			return StaticBody3D.new()
		"rigid":
			var rb := RigidBody3D.new()
			rb.gravity_scale = 0.0
			rb.contact_monitor = true
			rb.max_contacts_reported = 8
			return rb
		"area":
			var a := Area3D.new(); a.monitoring = true; a.monitorable = true
			return a
		_:
			return null


func find_visual_child(n: Node) -> Node:
	for c in n.get_children():
		if c is VisualInstance3D:
			return c
	return null


func gravity_world(gx: float, gy: float, gz: float, mode: String) -> Vector3:
	return to_world_vector(gx, gy, gz, mode)


func body_apply_central_force(body: Node, v) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).apply_central_force(v)


func body_apply_force(body: Node, fx: float, fy: float, fz: float, mode: String) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).apply_central_force(to_world_vector(fx, fy, fz, mode))


func body_apply_impulse(body: Node, ix: float, iy: float, iz: float, mode: String) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).apply_central_impulse(to_world_vector(ix, iy, iz, mode))


func body_apply_torque(body: Node, t: float) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).apply_torque_impulse(Vector3(0, 0, t))


func body_set_velocity(body: Node, vx: float, vy: float, vz: float, mode: String) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).linear_velocity = to_world_vector(vx, vy, vz, mode)


func body_get_velocity(body: Node):
	return (body as RigidBody3D).linear_velocity if body is RigidBody3D else Vector3.ZERO


func body_set_angular_velocity(body: Node, a: float) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).angular_velocity = Vector3(0, 0, a)


func body_set_mass(body: Node, m: float) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).mass = m


func body_get_mass(body: Node) -> float:
	return (body as RigidBody3D).mass if body is RigidBody3D else 1.0


func body_set_damping(body: Node, lin: float, ang: float) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.linear_damp = lin; rb.angular_damp = ang


func body_set_lock_rotation(body: Node, b: bool) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.axis_lock_angular_x = b
		rb.axis_lock_angular_y = b
		rb.axis_lock_angular_z = b


func body_set_freeze(body: Node, b: bool) -> void:
	if body is RigidBody3D:
		(body as RigidBody3D).freeze = b


func body_global_position(body: Node):
	return (body as Node3D).global_position if body is Node3D else Vector3.ZERO


func body_angular_velocity(body: Node) -> float:
	return (body as RigidBody3D).angular_velocity.length() if body is RigidBody3D else 0.0


func body_angle(node: Node) -> float:
	return (node as Node3D).rotation_degrees.z if node is Node3D else 0.0


func body_is_sleeping(body: Node) -> bool:
	return (body as RigidBody3D).sleeping if body is RigidBody3D else false


func physics_material(body: Node) -> PhysicsMaterial:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		if rb.physics_material_override == null:
			rb.physics_material_override = PhysicsMaterial.new()
		return rb.physics_material_override
	if body is StaticBody3D:
		var sb := body as StaticBody3D
		if sb.physics_material_override == null:
			sb.physics_material_override = PhysicsMaterial.new()
		return sb.physics_material_override
	return null


func set_layer(body: Node, value) -> void:
	if body is CollisionObject3D:
		(body as CollisionObject3D).collision_layer = ctx.physics_world.layer_bit(value)


func set_mask(body: Node, values: Array) -> void:
	if not (body is CollisionObject3D):
		return
	var mask := 0
	for v in values:
		mask |= ctx.physics_world.layer_bit(v)
	(body as CollisionObject3D).collision_mask = mask


func make_collider(kind: String, params: Array, mode: String, visual: Node = null) -> Node:
	var cs := CollisionShape3D.new()
	cs.name = "GScoreCollider"
	match kind:
		"rect", "box":
			var b := BoxShape3D.new()
			var w := length_to_world(_pf(params, 0, 0.2), mode)
			var h := length_to_world(_pf(params, 1, 0.2), mode)
			var d := length_to_world(_pf(params, 2, 0.2), mode) if params.size() > 2 else maxf(0.2, minf(w, h) * 0.5)
			b.size = Vector3(w, h, d)
			cs.shape = b
		"circle", "sphere":
			var s := SphereShape3D.new()
			s.radius = length_to_world(_pf(params, 0, 0.05), mode)
			cs.shape = s
		"auto":
			var b := BoxShape3D.new()
			var size := Vector3(1, 1, 1)
			if visual is MeshInstance3D and (visual as MeshInstance3D).mesh != null:
				var mi := visual as MeshInstance3D
				size = mi.mesh.get_aabb().size * mi.scale
			b.size = size
			cs.shape = b
		_:
			var b := BoxShape3D.new(); b.size = Vector3(0.2, 0.2, 0.2); cs.shape = b
	return cs


func collider_set_disabled(collider: Node, b: bool) -> void:
	if collider is CollisionShape3D:
		(collider as CollisionShape3D).disabled = b


func collider_set_offset(collider: Node, x: float, y: float, z: float, mode: String) -> void:
	if collider is Node3D:
		(collider as Node3D).position = to_world_vector(x, y, z, mode)


func connect_collision(adapter, body: Node) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		if not rb.body_entered.is_connected(adapter._on_enter):
			rb.body_entered.connect(adapter._on_enter)
		if not rb.body_exited.is_connected(adapter._on_exit):
			rb.body_exited.connect(adapter._on_exit)
		if not rb.sleeping_state_changed.is_connected(adapter._on_sleep):
			rb.sleeping_state_changed.connect(adapter._on_sleep)
	elif body is Area3D:
		var ar := body as Area3D
		if not ar.area_entered.is_connected(adapter._on_area_enter):
			ar.area_entered.connect(adapter._on_area_enter)
		if not ar.area_exited.is_connected(adapter._on_area_exit):
			ar.area_exited.connect(adapter._on_area_exit)
		if not ar.body_entered.is_connected(adapter._on_area_enter):
			ar.body_entered.connect(adapter._on_area_enter)
		if not ar.body_exited.is_connected(adapter._on_area_exit):
			ar.body_exited.connect(adapter._on_area_exit)


# --- Collision/event data ------------------------------------------------

func point_to_norm(p, mode: String) -> Vector3:
	return from_world_point(p, mode)


func vector_to_norm(v, mode: String) -> Vector3:
	return from_world_vector(v, mode)


# --- Input picking (camera ray) ------------------------------------------

func pick_hits(screen_pos: Vector2) -> Array:
	var out: Array = []
	var vp = ctx.get_viewport()
	var cam = vp.get_camera_3d() if vp != null else null
	if cam == null:
		return out
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	for id in ctx.registry.list_ids():
		var obj = ctx.registry.get_object(id)
		if obj == null:
			continue
		if obj.notation != null and obj.notation.has_method("raycast_regions"):
			for r in obj.notation.raycast_regions(origin, dir):
				out.append({"type": "region", "obj": obj, "region": r.region, "u": r.u, "v": r.v})
		if not obj.input_bindings.is_empty() and _ray_hits_object(obj, origin, dir):
			var nrm := get_position_norm(obj.node, ctx.mapper.app_mode)
			out.append({"type": "obj", "obj": obj, "nx": nrm.x, "ny": nrm.y})
	return out


func _ray_hits_object(obj, origin: Vector3, dir: Vector3) -> bool:
	var vis = obj.node
	if not (vis is VisualInstance3D):
		vis = find_visual_child(obj.node)
	if not (vis is VisualInstance3D):
		return false
	var aabb := (vis as VisualInstance3D).get_aabb()
	# transform AABB corners to world and test the ray against the world-space AABB.
	var xform := (vis as Node3D).global_transform
	var world_aabb := xform * aabb
	return _ray_aabb(origin, dir, world_aabb)


static func _ray_aabb(origin: Vector3, dir: Vector3, box: AABB) -> bool:
	var tmin := -INF
	var tmax := INF
	var bmin := box.position
	var bmax := box.position + box.size
	for i in 3:
		var o: float = origin[i]
		var d: float = dir[i]
		if absf(d) < 0.000001:
			if o < bmin[i] or o > bmax[i]:
				return false
		else:
			var t1: float = (bmin[i] - o) / d
			var t2: float = (bmax[i] - o) / d
			if t1 > t2:
				var tmp := t1; t1 = t2; t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return false
	return tmax >= maxf(tmin, 0.0)


# --- helpers -------------------------------------------------------------

func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _material_of(node: Node) -> StandardMaterial3D:
	var mi := node as MeshInstance3D
	if not (mi.material_override is StandardMaterial3D):
		mi.material_override = _unshaded(Color.WHITE)
	return mi.material_override as StandardMaterial3D


func _line_mesh(args: Array) -> Mesh:
	var pts := PackedVector3Array()
	# accept (x,y) pairs at z=0, or (x,y,z) triples if divisible by 3.
	if args.size() >= 6 and args.size() % 3 == 0:
		var i := 0
		while i + 2 < args.size():
			pts.append(Vector3(float(args[i]), float(args[i + 1]), float(args[i + 2]))); i += 3
	else:
		var j := 0
		while j + 1 < args.size():
			pts.append(Vector3(float(args[j]), float(args[j + 1]), 0.0)); j += 2
	if pts.size() < 2:
		pts = PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0)])
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pts:
		im.surface_add_vertex(p)
	im.surface_end()
	return im


func _pf(a: Array, i: int, def: float) -> float:
	if i < a.size():
		var v = a[i]
		if v is float or v is int:
			return float(v)
		if v is String and v.is_valid_float():
			return float(v)
	return def


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func is_area(node: Node) -> bool:
	return node is Area3D


func overlapping_others(node: Node) -> Array:
	if node is Area3D:
		var out: Array = []
		out.append_array((node as Area3D).get_overlapping_bodies())
		out.append_array((node as Area3D).get_overlapping_areas())
		return out
	return []


func colliding_others(node: Node) -> Array:
	if node is RigidBody3D:
		return (node as RigidBody3D).get_colliding_bodies()
	return []


func layer_names_for(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is CollisionObject3D:
		var bits: int = (node as CollisionObject3D).collision_layer
		for i in range(1, 33):
			if bits & (1 << (i - 1)):
				out.append(str(ctx.physics_world.layer_names.get(i, i)))
	return out


# --- Joints --------------------------------------------------------------

func joint_types() -> PackedStringArray:
	return PackedStringArray(["pin", "hinge", "slider", "conetwist", "generic6dof"])

func make_joint(jtype: String) -> Node:
	match jtype:
		"pin": return PinJoint3D.new()
		"hinge": return HingeJoint3D.new()
		"slider": return SliderJoint3D.new()
		"conetwist": return ConeTwistJoint3D.new()
		"generic6dof": return Generic6DOFJoint3D.new()
		_: return null

func joint_attach(joint: Node, body_a: Node, body_b: Node) -> void:
	var a := body_a as Node3D
	var b := body_b as Node3D
	if a == null or b == null:
		return
	var pa: Vector3 = a.global_position
	var dir: Vector3 = b.global_position - pa
	var j := joint as Node3D
	# Threshold is in native units (3D world units); do not equalise with the 2D backend's pixel guard.
	if dir.length() > 0.0001:
		# Build a basis whose +X points A->B (slider/hinge default working axis).
		var x_axis := dir.normalized()
		var up := Vector3.UP if absf(x_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var z_axis := x_axis.cross(up).normalized()
		var y_axis := z_axis.cross(x_axis).normalized()
		j.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), pa)
	else:
		j.global_position = pa
	joint.set("node_a", joint.get_path_to(a))
	joint.set("node_b", joint.get_path_to(b))

func joint_separation(_joint: Node, body_a: Node, body_b: Node) -> float:
	if body_a is Node3D and body_b is Node3D:
		return ((body_a as Node3D).global_position - (body_b as Node3D).global_position).length()
	return 0.0

func to_native_length(norm: float, mode: String) -> float:
	return length_to_world(norm, mode)

const J3D_STIFF_MAX := 200.0
const J3D_DAMP_MAX := 30.0

func joint_set_param(joint: Node, _jtype: String, key: String, args: Array, active_dof: String, mode: String) -> bool:
	if joint is Generic6DOFJoint3D:
		return _g6dof_param(joint as Generic6DOFJoint3D, key, args, active_dof, mode)
	match key:
		"stiffness":
			var v := clampf(_pf(args, 0, 0.0), 0.0, 1.0)
			if joint is SliderJoint3D:
				(joint as SliderJoint3D).set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_SOFTNESS, lerp(1.0, 0.1, v))
				return true
			if joint is ConeTwistJoint3D:
				(joint as ConeTwistJoint3D).set_param(ConeTwistJoint3D.PARAM_SOFTNESS, lerp(1.0, 0.1, v))
				return true
		"damping":
			var v := clampf(_pf(args, 0, 0.0), 0.0, 1.0)
			if joint is SliderJoint3D:
				(joint as SliderJoint3D).set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_DAMPING, v * J3D_DAMP_MAX)
				return true
			if joint is ConeTwistJoint3D:
				(joint as ConeTwistJoint3D).set_param(ConeTwistJoint3D.PARAM_RELAXATION, lerp(1.0, 0.1, v))
				return true
		"restlength":
			if joint is SliderJoint3D:
				return false  # SliderJoint3D has no spring; restLength is a no-op (use generic6dof for a true linear spring)
		"limit":
			if joint is HingeJoint3D:
				var h := joint as HingeJoint3D
				h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
				h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(_pf(args, 0, 0.0)))
				h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(_pf(args, 1, 0.0)))
				return true
			if joint is SliderJoint3D:
				var s := joint as SliderJoint3D
				s.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_LOWER, to_native_length(_pf(args, 0, 0.0), mode))
				s.set_param(SliderJoint3D.PARAM_LINEAR_LIMIT_UPPER, to_native_length(_pf(args, 1, 0.0), mode))
				return true
			if joint is ConeTwistJoint3D:
				var c := joint as ConeTwistJoint3D
				c.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(_pf(args, 0, 0.0)))
				c.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(_pf(args, 1, 0.0)))
				return true
		"motor":
			if joint is HingeJoint3D:
				var h := joint as HingeJoint3D
				h.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
				h.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, _pf(args, 0, 0.0))
				h.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, clampf(_pf(args, 1, 0.0), 0.0, 1.0) * J3D_STIFF_MAX)
				return true
		"axis":
			var dir := Vector3(_pf(args, 0, 1.0), _pf(args, 1, 0.0), _pf(args, 2, 0.0))
			if dir.length() > 0.0001 and joint is Node3D:
				var x_axis := dir.normalized()
				var up := Vector3.UP if absf(x_axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
				var z_axis := x_axis.cross(up).normalized()
				var y_axis := z_axis.cross(x_axis).normalized()
				var n := joint as Node3D
				n.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), n.global_position)
				return true
	return false

func _g6dof_param(j: Generic6DOFJoint3D, key: String, args: Array, dof: String, mode: String) -> bool:
	var linear := dof in ["linx", "liny", "linz", "lin", "all", ""]
	var angular := dof in ["angx", "angy", "angz", "ang", "all", ""]
	if not linear and not angular:
		return false
	var axis_idx := {"linx": 0, "liny": 1, "linz": 2, "angx": 0, "angy": 1, "angz": 2}.get(dof, -1)
	var axes := [0, 1, 2] if axis_idx < 0 else [axis_idx]
	match key:
		"limit":
			for ax in axes:
				if linear:
					_g6_set_flag(j, "linear_limit", ax, true)
					_g6_set(j, "linear_limit", ax, "lower_distance", to_native_length(_pf(args, 0, 0.0), mode))
					_g6_set(j, "linear_limit", ax, "upper_distance", to_native_length(_pf(args, 1, 0.0), mode))
				if angular:
					_g6_set_flag(j, "angular_limit", ax, true)
					_g6_set(j, "angular_limit", ax, "lower_angle", deg_to_rad(_pf(args, 0, 0.0)))
					_g6_set(j, "angular_limit", ax, "upper_angle", deg_to_rad(_pf(args, 1, 0.0)))
			return true
		"stiffness":
			var v := clampf(_pf(args, 0, 0.0), 0.0, 1.0) * J3D_STIFF_MAX
			for ax in axes:
				if linear:
					_g6_set_flag(j, "linear_spring", ax, true)
					_g6_set(j, "linear_spring", ax, "stiffness", v)
				if angular:
					_g6_set_flag(j, "angular_spring", ax, true)
					_g6_set(j, "angular_spring", ax, "stiffness", v)
			return true
		"damping":
			var v := clampf(_pf(args, 0, 0.0), 0.0, 1.0) * J3D_DAMP_MAX
			for ax in axes:
				if linear:
					_g6_set_flag(j, "linear_spring", ax, true)
					_g6_set(j, "linear_spring", ax, "damping", v)
				if angular:
					_g6_set_flag(j, "angular_spring", ax, true)
					_g6_set(j, "angular_spring", ax, "damping", v)
			return true
		"restlength":
			var d := to_native_length(_pf(args, 0, 0.0), mode)
			for ax in axes:
				if linear:
					_g6_set_flag(j, "linear_spring", ax, true)
					_g6_set(j, "linear_spring", ax, "equilibrium_point", d)
			return true
		"motor":
			for ax in axes:
				if angular:
					_g6_set_flag(j, "angular_motor", ax, true)
					_g6_set(j, "angular_motor", ax, "target_velocity", _pf(args, 0, 0.0))
					_g6_set(j, "angular_motor", ax, "force_limit", clampf(_pf(args, 1, 0.0), 0.0, 1.0) * J3D_STIFF_MAX)
			return true
	return false

func _g6_axis_name(ax: int) -> String:
	return ["x", "y", "z"][ax]

func _g6_set(j: Generic6DOFJoint3D, group: String, ax: int, prop: String, value) -> void:
	j.set("%s_%s/%s" % [group, _g6_axis_name(ax), prop], value)

func _g6_set_flag(j: Generic6DOFJoint3D, group: String, ax: int, value: bool) -> void:
	j.set("%s_%s/enabled" % [group, _g6_axis_name(ax)], value)
