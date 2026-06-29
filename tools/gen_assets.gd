extends SceneTree
## One-off generator for placeholder assets so the project runs out of the box.
## Run: godot --headless --script res://tools/gen_assets.gd

func _init() -> void:
	_ensure_dir("res://scores")
	_gen_score_page("res://scores/page1.png")
	print("[gen_assets] done")
	quit()


func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


func _gen_score_page(path: String) -> void:
	var w := 620
	var h := 820
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.98, 0.97, 0.93))

	var ink := Color(0.12, 0.12, 0.14)
	var margin := 60

	# Two systems, each a 5-line staff.
	var system_tops := [180, 460]
	for top in system_tops:
		for line in range(5):
			var y: int = top + line * 16
			_hline(img, margin, w - margin, y, ink)
		# bar lines
		for bx in [margin, margin + 160, margin + 320, w - margin]:
			_vline(img, bx, top, top + 4 * 16, ink)
		# a few note heads with stems
		var xs := [margin + 40, margin + 90, margin + 200, margin + 250, margin + 360, margin + 420]
		var steps := [3, 1, 2, 0, 4, 2]
		for i in range(xs.size()):
			var nx: int = xs[i]
			var ny: int = top + steps[i] * 8
			_note_head(img, nx, ny, 7, ink)
			_vline(img, nx + 7, ny - 34, ny, ink)

	# Title bar
	_rect(img, margin, 90, w - margin, 120, Color(0.85, 0.88, 0.95))
	_rect_outline(img, margin, 90, w - margin, 120, ink)

	var err := img.save_png(path)
	if err == OK:
		print("[gen_assets] wrote ", path, " (", w, "x", h, ")")
	else:
		printerr("[gen_assets] failed to write ", path, " err=", err)


func _hline(img: Image, x0: int, x1: int, y: int, c: Color) -> void:
	for x in range(x0, x1):
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, c)


func _vline(img: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(y0, y1):
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, c)


func _note_head(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r - 1, r + 2):
			# slightly elliptical note head
			if float(dx * dx) / float((r + 1) * (r + 1)) + float(dy * dy) / float(r * r) <= 1.0:
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
					img.set_pixel(x, y, c)


func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				img.set_pixel(x, y, c)


func _rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	_hline(img, x0, x1, y0, c)
	_hline(img, x0, x1, y1 - 1, c)
	_vline(img, x0, y0, y1, c)
	_vline(img, x1 - 1, y0, y1, c)
