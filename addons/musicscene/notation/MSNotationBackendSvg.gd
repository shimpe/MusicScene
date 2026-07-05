extends RefCounted
## SVG notation backend. Handles three sources:
##   - inline TEXT (a runtime-generated SVG string sent over OSC) -> rasterized via
##     Image.load_svg_from_string. This is the primary path for runtime-generated SVG scores.
##   - BYTES (SVG bytes over an OSC blob) -> decoded to text, then rasterized.
##   - a PATH: for res:// SVGs Godot's own import is preferred (reliable, matches the editor
##     preview, export-safe); for user:// / absolute paths the file text is rasterized at runtime.
##
## On failure it returns a clear error so the OSC client gets `/ms/error load_failed ...`.

const Result := preload("res://addons/musicscene/notation/MSNotationRenderResult.gd")

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
	svg_text = flatten_nested_viewbox(svg_text)
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


## Godot's ThorVG rasteriser ignores the viewBox scaling of a NESTED <svg> — a common Verovio pattern
## (an inner `<svg class="definition-scale" viewBox="0 0 W H">` with no width/height that scales a huge
## coordinate space into the page). Such an SVG rasterises fully transparent (no error). We rewrite the
## first nested `<svg viewBox>` into an equivalent `<g transform="translate() scale()">`, which ThorVG
## DOES honour. Only the in-memory raster is changed; any on-disk SVG (used for note-position parsing)
## is left untouched. A no-op for SVGs without a nested viewBox.
static func flatten_nested_viewbox(svg: String) -> String:
	var root_open := svg.find("<svg")
	if root_open < 0:
		return svg
	var root_gt := svg.find(">", root_open)
	if root_gt < 0:
		return svg
	var root_tag := svg.substr(root_open, root_gt - root_open + 1)
	var nested_open := svg.find("<svg", root_gt + 1)
	if nested_open < 0:
		return svg                                   # no nesting -> nothing to flatten
	var nested_gt := svg.find(">", nested_open)
	if nested_gt < 0:
		return svg
	var nested_tag := svg.substr(nested_open, nested_gt - nested_open + 1)
	var vb := _svg_attr(nested_tag, "viewBox")
	if vb == "":
		return svg                                   # nested <svg> without viewBox: nothing to do
	var vbr := _viewbox(vb)
	if vbr.size.x <= 0.0 or vbr.size.y <= 0.0:
		return svg
	# The viewport the nested <svg> fills: its own width/height, else the root's pixel size.
	var vpw := _svg_len(_svg_attr(nested_tag, "width"))
	var vph := _svg_len(_svg_attr(nested_tag, "height"))
	if vpw <= 0.0 or vph <= 0.0:
		vpw = _svg_len(_svg_attr(root_tag, "width"))
		vph = _svg_len(_svg_attr(root_tag, "height"))
	if vpw <= 0.0 or vph <= 0.0:
		var rvb := _viewbox(_svg_attr(root_tag, "viewBox"))
		vpw = rvb.size.x
		vph = rvb.size.y
	if vpw <= 0.0 or vph <= 0.0:
		return svg
	var close := _matching_svg_close(svg, nested_gt + 1)
	if close < 0:
		return svg
	var sx := vpw / vbr.size.x
	var sy := vph / vbr.size.y
	var tx := _svg_len(_svg_attr(nested_tag, "x")) - vbr.position.x * sx
	var ty := _svg_len(_svg_attr(nested_tag, "y")) - vbr.position.y * sy
	var carried := ""
	for a in ["class", "color", "font-family", "font-style", "font-weight", "style"]:
		var v := _svg_attr(nested_tag, a)
		if v != "":
			carried += ' %s="%s"' % [a, v]
	var g_open := '<g%s transform="translate(%s, %s) scale(%s, %s)">' % [carried, tx, ty, sx, sy]
	return svg.substr(0, nested_open) + g_open \
		+ svg.substr(nested_gt + 1, close - (nested_gt + 1)) + "</g>" + svg.substr(close + 6)


## Index of the </svg> that matches the <svg> whose content starts at `from` (depth-tracked).
static func _matching_svg_close(svg: String, from: int) -> int:
	var depth := 1
	var i := from
	while i < svg.length():
		var open := svg.find("<svg", i)
		var shut := svg.find("</svg>", i)
		if shut < 0:
			return -1
		if open >= 0 and open < shut:
			depth += 1
			i = open + 4
		else:
			depth -= 1
			if depth == 0:
				return shut
			i = shut + 6
	return -1


## Read attribute `name="value"` from a single start-tag string (word-boundaried by a leading space).
static func _svg_attr(tag: String, name: String) -> String:
	var key := " " + name + "=\""
	var i := tag.find(key)
	if i < 0:
		return ""
	i += key.length()
	var j := tag.find("\"", i)
	return tag.substr(i, j - i) if j >= 0 else ""


## Parse an SVG length ("840px", "840", "") to a float; unknown/relative units -> 0.
static func _svg_len(s: String) -> float:
	s = s.strip_edges()
	var num := ""
	for k in s.length():
		var ch := s[k]
		if (ch >= "0" and ch <= "9") or ch == "." or ch == "-" or ch == "+" or ch == "e" or ch == "E":
			num += ch
		else:
			break
	return float(num) if num != "" else 0.0


static func _viewbox(s: String) -> Rect2:
	var parts := s.split(" ", false)
	if parts.size() < 4:
		return Rect2(0, 0, 0, 0)
	return Rect2(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


static func _count_pages(template: String) -> int:
	var n := 0
	for i in range(1, MAX_PAGE_PROBE + 1):
		var p := template.replace("{page}", str(i))
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			n = i
		else:
			break
	return maxi(1, n)
