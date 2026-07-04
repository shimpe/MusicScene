extends RefCounted
## Parses MuseScore position exports (.mpos = measures, .spos = segments) and turns them into
## addressable regions over the rendered page. MuseScore writes element geometry in 1/1000 mm, so
## pixels = value * DPI / 25400 for a page rendered at DPI. We render the full page at a known DPI
## (so the mapping is exact), crop to the music (union of measure boxes + padding), and return the
## cropped texture plus each measure's rect in page-normalized [0,1] coordinates and its time.

const RENDER_DPI := 200.0          # -r passed to MuseScore (controls image sharpness)
const MPOS_REF_DPI := 1200.0       # MuseScore position-export reference: px = mpos * 1200/25400
const PAD_PX := Vector2(60, 90)   # padding around the content bbox (stems/slurs/dynamics)


## Build a MuseScore batch-job file: one input, full-page PNG + .mpos out. Returns the job path.
static func write_job(job_user: String, input_abs: String, png_abs: String, mpos_abs: String) -> bool:
	var job := [{"in": input_abs, "out": [png_abs, mpos_abs]}]
	var f := FileAccess.open(job_user, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(job))
	f.close()
	return true


## After MuseScore ran: load the full page, parse positions, crop to content, remap measures.
## Returns {ok, texture, measures:[{index, rect:Rect2(normalized), time}], error}.
static func finalize(png_user: String, mpos_user: String, page: int) -> Dictionary:
	var png_path := png_user
	if not FileAccess.file_exists(png_path):
		# MuseScore appends -1 to PNG page outputs.
		var stem := png_user.get_basename()
		for cand in ["%s-1.png" % stem, "%s-page1.png" % stem]:
			if FileAccess.file_exists(cand):
				png_path = cand
				break
	if not FileAccess.file_exists(png_path):
		return {"ok": false, "error": "addressable: no page image at " + png_user}

	var img := Image.new()
	if img.load(png_path) != OK:
		return {"ok": false, "error": "addressable: could not load page image"}

	var raw := parse_mpos(mpos_user)
	if raw.is_empty():
		return {"ok": false, "error": "addressable: no measures in " + mpos_user}

	# MuseScore .mpos geometry -> pixels in the rendered image. The mpos values already scale with
	# the export DPI, so the conversion uses MuseScore's fixed reference (1200), not RENDER_DPI.
	var k := MPOS_REF_DPI / 25400.0
	var page0 := page - 1   # notation pages are 1-based; MuseScore .mpos pages are 0-based
	var rects: Array = []      # {index, rect_px}
	var bbox := Rect2()
	var first := true
	for m in raw:
		if int(m.page) != page0:
			continue
		var r := Rect2(m.x * k, m.y * k, m.sx * k, m.sy * k)
		rects.append({"index": m.index, "rect_px": r, "time": m.time})
		if first:
			bbox = r
			first = false
		else:
			bbox = bbox.merge(r)
	if rects.is_empty():
		return {"ok": false, "error": "addressable: no measures on page %d (mpos has pages 0-based)" % page}

	# Crop to the content (with padding), clamped to the image.
	var full := Rect2(Vector2.ZERO, img.get_size())
	var crop := bbox.grow_individual(PAD_PX.x, PAD_PX.y, PAD_PX.x, PAD_PX.y).intersection(full)
	var crop_i := Rect2i(crop)
	if crop_i.size.x <= 0 or crop_i.size.y <= 0:
		crop_i = Rect2i(full)
	var cropped := img.get_region(crop_i)
	var tex := ImageTexture.create_from_image(cropped)

	var origin := Vector2(crop_i.position)
	var size := Vector2(crop_i.size)
	var measures: Array = []
	for e in rects:
		var rp: Rect2 = e.rect_px
		measures.append({
			"index": e.index,
			"rect": Rect2((rp.position - origin) / size, rp.size / size),
			"time": e.time,
		})
	return {"ok": true, "texture": tex, "measures": measures}


## Parse an .mpos file into [{index, x, y, sx, sy, page, time}] sorted by index.
static func parse_mpos(path: String) -> Array:
	var elements := {}
	var events := {}
	var p := XMLParser.new()
	if p.open(path) != OK:
		return []
	while p.read() == OK:
		if p.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var n := p.get_node_name()
		if n == "element":
			var id := int(p.get_named_attribute_value_safe("id"))
			elements[id] = {
				"x": float(p.get_named_attribute_value_safe("x")),
				"y": float(p.get_named_attribute_value_safe("y")),
				"sx": float(p.get_named_attribute_value_safe("sx")),
				"sy": float(p.get_named_attribute_value_safe("sy")),
				"page": int(p.get_named_attribute_value_safe("page")),
			}
		elif n == "event":
			var elid := int(p.get_named_attribute_value_safe("elid"))
			events[elid] = float(p.get_named_attribute_value_safe("position"))
	var ids := elements.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var e = elements[id]
		out.append({
			"index": id, "x": e.x, "y": e.y, "sx": e.sx, "sy": e.sy, "page": e.page,
			"time": events.get(id, 0.0),
		})
	return out
