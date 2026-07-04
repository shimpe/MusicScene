extends SceneTree
## Tests every runtime score-source path. Run:
##   godot --headless --path . --script res://tools/test_sources.gd

func _init() -> void:
	var R = load("res://addons/musicscene/notation/MSNotationRenderer.gd")

	print("--- 1. inline SVG text ---")
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200">' \
		+ '<rect width="400" height="200" fill="white"/>' \
		+ '<circle cx="200" cy="100" r="60" fill="black"/></svg>'
	var r1 = R.render(svg, "svg", 1)
	print("ok=", r1.ok, " ", (r1.texture.get_size() if r1.ok else r1.error))

	print("--- 2. PNG bytes (OSC blob) ---")
	var bytes := FileAccess.get_file_as_bytes("res://scores/page1.png")
	print("bytes len=", bytes.size())
	var r2 = R.render(bytes, "png", 1)
	print("ok=", r2.ok, " ", (r2.texture.get_size() if r2.ok else r2.error))

	print("--- 3. res:// SVG path (Godot import) ---")
	var r3 = R.render("res://scores/test.svg", "svg", 1)
	print("ok=", r3.ok, " ", (r3.texture.get_size() if r3.ok else r3.error))

	print("--- 4. external engraver (inline MusicXML via stub) ---")
	ProjectSettings.set_setting("musicscene/notation/engraver/musicxml",
		'py "D:/Projects/MusicScene/tools/stub_engraver.py" {input} {output} {format}')
	var mxml := '<?xml version="1.0"?><score-partwise><part-list/></score-partwise>'
	var r4 = R.render(mxml, "musicxml", 1)
	print("ok=", r4.ok, " ", (r4.texture.get_size() if r4.ok else r4.error))

	print("--- 5. runtime file in user:// ---")
	var f := FileAccess.open("user://runtime_score.svg", FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="300" height="150">' \
		+ '<rect width="300" height="150" fill="white"/><rect x="40" y="40" width="220" height="70" fill="black"/></svg>')
	f.close()
	var r5 = R.render("user://runtime_score.svg", "svg", 1)
	print("ok=", r5.ok, " ", (r5.texture.get_size() if r5.ok else r5.error))

	quit()
