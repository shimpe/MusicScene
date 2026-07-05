extends SceneTree
## Regression: Godot's ThorVG rasteriser ignores a NESTED <svg>'s viewBox scaling (the Verovio
## "definition-scale" pattern), rendering such scores fully transparent. SvgBackend.flatten_nested_viewbox
## rewrites the nested <svg viewBox> into a <g transform="scale()"> so ThorVG draws it.
##   <godot> --headless --path . --script res://tools/test_svg_flatten.gd
const SvgBackend := preload("res://addons/musicscene/notation/MSNotationBackendSvg.gd")
var _pass := 0
var _fail := 0

func check(c: bool, m: String) -> void:
	if c: _pass += 1; print("PASS: ", m)
	else: _fail += 1; print("FAIL: ", m)

func _opaque(text: String) -> int:
	var img := Image.new()
	if img.load_svg_from_string(text, 2.0) != OK:
		return -1
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.05:
				n += 1
	return n

func _init() -> void:
	# A nested <svg viewBox> scaling a large coordinate space into a small page (Verovio-style).
	var nested := '<svg xmlns="http://www.w3.org/2000/svg" width="100px" height="100px">' \
		+ '<svg class="definition-scale" color="black" viewBox="0 0 1000 1000">' \
		+ '<rect x="100" y="100" width="800" height="800" fill="black"/></svg></svg>'
	var flat := SvgBackend.flatten_nested_viewbox(nested)
	check(flat.contains('transform="translate(') and flat.contains("scale("), "nested <svg viewBox> -> <g transform>")
	check(not flat.contains('<svg class="definition-scale"'), "inner <svg> element replaced")
	check(flat.contains('color="black"'), "presentation attrs carried onto the <g>")
	check(_opaque(flat) > 100, "flattened SVG rasterises to visible pixels (%d opaque)" % _opaque(flat))
	check(not flat.contains('stroke="currentColor"'), "no stroke injected when the SVG has no CSS stroke idiom")

	# Verovio-style: staff/bar lines are stroked ONLY via a <style> rule ThorVG ignores, so those lines
	# vanish. The adapter must re-declare the stroke on the container so ThorVG draws them.
	var styled := '<svg xmlns="http://www.w3.org/2000/svg" width="100px" height="100px">' \
		+ '<style type="text/css">#p path {stroke:currentColor}</style>' \
		+ '<svg class="definition-scale" color="black" viewBox="0 0 1000 1000">' \
		+ '<path d="M100 500 L900 500" stroke-width="20"/></svg></svg>'
	var sflat := SvgBackend.flatten_nested_viewbox(styled)
	check(sflat.contains('stroke="currentColor"'), "CSS-only stroke re-declared on the container")
	check(_opaque(sflat) > 100, "CSS-stroked line (staff) now rasterises: %d opaque" % _opaque(sflat))

	# Idempotent: flattening an already-flat SVG changes nothing.
	check(SvgBackend.flatten_nested_viewbox(flat) == flat, "flatten is idempotent")

	# Plain single <svg> (no nesting) must be untouched and still render.
	var plain := '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40"><rect x="5" y="5" width="30" height="30" fill="black"/></svg>'
	check(SvgBackend.flatten_nested_viewbox(plain) == plain, "plain SVG is a no-op")
	check(_opaque(plain) > 100, "plain SVG still rasterises")

	# viewBox false-positive guard: 'x=' inside 'viewBox=' must not be read as the x attribute.
	var tag := '<svg class="definition-scale" viewBox="0 0 1000 500">'
	check(SvgBackend._svg_attr(tag, "x") == "", "attr reader ignores 'x=' inside viewBox=")
	check(SvgBackend._svg_attr(tag, "viewBox") == "0 0 1000 500", "attr reader reads viewBox")

	print("DONE pass=%d fail=%d" % [_pass, _fail])
	quit()
