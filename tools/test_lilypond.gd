extends SceneTree
## End-to-end LilyPond engraver test (real LilyPond via addons/musicscene/tools/ly_to_score.py).
##   godot --headless --path . --script res://tools/test_lilypond.gd

func _init() -> void:
	var R = load("res://addons/musicscene/notation/MSNotationRenderer.gd")
	var Cache = load("res://addons/musicscene/notation/MSNotationCache.gd")
	Cache.clear()

	var wrapper := ProjectSettings.globalize_path("res://addons/musicscene/tools/ly_to_score.py")
	var cmd := 'py "%s" {input} {output} --page {page} --dpi 150 --lilypond "C:/Program Files/lilypond-2.25.81/bin/lilypond.exe"' % wrapper
	ProjectSettings.set_setting("musicscene/notation/engraver/lilypond", cmd)
	ProjectSettings.set_setting("musicscene/notation/engraver_output", "png")

	print("--- inline LilyPond (runtime-generated) ---")
	var ly := FileAccess.get_file_as_string("res://scores/example.ly")
	print("ly source length=", ly.length())
	var r1 = R.render(ly, "lilypond", 1, {}, true)
	print("ok=", r1.ok, " ", (r1.texture.get_size() if r1.ok else r1.error))

	print("--- LilyPond from file ---")
	var r2 = R.render("res://scores/example.ly", "lilypond", 1)
	print("ok=", r2.ok, " ", (r2.texture.get_size() if r2.ok else r2.error))

	print("--- cache info ---")
	var ci = Cache.info()
	print("cached files=", ci.count, " bytes=", ci.bytes)
	quit()
