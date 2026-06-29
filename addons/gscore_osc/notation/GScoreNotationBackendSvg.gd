extends RefCounted
## SVG notation backend. Two strategies, in order of reliability:
##   1. For a path Godot already imported to a Texture2D (any res:// .svg), use that import
##      directly (ResourceLoader.load). This is the same rasterization the editor thumbnail shows,
##      works in exported builds, and avoids fragile runtime parsing.
##   2. Otherwise (user://, absolute path, or non-imported file) read the text and rasterize at
##      runtime via Image.load_svg_from_string.
##
## Supports "{page}" multi-page like the image backend. On failure it returns a clear error so the
## OSC client gets `/gscore/error load_failed ...` and the Godot console logs a warning.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")

const BACKEND := "svg"
const MAX_PAGE_PROBE := 512


static func render(source: String, page: int, options: Dictionary = {}):
	var scale: float = float(options.get("scale", 2.0))
	var path := source.replace("\\", "/")
	var page_count := 1
	if path.contains("{page}"):
		page_count = _count_pages(path)
		path = path.replace("{page}", str(page))

	# 1. Prefer Godot's own SVG import (reliable; matches the editor preview).
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return Result.make_ok(BACKEND, res, page_count)

	# 2. Runtime rasterization fallback.
	var svg_text := _read_text(path)
	if svg_text == "":
		return Result.make_error(BACKEND,
			"Could not read SVG (not an imported texture and not readable as text): " + path)

	var img := Image.new()
	if not img.has_method("load_svg_from_string"):
		return Result.make_error(BACKEND, "Runtime SVG not supported in this Godot build")
	var err: int = img.call("load_svg_from_string", svg_text, scale)
	if err != OK:
		return Result.make_error(BACKEND,
			"SVG rasterisation failed (error %d). Try importing it under res://, or export to PNG. Path: %s"
			% [err, path])
	if img.is_empty() or img.get_width() == 0 or img.get_height() == 0:
		return Result.make_error(BACKEND,
			"SVG rasterised to an empty image (check the SVG has explicit width/height): " + path)
	return Result.make_ok(BACKEND, ImageTexture.create_from_image(img), page_count)


static func _count_pages(template: String) -> int:
	var n := 0
	for i in range(1, MAX_PAGE_PROBE + 1):
		var p := template.replace("{page}", str(i))
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			n = i
		else:
			break
	return maxi(1, n)


static func _read_text(path: String) -> String:
	if path.begins_with("res://") or FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""
