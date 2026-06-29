extends RefCounted
## Hit-testing helpers for mouse/touch interaction. Centralised so any visual object or notation
## region is clickable without each one needing its own Area2D.

## True if the global point hits the object's visual (works after physics-wrapping too).
static func object_hit(obj, global_point: Vector2) -> bool:
	var target := _visual_of(obj)
	if target == null:
		return false
	if target.has_method("gscore_contains_point"):
		return target.gscore_contains_point(target.to_local(global_point))
	if target is Control:
		return (target as Control).get_global_rect().has_point(global_point)
	return false


static func _visual_of(obj) -> Node:
	var node: Node = obj.node
	if node == null:
		return null
	if node.has_method("gscore_contains_point"):
		return node
	# Physics-wrapped: the drawing node is a child of the body.
	for c in node.get_children():
		if c.has_method("gscore_contains_point"):
			return c
	return node
