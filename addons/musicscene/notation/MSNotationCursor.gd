class_name MSNotationCursor
extends Node2D
## Vertical playback cursor drawn over a notation page. Positioned in page-normalized [0,1]
## coordinates (u = horizontal). When the page has several staff-systems (Verovio wraps wide scores
## onto multiple lines) the line spans only the system it is in, chosen by `sys`; with no system
## data it spans the full page height.

var u: float = 0.1
var v: float = 0.5              # stored for measure/beat overlays and system selection
var sys: int = -1              # current staff-system index (-1 = span the full page)
var systems: Array = []        # [{top, bottom}] page-normalized vertical bands, top-to-bottom
var page_size: Vector2 = Vector2(600, 800)
var line_color: Color = Color(1, 0, 0, 0.8)
var line_width: float = 3.0


func set_u(value: float) -> void:
	u = value
	queue_redraw()


func set_pos(new_u: float, new_sys: int) -> void:
	u = new_u
	sys = new_sys
	queue_redraw()


func set_systems(s: Array) -> void:
	systems = s
	queue_redraw()


## Index of the staff-system whose band contains v, else the nearest, else -1 (no system data).
func sys_for_v(vv: float) -> int:
	if systems.is_empty():
		return -1
	for i in systems.size():
		if vv >= systems[i].top and vv <= systems[i].bottom:
			return i
	var best := 0
	var best_d := 1e20
	for i in systems.size():
		var d: float = absf(vv - (systems[i].top + systems[i].bottom) * 0.5)
		if d < best_d:
			best_d = d
			best = i
	return best


func set_page_size(s: Vector2) -> void:
	page_size = s
	queue_redraw()


func _draw() -> void:
	var x := (u - 0.5) * page_size.x
	var y0: float
	var y1: float
	if sys >= 0 and sys < systems.size():
		y0 = (systems[sys].top - 0.5) * page_size.y
		y1 = (systems[sys].bottom - 0.5) * page_size.y
	else:
		y0 = -page_size.y * 0.5
		y1 = page_size.y * 0.5
	draw_line(Vector2(x, y0), Vector2(x, y1), line_color, line_width)
