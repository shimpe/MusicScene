extends RefCounted
## Converts between client-facing coordinate spaces and Godot 2D pixel space.
##
## Modes (independently selectable for the app and for physics):
##   normalized : x in [-1,1] left->right, y in [-1,1] bottom->top (y-up). The viewport maps
##                to the full [-1,1] x [-1,1] square; (0,0) is the viewport centre.
##   pixels     : raw viewport pixels, origin top-left, y-down (native screen space).
##   world      : global Node2D coordinates. With no camera this is identical to pixels.
##
## Points get scale + y-flip + centre offset. Vectors (velocity / force / gravity) get only
## scale + y-flip. Lengths along x use half the viewport width; along y, half the height; a
## uniform length (radius / scale) uses half the height as the reference axis.

const VALID_MODES := ["normalized", "pixels", "world"]

var app_mode: String = "normalized"
var physics_mode: String = "normalized"
var host: Node = null  # used to query the live viewport size

var _fallback_size := Vector2(1280, 720)


func is_valid_mode(mode: String) -> bool:
	return mode in VALID_MODES


func viewport_size() -> Vector2:
	if host != null and host.is_inside_tree():
		var vp := host.get_viewport()
		if vp != null:
			var s := vp.get_visible_rect().size
			if s.x > 0 and s.y > 0:
				return s
	return _fallback_size


# --- Points (positions) --------------------------------------------------

func point_to_pixels(x: float, y: float, mode: String) -> Vector2:
	var vp := viewport_size()
	match mode:
		"normalized":
			return Vector2(vp.x * 0.5 + x * vp.x * 0.5, vp.y * 0.5 - y * vp.y * 0.5)
		_:
			return Vector2(x, y)


func point_from_pixels(p: Vector2, mode: String) -> Vector2:
	var vp := viewport_size()
	match mode:
		"normalized":
			var hx := vp.x * 0.5
			var hy := vp.y * 0.5
			return Vector2((p.x - hx) / hx, -(p.y - hy) / hy)
		_:
			return p


# --- Vectors (velocity / force / gravity) --------------------------------

func vector_to_pixels(x: float, y: float, mode: String) -> Vector2:
	var vp := viewport_size()
	match mode:
		"normalized":
			return Vector2(x * vp.x * 0.5, -y * vp.y * 0.5)
		_:
			return Vector2(x, y)


func vector_from_pixels(v: Vector2, mode: String) -> Vector2:
	var vp := viewport_size()
	match mode:
		"normalized":
			return Vector2(v.x / (vp.x * 0.5), -v.y / (vp.y * 0.5))
		_:
			return v


# --- Lengths -------------------------------------------------------------

func length_x_to_pixels(w: float, mode: String) -> float:
	if mode == "normalized":
		return w * viewport_size().x * 0.5
	return w


func length_y_to_pixels(h: float, mode: String) -> float:
	if mode == "normalized":
		return h * viewport_size().y * 0.5
	return h


## Uniform length (circle radius, uniform scale). Uses half the viewport height.
func length_to_pixels(s: float, mode: String) -> float:
	if mode == "normalized":
		return s * viewport_size().y * 0.5
	return s


func length_from_pixels(px: float, mode: String) -> float:
	if mode == "normalized":
		return px / (viewport_size().y * 0.5)
	return px
