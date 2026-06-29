extends RefCounted
## SVG notation backend. Handles three sources:
##   - inline TEXT (a runtime-generated SVG string sent over OSC) -> rasterized via
##     Image.load_svg_from_string. This is the primary path for runtime-generated SVG scores.
##   - BYTES (SVG bytes over an OSC blob) -> decoded to text, then rasterized.
##   - a PATH: for res:// SVGs Godot's own import is preferred (reliable, matches the editor
##     preview, export-safe); for user:// / absolute paths the file text is rasterized at runtime.
##
## On failure it returns a clear error so the OSC client gets `/gscore/error load_failed ...`.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")

const BACKEND := "svg"
const MAX_PAGE_PROBE := 512


static func render(content: Dictionary, page: int, options: Dictionary = {}):
	var scale: float = float(options.get("scale", 2.0))

	if content.kind == "text":
		return _rasterize(content.text, scale, 1, "<inline svg>")
	if content.kind == "bytes":
		return _rasterize(content.bytes.get_string_from_utf8(), scale, 1, "<svg bytes>")

	# kind == "path"
	var path: String = content.path
	var page_count := 1
	if path.contains("{page}"):
		page_count = _count_pages(path)
		path = path.replace("{page}", str(page))

	# Prefer Godot's own SVG import (res:// imported textures): reliable & export-safe.
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return Result.make_ok(BACKEND, res, page_count)

	# Runtime rasterization from file text (user:// / absolute / non-imported).
	if not (path.begins_with("res://") or FileAccess.file_exists(path)):
		return Result.make_error(BACKEND, "SVG not found: " + path)
	return _rasterize(FileAccess.get_file_as_string(path), scale, page_count, path)


static func _rasterize(svg_text: String, scale: float, page_count: int, label: String):
	if svg_text.strip_edges() == "":
		return Result.make_error(BACKEND, "Empty SVG content: " + label)
	var img := Image.new()
	if not img.has_method("load_svg_from_string"):
		return Result.make_error(BACKEND, "Runtime SVG not supported in this Godot build")
	var err: int = img.call("load_svg_from_string", svg_text, scale)
	if err != OK:
		return Result.make_error(BACKEND,
			"SVG rasterisation failed (error %d). Import under res:// or export to PNG. Source: %s"
			% [err, label])
	if img.is_empty() or img.get_width() == 0 or img.get_height() == 0:
		return Result.make_error(BACKEND,
			"SVG rasterised to an empty image (needs explicit width/height): " + label)
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
