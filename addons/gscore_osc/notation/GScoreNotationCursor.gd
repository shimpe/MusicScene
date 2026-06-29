class_name GScoreNotationCursor
extends Node2D
## Vertical playback cursor drawn over a notation page. Positioned in page-normalized [0,1]
## coordinates (u = horizontal). Child of the notation object, so it moves/scales with it.

var u: float = 0.1
var v: float = 0.5              # stored for measure/beat overlays; line uses full height
var page_size: Vector2 = Vector2(600, 800)
var line_color: Color = Color(1, 0, 0, 0.8)
var line_width: float = 3.0


func set_u(value: float) -> void:
	u = value
	queue_redraw()


func set_page_size(s: Vector2) -> void:
	page_size = s
	queue_redraw()


func _draw() -> void:
	var x := (u - 0.5) * page_size.x
	var half_h := page_size.y * 0.5
	draw_line(Vector2(x, -half_h), Vector2(x, half_h), line_color, line_width)
