extends RefCounted
## Builds CollisionShape2D nodes from OSC collider commands, mapping normalized/pixel/world
## sizes to Godot pixel shapes. v1 supports rect, circle, polygon and auto (from visual bounds).

const Mapper := preload("res://addons/gscore_osc/core/GScoreCoordinateMapper.gd")


static func rect(w: float, h: float, mapper, mode: String) -> CollisionShape2D:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(mapper.length_x_to_pixels(w, mode), mapper.length_y_to_pixels(h, mode))
	return _wrap(shape)


static func circle(r: float, mapper, mode: String) -> CollisionShape2D:
	var shape := CircleShape2D.new()
	shape.radius = mapper.length_to_pixels(r, mode)
	return _wrap(shape)


static func polygon(coords: Array, mapper, mode: String) -> CollisionShape2D:
	var pts := PackedVector2Array()
	var i := 0
	while i + 1 < coords.size():
		var x := float(coords[i])
		var y := float(coords[i + 1])
		# Treat polygon coordinates as offsets in the chosen coord space (y-up for normalized).
		pts.append(Vector2(mapper.length_to_pixels(x, mode), -mapper.length_to_pixels(y, mode)))
		i += 2
	var shape := ConvexPolygonShape2D.new()
	shape.points = pts
	return _wrap(shape)


static func auto(visual: Node, mapper, _mode: String) -> CollisionShape2D:
	var size := Vector2(80, 80)
	if visual != null and visual.has_method("gscore_get_bounds"):
		size = visual.gscore_get_bounds().size
	elif visual is Sprite2D and (visual as Sprite2D).texture != null:
		size = (visual as Sprite2D).texture.get_size()
	var shape := RectangleShape2D.new()
	shape.size = size
	return _wrap(shape)


static func _wrap(shape: Shape2D) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	cs.name = "GScoreCollider"
	cs.shape = shape
	return cs
