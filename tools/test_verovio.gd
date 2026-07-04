extends SceneTree
func _init() -> void:
	var V = load("res://addons/musicscene/notation/MSNotationVerovioPositions.gd")
	var base := "C:/Scripts/Temp/claude/D--Projects-MusicScene/4ede0533-d976-4a03-a010-fa7d8dd4b832/scratchpad/"
	var pos = V._parse_svg(base + "vr_out.svg")
	var tm = V._parse_timemap(base + "vr_out.json")
	print("svg note positions: %d, timemap ids: %d" % [pos.size(), tm.size()])
	var els: Array = []
	for id in pos.keys():
		if tm.has(id):
			els.append({"id": id, "when": tm[id] / 4.0, "u": pos[id].x, "v": pos[id].y})
	els.sort_custom(func(a, b): return a.when < b.when)
	for e in els:
		print("  %s  when=%.3f  u=%.3f v=%.3f" % [e.id, e.when, e.u, e.v])
	quit()
