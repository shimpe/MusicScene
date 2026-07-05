extends RefCounted
## Composites a solid background colour behind a (possibly transparent) score-page texture. Scores
## engraved from transparent SVG/PNG — e.g. Verovio, which draws ink on a transparent page — otherwise
## show nothing behind the notes. Dimension-agnostic: the 2D sprite and the 3D page material both
## display whatever this returns, so one code path covers both.

## Return `tex` with `color` filled behind it. A fully transparent colour (a <= 0) or a null texture
## returns `tex` unchanged (no allocation), preserving the transparent-by-default behaviour.
static func composite(tex: Texture2D, color: Color) -> Texture2D:
	if tex == null or color.a <= 0.0:
		return tex
	var src := tex.get_image()
	if src == null:
		return tex
	src = src.duplicate()
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var bg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	bg.fill(color)
	bg.blend_rect(src, Rect2i(0, 0, w, h), Vector2i.ZERO)   # score (src-over) on the paper
	return ImageTexture.create_from_image(bg)


## Parse a `background` command's args into a colour. Accepts:
##   (none) / "none" / "off" / "clear" / "transparent"  -> transparent (no background)
##   "<name>" or "#rrggbb" [alpha]                        -> named/hex colour, optional 0..1 alpha
##   <r> <g> <b> [a]                                      -> component floats 0..1
static func parse(args: Array) -> Color:
	if args.is_empty():
		return Color(0, 0, 0, 0)
	var a0 = args[0]
	if a0 is String:
		var s := String(a0).strip_edges().to_lower()
		if s == "" or s == "none" or s == "off" or s == "clear" or s == "transparent":
			return Color(0, 0, 0, 0)
		var c := Color.from_string(String(a0).strip_edges(), Color.WHITE)
		if args.size() > 1 and (args[1] is float or args[1] is int):
			c.a = clampf(float(args[1]), 0.0, 1.0)
		return c
	var r := float(a0) if (a0 is float or a0 is int) else 1.0
	var g := float(args[1]) if args.size() > 1 and (args[1] is float or args[1] is int) else 1.0
	var b := float(args[2]) if args.size() > 2 and (args[2] is float or args[2] is int) else 1.0
	var al := float(args[3]) if args.size() > 3 and (args[3] is float or args[3] is int) else 1.0
	return Color(r, g, b, al)
