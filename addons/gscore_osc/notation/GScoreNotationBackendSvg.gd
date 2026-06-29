extends RefCounted
## SVG notation backend. Rasterises an SVG page at runtime via Image.load_svg_from_string.
## Works for engraver SVG output (Verovio, MuseScore, LilyPond). Supports "{page}" multi-page
## like the image backend.
##
## If the running Godot build lacks runtime SVG support, render() returns a clear error so the
## OSC client gets `/gscore/error load_failed ...` rather than a silent failure.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")

const BACKEND := "svg"
const MAX_PAGE_PROBE := 512


static func render(source: String, page: int, options: Dictionary = {}):
	var scale: float = float(options.get("scale", 2.0))
	var path := source
	var page_count := 1
	if source.contains("{page}"):
		path = source.replace("{page}", str(page))
		page_count = _count_pages(source)

	var svg_text := _read_text(path)
	if svg_text == "":
		return Result.make_error(BACKEND, "Could not read SVG: " + path)

	var img := Image.new()
	if not img.has_method("load_svg_from_string"):
		return Result.make_error(BACKEND, "Runtime SVG not supported in this Godot build")
	var err: int = img.call("load_svg_from_string", svg_text, scale)
	if err != OK:
		return Result.make_error(BACKEND, "SVG rasterisation failed (error %d): %s" % [err, path])
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
	if FileAccess.file_exists(path) or path.begins_with("res://"):
		return FileAccess.get_file_as_string(path)
	return ""
