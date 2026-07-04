extends SceneTree
## Verifies the committed default DIRECT engraver commands (no Python wrapper).
##   godot --headless --path . --script res://tools/test_engravers.gd

func _init() -> void:
	var R = load("res://addons/musicscene/notation/MSNotationRenderer.gd")
	var Cache = load("res://addons/musicscene/notation/MSNotationCache.gd")
	Cache.clear()
	print("lilypond cmd = ", ProjectSettings.get_setting("musicscene/notation/engraver/lilypond", ""))
	print("musicxml cmd = ", ProjectSettings.get_setting("musicscene/notation/engraver/musicxml", ""))

	print("--- inline LilyPond (direct lilypond.exe) ---")
	var ly := FileAccess.get_file_as_string("res://scores/example.ly")
	var r1 = R.render(ly, "lilypond", 1, {}, true)
	print("ok=", r1.ok, " ", (r1.texture.get_size() if r1.ok else r1.error))

	print("--- inline MusicXML (direct MuseScore4.exe) ---")
	var xml := FileAccess.get_file_as_string("res://scores/example.musicxml")
	var r2 = R.render(xml, "musicxml", 1, {}, true)
	print("ok=", r2.ok, " ", (r2.texture.get_size() if r2.ok else r2.error))
	quit()
