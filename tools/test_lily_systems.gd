extends SceneTree
## Regression: LilyPond addressable must split a multi-system page into per-system vertical bands, so
## the follow cursor stays in the current line instead of spanning the whole page. _build_systems marks
## a new system where the horizontal position u resets leftward. Needs no LilyPond/render. fail=0 = ok.
const Lily := preload("res://addons/musicscene/notation/MSNotationLilyPositions.gd")

func _init() -> void:
	# system 0 across the top (u rises 0.10->0.90, v ~0.2), then u resets for system 1 (v ~0.7)
	var els := [
		{"index": 0, "u": 0.10, "v": 0.20}, {"index": 1, "u": 0.50, "v": 0.25}, {"index": 2, "u": 0.90, "v": 0.20},
		{"index": 3, "u": 0.12, "v": 0.70}, {"index": 4, "u": 0.55, "v": 0.72}, {"index": 5, "u": 0.80, "v": 0.68},
	]
	var systems := Lily._build_systems(els)
	var fails := 0
	if systems.size() != 2:
		fails += 1; print("FAIL: expected 2 systems, got ", systems.size())
	if int(els[0].sys) != 0 or int(els[2].sys) != 0 or int(els[3].sys) != 1 or int(els[5].sys) != 1:
		fails += 1; print("FAIL: sys stamping wrong: ", els.map(func(e): return int(e.sys)))
	if systems.size() == 2 and float(systems[0].bottom) > float(systems[1].top):
		fails += 1; print("FAIL: system bands overlap")
	if systems.size() >= 1 and (float(systems[0].bottom) - float(systems[0].top)) > 0.8:
		fails += 1; print("FAIL: system 0 band spans nearly the whole page (the original bug)")
	print("systems=", systems.size(), " sys=", els.map(func(e): return int(e.sys)))
	print("fail=", fails)
	quit()
