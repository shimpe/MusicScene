extends SceneTree
## Diagnoses SVG notation loading. Run after an editor import:
##   godot --headless --path . --script res://tools/svg_diag.gd

func _init() -> void:
	var p := "res://scores/test.svg"
	print("--- ResourceLoader (Godot's own SVG import) ---")
	print("exists=", ResourceLoader.exists(p))
	var r = ResourceLoader.load(p)
	print("load -> ", r, " is_Texture2D=", r is Texture2D, " size=", (r.get_size() if r is Texture2D else "n/a"))

	print("--- raw text + runtime load_svg_from_string ---")
	var txt := FileAccess.get_file_as_string(p)
	print("text length=", txt.length())
	var img := Image.new()
	var err: int = img.load_svg_from_string(txt, 2.0)
	print("load_svg_from_string err=", err, " size=", (img.get_size() if err == OK else Vector2i.ZERO))

	print("--- current SvgBackend ---")
	var B = load("res://addons/gscore_osc/notation/GScoreNotationBackendSvg.gd")
	var res = B.render(p, 1, {})
	print("ok=", res.ok, " err=", res.error, " texsize=", (res.texture.get_size() if res.ok else "n/a"))
	quit()
