extends SceneTree
## Headless self-test: a lyric score rendered with --text-to-path shows real dark pixels
## where the lyrics sit (Godot's ThorVG renders <path> glyphs, not <text>). Prints `fail=0`
## on success (CI greps for it), `FAIL:` on any failure.

const BackendSvg := preload("res://addons/musicscene/notation/MSNotationBackendSvg.gd")

func _dark(img: Image, x0: int, y0: int, x1: int, y1: int) -> int:
	var n := 0
	for x in range(x0, x1):
		for y in range(y0, y1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var p := img.get_pixel(x, y)
				if p.a > 0.5 and p.r < 0.5 and p.g < 0.5 and p.b < 0.5:
					n += 1
	return n

func _rasterize(svg_text: String) -> Image:
	var svg := BackendSvg.flatten_nested_viewbox(svg_text)   # same transform production applies
	var img := Image.new()
	if img.load_svg_from_string(svg, 3.0) != OK:
		return null
	return img

func _init() -> void:
	var fails := 0
	var tmp := OS.get_environment("TEMP")
	if tmp == "":
		tmp = "user://"
	var mei := tmp.path_join("mslyr_test.mei")
	# a minimal lyric MEI (single voice, two syllables) — no sclang needed
	var mei_str := '<?xml version="1.0" encoding="UTF-8"?><mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score><scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp><staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef><section><measure n="1"><staff n="1"><layer n="1"><note dur="4" oct="5" pname="c"><verse n="1"><syl>morn</syl></verse></note><note dur="4" oct="5" pname="d"><verse n="1"><syl>ing</syl></verse></note></layer></staff></measure></section></score></mdiv></body></music></mei>'
	var f := FileAccess.open(mei, FileAccess.WRITE)
	if f == null:
		print("FAIL: cannot write temp MEI"); quit()
		return
	f.store_string(mei_str); f.close()

	var py := "py" if OS.get_name() == "Windows" else "python3"
	var wrap := ProjectSettings.globalize_path("res://addons/musicscene/tools/verovio_render.py")
	var svg_conv := tmp.path_join("mslyr_conv.svg")
	var svg_plain := tmp.path_join("mslyr_plain.svg")
	var out := []
	OS.execute(py, [wrap, mei, svg_conv, "--page", "1", "--text-to-path"], out, true)
	OS.execute(py, [wrap, mei, svg_plain, "--page", "1"], out, true)

	if not FileAccess.file_exists(svg_conv) or not FileAccess.file_exists(svg_plain):
		print("FAIL: verovio wrapper produced no SVG (is verovio installed?)"); print("fail=1"); quit()
		return

	var conv := FileAccess.get_file_as_string(svg_conv)
	var plain := FileAccess.get_file_as_string(svg_plain)
	# structural: converted has paths, no text; plain still has text
	if conv.contains("<text"): fails += 1; print("FAIL: converted SVG still has <text>")
	if not conv.contains("<path"): fails += 1; print("FAIL: converted SVG has no <path>")
	if not plain.contains("<text"): fails += 1; print("FAIL: plain SVG unexpectedly has no <text>")

	# rendered: the converted SVG must produce dark pixels in the lyric band (below the staff);
	# the plain one must not (ThorVG drops its <text>).
	var img_conv := _rasterize(conv)
	var img_plain := _rasterize(plain)
	if img_conv == null or img_plain == null:
		fails += 1; print("FAIL: rasterisation failed")
	else:
		# lyric band = lower third of the image, full width
		var h := img_conv.get_height(); var w := img_conv.get_width()
		var band_conv := _dark(img_conv, 0, int(h * 0.6), w, h)
		var band_plain := _dark(img_plain, 0, int(h * 0.6), w, h)
		print("lyric_band_conv=", band_conv, " lyric_band_plain=", band_plain, " size=", img_conv.get_size())
		if band_conv < 20: fails += 1; print("FAIL: no lyric pixels in the converted render")
		if band_conv <= band_plain: fails += 1; print("FAIL: converted render not darker than plain in the lyric band")

	print("fail=", fails)
	quit()
