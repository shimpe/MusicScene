extends SceneTree
## End-to-end MuseScore engraver test (real MuseScore via addons/musicscene/tools/mscore_to_score.py).
##   godot --headless --path . --script res://tools/test_musescore.gd

func _init() -> void:
	var R = load("res://addons/musicscene/notation/MSNotationRenderer.gd")
	var Cache = load("res://addons/musicscene/notation/MSNotationCache.gd")
	Cache.clear()

	var wrapper := ProjectSettings.globalize_path("res://addons/musicscene/tools/mscore_to_score.py")
	var cmd := 'py "%s" {input} {output} --page {page} --dpi 150' % wrapper
	ProjectSettings.set_setting("musicscene/notation/engraver/musicxml", cmd)
	ProjectSettings.set_setting("musicscene/notation/engraver_output", "png")

	print("--- MusicXML from file ---")
	var r1 = R.render("res://scores/example.musicxml", "musicxml", 1)
	print("ok=", r1.ok, " ", (r1.texture.get_size() if r1.ok else r1.error))

	print("--- inline MusicXML (runtime-generated) ---")
	var xml := FileAccess.get_file_as_string("res://scores/example.musicxml")
	print("xml length=", xml.length())
	var r2 = R.render(xml, "musicxml", 1, {}, true)
	print("ok=", r2.ok, " ", (r2.texture.get_size() if r2.ok else r2.error))

	var ci = Cache.info()
	print("cached files=", ci.count, " bytes=", ci.bytes)
	quit()
