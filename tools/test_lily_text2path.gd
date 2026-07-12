extends SceneTree
## Regression: LilyPond's <text> (lyrics/dynamics/tuplet numbers) is invisible in Godot's ThorVG, so
## MSRenderQueue runs LilyPond through lily_render.py (which outlines <text> to <path>) whenever a
## fontTools Python is available. _text_to_path_python must reuse the Verovio engraver's interpreter.
## Pure string resolution — no LilyPond/Python needed, so it runs in CI. Prints fail=0 on success.
const RenderQueue := preload("res://addons/musicscene/notation/MSRenderQueue.gd")

func _init() -> void:
	var q = RenderQueue.new()
	var fails := 0

	# 1) an explicit text_to_path_python wins
	ProjectSettings.set_setting("musicscene/notation/text_to_path_python", "/custom/python3")
	if q._text_to_path_python() != "/custom/python3":
		fails += 1
		print("FAIL: explicit text_to_path_python not honoured -> '%s'" % q._text_to_path_python())

	# 2) else reuse the Verovio (mei) engraver's interpreter
	ProjectSettings.set_setting("musicscene/notation/text_to_path_python", "")
	ProjectSettings.set_setting("musicscene/notation/engraver/mei",
		"\"res://.venv/Scripts/python.exe\" \"res://addons/musicscene/tools/verovio_render.py\" {input} {output} --page {page} --text-to-path")
	var py: String = q._text_to_path_python()
	if py == "" or not py.to_lower().contains("python"):
		fails += 1
		print("FAIL: expected the Verovio interpreter, got '%s'" % py)

	print("resolved=", py)
	print("fail=", fails)
	q.free()
	quit()
