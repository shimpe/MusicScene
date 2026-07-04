class_name MSNotationRegion
extends Node2D
## An addressable rectangular region over a notation page, in page-normalized [0,1] coordinates
## (top-left origin, y-down). Can be highlighted and can carry event bindings (e.g. click ->
## an OSC address). v1 regions are defined manually; a future renderer could auto-generate them
## from engraver bounding boxes.

var region_id: String = ""
var rect_norm: Rect2 = Rect2(0.0, 0.0, 0.1, 0.1)
var measure: int = -1
var staff: int = -1
var page_size: Vector2 = Vector2(600, 800)
var highlight: bool = false
var fill_color: Color = Color(1.0, 0.9, 0.2, 0.3)
var bindings: Dictionary = {}   # event name -> target OSC address


func set_page_size(s: Vector2) -> void:
	page_size = s
	queue_redraw()


func set_rect_norm(r: Rect2) -> void:
	rect_norm = r
	queue_redraw()


func local_rect() -> Rect2:
	return Rect2(
		(rect_norm.position.x - 0.5) * page_size.x,
		(rect_norm.position.y - 0.5) * page_size.y,
		rect_norm.size.x * page_size.x,
		rect_norm.size.y * page_size.y)


func contains_local(p: Vector2) -> bool:
	return local_rect().has_point(p)


## Page-normalized centre of this region (for event payloads).
func center_norm() -> Vector2:
	return rect_norm.position + rect_norm.size * 0.5


func _draw() -> void:
	if not highlight:
		return
	var r := local_rect()
	draw_rect(r, fill_color, true)
	draw_rect(r, Color(fill_color.r, fill_color.g, fill_color.b, 0.9), false, 2.0)
