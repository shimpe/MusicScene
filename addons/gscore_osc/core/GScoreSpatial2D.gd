extends RefCounted
## 2D spatial backend. Owns everything dimension-specific for the 2D path: primitive creation,
## coordinate mapping (via GScoreCoordinateMapper), transforms, 2D physics bodies/colliders,
## collision data, and pointer picking. Selected when gscore_osc/space == "2d".
##
## All other gscore subsystems are dimension-agnostic and call these methods through ctx.spatial.

const Primitive := preload("res://addons/gscore_osc/core/GScorePrimitive2D.gd")
const NotationObject := preload("res://addons/gscore_osc/notation/GScoreNotationObject.gd")
const Collider := preload("res://addons/gscore_osc/physics/GScoreColliderBuilder.gd")
const InputUtil := preload("res://addons/gscore_osc/events/GScoreInputEvents.gd")

var ctx = null


func _init(p_ctx) -> void:
	ctx = p_ctx


func is_3d() -> bool:
	return false


func create_objects_root() -> Node:
	var n := Node2D.new()
	n.name = "Objects"
	return n


func ensure_camera() -> void:
	pass  # 2D needs no camera


# --- Transforms ----------------------------------------------------------

func set_position(node: Node, x: float, y: float, _z: float, mode: String) -> void:
	var px: Vector2 = ctx.mapper.point_to_pixels(x, y, mode)
	if node is Node2D:
		node.global_position = px
	elif node is Control:
		node.set_global_position(px)


func set_axis(node: Node, axis: int, value: float, mode: String) -> void:
	if axis == 2:
		set_depth(node, value)
		return
	var cur := get_position_norm(node, mode)
	if axis == 0:
		cur.x = value
	else:
		cur.y = value
	set_position(node, cur.x, cur.y, 0.0, mode)


func set_depth(node: Node, value: float) -> void:
	if node is CanvasItem:
		node.z_index = int(value)


func get_position_norm(node: Node, mode: String) -> Vector2:
	var px := Vector2.ZERO
	if node is Node2D:
		px = node.global_position
	elif node is Control:
		px = node.global_position
	return ctx.mapper.point_from_pixels(px, mode)


func set_scale(node: Node, sx: float, sy: float, _sz: float) -> void:
	if "scale" in node:
		node.scale = Vector2(sx, sy)


func get_scale(node: Node):
	return node.scale if "scale" in node else Vector2.ONE


func set_rotation(node: Node, args: Array, _mode: String) -> void:
	var deg := float(args[0]) if args.size() > 0 else 0.0
	if "rotation" in node:
		node.rotation = deg_to_rad(deg)


func get_rotation_deg(node: Node):
	return rad_to_deg(node.rotation) if "rotation" in node else 0.0


func set_size(node: Node, w: float, h: float, mode: String) -> void:
	var wpx: float = ctx.mapper.length_x_to_pixels(w, mode)
	var hpx: float = ctx.mapper.length_y_to_pixels(h, mode)
	if node.has_method("gscore_set_size"):
		node.gscore_set_size(wpx, hpx)
	elif node is Sprite2D:
		var spr := node as Sprite2D
		if spr.texture != null:
			var t := spr.texture.get_size()
			if t.x > 0 and t.y > 0:
				spr.scale = Vector2(wpx / t.x, hpx / t.y)
	elif node is Control:
		var ctrl := node as Control
		ctrl.custom_minimum_size = Vector2(wpx, hpx)
		ctrl.size = Vector2(wpx, hpx)


func get_size_norm(node: Node, mode: String) -> Vector2:
	var px := Vector2(80, 80)
	if node is Sprite2D:
		var spr := node as Sprite2D
		if spr.texture != null:
			px = spr.texture.get_size() * spr.scale
	elif node.has_method("gscore_get_bounds"):
		px = node.gscore_get_bounds().size
	elif node is Control:
		px = (node as Control).size
	if mode == "normalized":
		var vp: Vector2 = ctx.mapper.viewport_size()
		return Vector2(px.x / (vp.x * 0.5), px.y / (vp.y * 0.5))
	return px


func set_opacity(node: Node, a: float) -> void:
	if node is CanvasItem:
		var m: Color = node.modulate
		m.a = clampf(a, 0.0, 1.0)
		node.modulate = m


func get_opacity(node: Node) -> float:
	return node.modulate.a if node is CanvasItem else 1.0


func set_color(node: Node, c: Color) -> void:
	if node.has_method("gscore_set_color"):
		node.gscore_set_color(c)
	elif node is CanvasItem:
		node.modulate = c


# --- Factory -------------------------------------------------------------

func create_primitive(type: String, args: Array) -> Node:
	match type:
		"group":
			var g := Node2D.new(); g.name = "Group"; return g
		"text":
			var p := Primitive.new(); p.kind = Primitive.Kind.TEXT; p.name = "Text"
			if args.size() > 0:
				p.text = String(args[0])
			return p
		"rect":
			var p := Primitive.new(); p.kind = Primitive.Kind.RECT; p.name = "Rect"; p.size = Vector2(120, 80)
			return p
		"circle":
			var p := Primitive.new(); p.kind = Primitive.Kind.CIRCLE; p.name = "Circle"
			p.radius = 40.0; p.fill_color = Color(0.95, 0.55, 0.45, 1.0)
			return p
		"line":
			var p := Primitive.new(); p.kind = Primitive.Kind.LINE; p.name = "Line"
			var pts := PackedVector2Array()
			var i := 0
			while i + 1 < args.size():
				pts.append(Vector2(float(args[i]), -float(args[i + 1]))); i += 2
			if pts.size() < 2:
				pts = PackedVector2Array([Vector2(-60, 0), Vector2(60, 0)])
			p.points = pts
			return p
		"image", "sprite":
			var s := Sprite2D.new(); s.name = "Sprite"; s.centered = true
			if args.size() > 0:
				var tex := _load_texture(String(args[0]))
				if tex == null:
					ctx.error("load_failed", "/gscore/scene", "Could not load image: " + String(args[0]))
				else:
					s.texture = tex
			return s
		"area":
			var a := Area2D.new(); a.name = "Area"
			var col := CollisionShape2D.new()
			var shape := RectangleShape2D.new(); shape.size = Vector2(120, 120)
			col.shape = shape; a.add_child(col)
			return a
		"notation":
			var n := NotationObject.new(); n.name = "Notation"; return n
		_:
			ctx.error("bad_arguments", "/gscore/scene", "Unknown built-in type: " + type)
			return null


func create_notation(osc_id: String) -> Node:
	var n := NotationObject.new()
	n.name = "Notation"
	n.setup(ctx, osc_id)
	return n


func is_notation(node: Node) -> bool:
	return node is NotationObject


# --- Physics -------------------------------------------------------------

func is_physics_body(node: Node) -> bool:
	return node is PhysicsBody2D or node is Area2D


func make_body(kind: String) -> Node:
	match kind:
		"static":
			return StaticBody2D.new()
		"rigid":
			var rb := RigidBody2D.new()
			rb.gravity_scale = 0.0
			rb.contact_monitor = true
			rb.max_contacts_reported = 8
			return rb
		"area":
			var a := Area2D.new(); a.monitoring = true; a.monitorable = true
			return a
		_:
			return null


func find_visual_child(n: Node) -> Node:
	for c in n.get_children():
		if c is CanvasItem and not (c is CollisionShape2D) and not (c is CollisionPolygon2D):
			return c
	return null


func gravity_world(gx: float, gy: float, _gz: float, mode: String) -> Vector2:
	return ctx.mapper.vector_to_pixels(gx, gy, mode)


func body_apply_central_force(body: Node, v) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_force(v)


func body_apply_central_impulse(body: Node, v) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_impulse(v)


func body_apply_force(body: Node, fx: float, fy: float, _fz: float, mode: String) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_force(ctx.mapper.vector_to_pixels(fx, fy, mode))


func body_apply_impulse(body: Node, ix: float, iy: float, _iz: float, mode: String) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_central_impulse(ctx.mapper.vector_to_pixels(ix, iy, mode))


func body_apply_torque(body: Node, t: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).apply_torque_impulse(t)


func body_set_velocity(body: Node, vx: float, vy: float, _vz: float, mode: String) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).linear_velocity = ctx.mapper.vector_to_pixels(vx, vy, mode)


func body_get_velocity(body: Node):
	return (body as RigidBody2D).linear_velocity if body is RigidBody2D else Vector2.ZERO


func body_set_angular_velocity(body: Node, a: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).angular_velocity = a


func body_set_mass(body: Node, m: float) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).mass = m


func body_get_mass(body: Node) -> float:
	return (body as RigidBody2D).mass if body is RigidBody2D else 1.0


func body_set_damping(body: Node, lin: float, ang: float) -> void:
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		rb.linear_damp = lin; rb.angular_damp = ang


func body_set_lock_rotation(body: Node, b: bool) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).lock_rotation = b


func body_set_freeze(body: Node, b: bool) -> void:
	if body is RigidBody2D:
		(body as RigidBody2D).freeze = b


func body_global_position(body: Node):
	return (body as Node2D).global_position if body is Node2D else Vector2.ZERO


func body_angular_velocity(body: Node) -> float:
	return (body as RigidBody2D).angular_velocity if body is RigidBody2D else 0.0


func body_angle(node: Node) -> float:
	return rad_to_deg(node.rotation) if "rotation" in node else 0.0


func physics_material(body: Node) -> PhysicsMaterial:
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


func set_layer(body: Node, value) -> void:
	if body is CollisionObject2D:
		(body as CollisionObject2D).collision_layer = ctx.physics_world.layer_bit(value)


func set_mask(body: Node, values: Array) -> void:
	if not (body is CollisionObject2D):
		return
	var mask := 0
	for v in values:
		mask |= ctx.physics_world.layer_bit(v)
	(body as CollisionObject2D).collision_mask = mask


func make_collider(kind: String, params: Array, mode: String, visual: Node = null) -> Node:
	match kind:
		"rect":
			return Collider.rect(_pf(params, 0, 0.1), _pf(params, 1, 0.1), ctx.mapper, mode)
		"circle":
			return Collider.circle(_pf(params, 0, 0.05), ctx.mapper, mode)
		"polygon":
			return Collider.polygon(params, ctx.mapper, mode)
		"auto":
			return Collider.auto(visual, ctx.mapper, mode)
		_:
			return null


func collider_set_disabled(collider: Node, b: bool) -> void:
	if collider is CollisionShape2D:
		(collider as CollisionShape2D).disabled = b


func collider_set_offset(collider: Node, x: float, y: float, _z: float, mode: String) -> void:
	if collider is Node2D:
		(collider as Node2D).position = ctx.mapper.vector_to_pixels(x, y, mode)


func connect_collision(adapter, body: Node) -> void:
	if body is RigidBody2D:
		var rb := body as RigidBody2D
		if not rb.body_entered.is_connected(adapter._on_enter):
			rb.body_entered.connect(adapter._on_enter)
		if not rb.body_exited.is_connected(adapter._on_exit):
			rb.body_exited.connect(adapter._on_exit)
		if not rb.sleeping_state_changed.is_connected(adapter._on_sleep):
			rb.sleeping_state_changed.connect(adapter._on_sleep)
	elif body is Area2D:
		var ar := body as Area2D
		if not ar.area_entered.is_connected(adapter._on_area_enter):
			ar.area_entered.connect(adapter._on_area_enter)
		if not ar.area_exited.is_connected(adapter._on_area_exit):
			ar.area_exited.connect(adapter._on_area_exit)
		if not ar.body_entered.is_connected(adapter._on_area_enter):
			ar.body_entered.connect(adapter._on_area_enter)
		if not ar.body_exited.is_connected(adapter._on_area_exit):
			ar.body_exited.connect(adapter._on_area_exit)


func body_is_sleeping(body: Node) -> bool:
	return (body as RigidBody2D).sleeping if body is RigidBody2D else false


# --- Collision/event data ------------------------------------------------

func point_to_norm(p, mode: String) -> Vector3:
	var v: Vector2 = ctx.mapper.point_from_pixels(p, mode)
	return Vector3(v.x, v.y, 0.0)


func vector_to_norm(v, mode: String) -> Vector3:
	var n: Vector2 = ctx.mapper.vector_from_pixels(v, mode)
	return Vector3(n.x, n.y, 0.0)


# --- Input picking -------------------------------------------------------

func pointer_world() -> Vector2:
	# 2D world pointer position (== screen with no camera).
	if ctx.objects_root != null and ctx.objects_root is Node2D:
		return (ctx.objects_root as Node2D).get_global_mouse_position()
	return Vector2.ZERO


func pointer_norm(mode: String) -> Vector2:
	return ctx.mapper.point_from_pixels(pointer_world(), mode)


## Returns hit descriptors under the pointer:
##   {type:"obj", obj, nx, ny}              nx,ny = pointer in normalized app coords
##   {type:"region", obj, region, u, v}     u,v   = page-normalized click position
func pick_hits(_screen_pos) -> Array:
	var gpos := pointer_world()
	var nrm: Vector2 = ctx.mapper.point_from_pixels(gpos, ctx.mapper.app_mode)
	var out: Array = []
	for id in ctx.registry.list_ids():
		var obj = ctx.registry.get_object(id)
		if obj == null:
			continue
		if obj.notation != null and obj.notation.has_method("hit_test_regions"):
			for reg in obj.notation.hit_test_regions(gpos):
				var uv := region_uv(obj, gpos)
				out.append({"type": "region", "obj": obj, "region": reg, "u": uv.x, "v": uv.y})
		if not obj.input_bindings.is_empty() and InputUtil.object_hit(obj, gpos):
			out.append({"type": "obj", "obj": obj, "nx": nrm.x, "ny": nrm.y})
	return out


func region_uv(obj, world_pos) -> Vector2:
	var n = obj.notation
	if n == null or not (n is Node2D):
		return Vector2.ZERO
	var local: Vector2 = (n as Node2D).to_local(world_pos)
	if n.page_size.x <= 0 or n.page_size.y <= 0:
		return Vector2.ZERO
	return Vector2(local.x / n.page_size.x + 0.5, local.y / n.page_size.y + 0.5)


# --- helpers -------------------------------------------------------------

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
