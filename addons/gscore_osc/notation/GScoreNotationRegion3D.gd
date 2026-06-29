class_name GScoreNotationRegion3D
extends RefCounted
## Data for an addressable notation region in the 3D backend (page-normalized [0,1] rect, y-down).
## The highlight quad is a MeshInstance3D child managed by GScoreNotationObject3D.

var region_id: String = ""
var rect_norm: Rect2 = Rect2(0.0, 0.0, 0.1, 0.1)
var measure: int = -1
var staff: int = -1
var highlight: bool = false
var fill_color: Color = Color(1.0, 0.9, 0.2, 0.35)
var bindings: Dictionary = {}     # event -> target OSC address
var node: MeshInstance3D = null   # highlight quad


func center_norm() -> Vector2:
	return rect_norm.position + rect_norm.size * 0.5


func contains_uv(u: float, v: float) -> bool:
	return rect_norm.has_point(Vector2(u, v))
