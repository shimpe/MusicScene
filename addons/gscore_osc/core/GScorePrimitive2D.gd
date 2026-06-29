@tool
class_name GScorePrimitive2D
extends Node2D
## A single Node2D that draws one built-in visual primitive (rect / circle / line / text).
## Sizes/positions are in local pixels; the GScoreObject wrapper handles coordinate mapping.
## Keeping all primitives as Node2D lets transforms (position/scale/rotation/modulate) and
## hit-testing work uniformly across every object type.

enum Kind { RECT, CIRCLE, LINE, TEXT }

@export var kind: int = Kind.RECT:
	set(v):
		kind = v
		queue_redraw()
@export var size: Vector2 = Vector2(80, 80):
	set(v):
		size = v
		queue_redraw()
@export var radius: float = 40.0:
	set(v):
		radius = v
		queue_redraw()
@export var points: PackedVector2Array = PackedVector2Array():
	set(v):
		points = v
		queue_redraw()
@export var line_width: float = 3.0:
	set(v):
		line_width = v
		queue_redraw()
@export var text: String = "":
	set(v):
		text = v
		queue_redraw()
@export var font_size: int = 28:
	set(v):
		font_size = v
		queue_redraw()
@export var fill_color: Color = Color(0.8, 0.85, 0.95, 1.0):
	set(v):
		fill_color = v
		queue_redraw()
@export var filled: bool = true:
	set(v):
		filled = v
		queue_redraw()


func _draw() -> void:
	match kind:
		Kind.RECT:
			var r := Rect2(-size * 0.5, size)
			if filled:
				draw_rect(r, fill_color, true)
			else:
				draw_rect(r, fill_color, false, line_width)
		Kind.CIRCLE:
			if filled:
				draw_circle(Vector2.ZERO, radius, fill_color)
			else:
				draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, fill_color, line_width)
		Kind.LINE:
			if points.size() >= 2:
				draw_polyline(points, fill_color, line_width, true)
		Kind.TEXT:
			var font := ThemeDB.fallback_font
			if font == null:
				return
			var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			# centre the text on the origin
			var pos := Vector2(-ts.x * 0.5, ts.y * 0.5 - font.get_descent(font_size))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)


# --- gscore_* API used by GScoreObject -----------------------------------

func gscore_set_size(w_px: float, h_px: float) -> void:
	size = Vector2(w_px, h_px)

func gscore_set_radius(r_px: float) -> void:
	radius = r_px

func gscore_set_color(c: Color) -> void:
	fill_color = c

func gscore_set_text(t: String) -> void:
	text = t

func gscore_get_bounds() -> Rect2:
	match kind:
		Kind.RECT:
			return Rect2(-size * 0.5, size)
		Kind.CIRCLE:
			return Rect2(-radius, -radius, radius * 2.0, radius * 2.0)
		Kind.LINE:
			if points.size() == 0:
				return Rect2()
			var mn := points[0]
			var mx := points[0]
			for p in points:
				mn = mn.min(p)
				mx = mx.max(p)
			return Rect2(mn, mx - mn).grow(line_width * 0.5)
		Kind.TEXT:
			var font := ThemeDB.fallback_font
			if font == null:
				return Rect2(-40, -14, 80, 28)
			var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			return Rect2(-ts.x * 0.5, -ts.y * 0.5, ts.x, ts.y)
	return Rect2()


## Local-space hit test (point already in this node's local coordinates).
func gscore_contains_point(local: Vector2) -> bool:
	match kind:
		Kind.CIRCLE:
			return local.length() <= radius
		Kind.LINE:
			for i in range(points.size() - 1):
				if _dist_to_segment(local, points[i], points[i + 1]) <= maxf(line_width, 6.0):
					return true
			return false
		_:
			return gscore_get_bounds().has_point(local)


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 == 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
