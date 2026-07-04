extends SceneTree
## Quick test of the LilyPond SVG note-position parser.
##   godot --headless --path . --script res://tools/test_lilypos.gd
func _init() -> void:
	var L = load("res://addons/musicscene/notation/MSNotationLilyPositions.gd")
	var svg := "C:/Scripts/Temp/claude/D--Projects-MusicScene/4ede0533-d976-4a03-a010-fa7d8dd4b832/scratchpad/timed.cropped.svg"
	var els = L._parse(svg)
	print("elements: ", els.size())
	for e in els:
		print("  n%d  when=%.3f  src=%d:%d  u=%.3f v=%.3f" % [e.index, e.when, e.line, e.char, e.u, e.v])
	quit()
