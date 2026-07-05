extends SceneTree
## Background colour for notation scores: the Background helper (parse + composite) and an end-to-end
## check that `background` fills paper behind a transparent (Verovio) score.
##   <godot> --headless --path . --script res://tools/test_notation_bg.gd
const Background := preload("res://addons/musicscene/notation/MSNotationBackground.gd")
var _f := 0
var _pass := 0
var _fail := 0

func check(c: bool, m: String) -> void:
	if c: _pass += 1; print("PASS: ", m)
	else: _fail += 1; print("FAIL: ", m)

func _approx(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.02 and abs(a.g - b.g) < 0.02 and abs(a.b - b.b) < 0.02 and abs(a.a - b.a) < 0.02

func _display_texture(n):
	if n == null:
		return null
	if "sprite" in n and n.sprite != null:
		return n.sprite.texture                      # 2D
	if "page_mat" in n and n.page_mat != null:
		return n.page_mat.albedo_texture             # 3D
	return null

func _opaque_and_dark(tex) -> Vector2i:
	var img: Image = tex.get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var opaque := 0
	var dark := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5:
				opaque += 1
				if c.r < 0.5 and c.g < 0.5 and c.b < 0.5:
					dark += 1
	return Vector2i(opaque, dark)

func _unit() -> void:
	check(Background.parse([]).a == 0.0, "parse [] -> transparent")
	check(Background.parse(["none"]).a == 0.0, "parse 'none' -> transparent")
	check(_approx(Background.parse(["white"]), Color.WHITE), "parse 'white' -> white")
	check(_approx(Background.parse(["#204080"]), Color("#204080")), "parse hex -> colour")
	check(_approx(Background.parse([1, 1, 1]), Color(1, 1, 1, 1)), "parse 1 1 1 -> white")
	check(_approx(Background.parse([0.2, 0.3, 0.4, 0.5]), Color(0.2, 0.3, 0.4, 0.5)), "parse r g b a")
	check(_approx(Background.parse(["red", 0.5]), Color(1, 0, 0, 0.5)), "parse name + alpha")

	# composite: a mostly-transparent image with one opaque black pixel, over white
	var src := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	src.fill(Color(0, 0, 0, 0))
	src.set_pixel(1, 1, Color(0, 0, 0, 1))            # one ink pixel
	var tex := ImageTexture.create_from_image(src)
	check(Background.composite(tex, Color(0, 0, 0, 0)) == tex, "composite with transparent bg is a no-op")
	var out = Background.composite(tex, Color.WHITE).get_image()
	check(_approx(out.get_pixel(0, 0), Color.WHITE), "composite: transparent area filled white")
	check(_approx(out.get_pixel(1, 1), Color.BLACK), "composite: ink pixel preserved")

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 2:
		_unit()
		osc.dispatcher.dispatch("/ms/scene/sc", ["new", "notation"])
		osc.dispatcher.dispatch("/ms/scene/sc", ["background", 1.0, 1.0, 1.0])
		osc.dispatcher.dispatch("/ms/scene/sc", ["notationData", "abc",
			"X: 1\nT: Twinkle\nM: 4/4\nL: 1/4\nK: C\nC C G G A A G2 | F F E E D D C2 |"])
	if _f > 3:
		var obj = osc.registry.get_object("sc")
		var n = obj.notation if obj != null else null
		var tex = _display_texture(n)
		if tex != null:
			var od := _opaque_and_dark(tex)
			var total := int(tex.get_size().x) * int(tex.get_size().y)
			# white background -> nearly every pixel opaque; ink -> some dark pixels
			check(od.x > total * 0.9, "background fills the page: %d/%d px opaque" % [od.x, total])
			check(od.y > 200, "score ink still visible over the background: %d dark px" % od.y)
			print("DONE pass=%d fail=%d" % [_pass, _fail])
			return true
	if _f > 600:
		check(false, "render did not complete in time")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
