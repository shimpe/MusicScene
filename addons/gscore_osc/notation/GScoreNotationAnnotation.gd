class_name GScoreNotationAnnotation
extends Node2D
## Lightweight text/glyph annotation over a notation page, positioned in page-normalized [0,1]
## coordinates. A child of the notation object, so it moves/scales with the score.
##
## Glyphs are drawn as text; bundle a SMuFL music font and set it on ThemeDB to render real
## music glyphs. Without one, the glyph name/character is drawn as-is.

var ann_id: String = ""
var rect_norm: Rect2 = Rect2(0.1, 0.1, 0.2, 0.1)
var page_size: Vector2 = Vector2(600, 800)
var text: String = ""
var glyph: String = ""
var text_color: Color = Color(0.1, 0.1, 0.1, 1.0)
var font_size: int = 28


func set_page_size(s: Vector2) -> void:
	page_size = s
	queue_redraw()


func local_rect() -> Rect2:
	return Rect2(
		(rect_norm.position.x - 0.5) * page_size.x,
		(rect_norm.position.y - 0.5) * page_size.y,
		rect_norm.size.x * page_size.x,
		rect_norm.size.y * page_size.y)


func _draw() -> void:
	var s := text if text != "" else glyph
	if s == "":
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var r := local_rect()
	draw_string(font, r.position + Vector2(2, font_size), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
