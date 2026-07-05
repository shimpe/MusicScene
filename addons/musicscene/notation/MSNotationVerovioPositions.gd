extends RefCounted
## Verovio addressable notation. Verovio is the cleanest engraver for this: its SVG tags every note
## with a stable id (<g class="note" id="...">), and renderToTimemap() returns each id's onset time.
## We rasterize the SVG, read each note's id + page position, join with the timemap for timing, and
## get note-level addressing + following — no source-tagging tricks needed.

const SvgBackend := preload("res://addons/musicscene/notation/MSNotationBackendSvg.gd")


## After the Verovio wrapper produced <svg> + <timemap.json>: rasterize the SVG (display) and build
## note elements. Returns {ok, texture, elements:[{index, id, when, line, char, u, v}], error}.
static func finalize(svg_path: String, timemap_path: String, options: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(svg_path):
		return {"ok": false, "error": "verovio: no SVG at " + svg_path}
	var res = SvgBackend.render({"kind": "path", "path": svg_path, "text": "", "bytes": PackedByteArray()}, 1, options)
	if not res.ok:
		return {"ok": false, "error": "verovio: " + res.error}

	var positions := _parse_svg(svg_path)          # id -> {u, v, sys}
	var times := _parse_timemap(timemap_path)        # id -> qstamp (quarters)

	var elements: Array = []
	for id in positions.keys():
		if not times.has(id):
			continue
		var p: Dictionary = positions[id]
		elements.append({
			"id": id,
			"when": times[id] / 4.0,   # quarters -> whole notes (matches transport.beat/4)
			"line": -1, "char": -1,
			"u": p.u, "v": p.v, "sys_id": p.sys,
		})
	elements.sort_custom(func(a, b): return a.when < b.when)
	for i in elements.size():
		elements[i].index = i

	# group notes into staff-systems (Verovio wraps wide scores onto several) and give each a padded
	# vertical band; stamp every element with its system index so a follow cursor can stay in one system.
	var systems := _build_systems(elements)
	return {"ok": true, "texture": res.texture, "elements": elements, "systems": systems}


## Multi-page (paginate) variant: the wrapper wrote <svg_stem>-<n>.svg per page + one global timemap.
## Rasterize every page, read its note positions/systems, join with the timemap. Returns
## {ok, pages:[{texture, systems}], elements:[{index, when, u, v, sys, page}], page_count}.
static func finalize_paged(svg_stem: String, timemap_path: String, options: Dictionary = {}) -> Dictionary:
	var page_paths := _page_svgs(svg_stem)
	if page_paths.is_empty():
		return {"ok": false, "error": "verovio: no page SVGs at " + svg_stem + "-N.svg"}
	var times := _parse_timemap(timemap_path)
	var pages: Array = []
	var elements: Array = []
	for pi in page_paths.size():
		var svg_path: String = page_paths[pi]
		var res = SvgBackend.render({"kind": "path", "path": svg_path, "text": "", "bytes": PackedByteArray()}, 1, options)
		if not res.ok:
			return {"ok": false, "error": "verovio: " + res.error}
		var positions := _parse_svg(svg_path)
		var page_elements: Array = []
		for id in positions.keys():
			if not times.has(id):
				continue
			var p: Dictionary = positions[id]
			page_elements.append({
				"id": id, "when": times[id] / 4.0, "line": -1, "char": -1,
				"u": p.u, "v": p.v, "sys_id": p.sys, "page": pi + 1,
			})
		var systems := _build_systems(page_elements)   # stamps each element's sys (index within this page)
		# A fixed-size page pads blank space below the last system; crop the raster to its actual drawn
		# content (staff lines included) and rescale the note/system y's into the cropped page.
		var crop := _crop_to_content(res.texture)
		var span: float = crop.bottom - crop.top
		if span > 0.0 and span < 0.999:
			for e in page_elements:
				e.v = (e.v - crop.top) / span
			for band in systems:
				band.top = (band.top - crop.top) / span
				band.bottom = (band.bottom - crop.top) / span
		pages.append({"texture": crop.texture, "systems": systems})
		elements.append_array(page_elements)
	elements.sort_custom(func(a, b): return a.when < b.when)
	for i in elements.size():
		elements[i].index = i
	return {"ok": true, "pages": pages, "elements": elements, "page_count": pages.size()}


## Crop a page raster vertically to its drawn content (transparent SVG background -> get_used_rect finds
## the ink). Keeps full width (uniform page widths). Returns {texture, top, bottom} (top/bottom normalized).
static func _crop_to_content(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	if img == null:
		return {"texture": tex, "top": 0.0, "bottom": 1.0}
	var h := img.get_height()
	var used := img.get_used_rect()
	if used.size.y <= 0 or h <= 0:
		return {"texture": tex, "top": 0.0, "bottom": 1.0}
	var margin := int(h * 0.015)
	var y0 := maxi(0, used.position.y - margin)
	var y1 := mini(h, used.position.y + used.size.y + margin)
	if y1 - y0 >= h:
		return {"texture": tex, "top": 0.0, "bottom": 1.0}
	var cropped := img.get_region(Rect2i(0, y0, img.get_width(), y1 - y0))
	return {"texture": ImageTexture.create_from_image(cropped), "top": float(y0) / h, "bottom": float(y1) / h}


static func _page_svgs(svg_stem: String) -> Array:
	var dir := svg_stem.get_base_dir()
	var base := svg_stem.get_file()
	var da := DirAccess.open(dir)
	if da == null:
		return []
	var found: Array = []
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if fn.begins_with(base + "-") and fn.ends_with(".svg"):
			var num := fn.substr((base + "-").length())
			num = num.left(num.length() - 4)   # strip ".svg"
			if num.is_valid_int():
				found.append({"n": int(num), "path": dir.path_join(fn)})
		fn = da.get_next()
	da.list_dir_end()
	found.sort_custom(func(a, b): return a.n < b.n)
	var out: Array = []
	for f in found:
		out.append(f.path)
	return out


static func _build_systems(elements: Array) -> Array:
	var by_sys := {}                       # sys_id -> [min_v, max_v]
	for e in elements:
		var sid = e.get("sys_id", "")
		if by_sys.has(sid):
			by_sys[sid][0] = minf(by_sys[sid][0], e.v)
			by_sys[sid][1] = maxf(by_sys[sid][1], e.v)
		else:
			by_sys[sid] = [e.v, e.v]
	var ids: Array = by_sys.keys()
	ids.sort_custom(func(a, b): return by_sys[a][0] < by_sys[b][0])   # top to bottom
	var systems: Array = []
	var index := {}
	for i in ids.size():
		var mn: float = by_sys[ids[i]][0]
		var mx: float = by_sys[ids[i]][1]
		var pad: float = maxf(0.04, (mx - mn) * 0.15)
		systems.append({"top": clampf(mn - pad, 0.0, 1.0), "bottom": clampf(mx + pad, 0.0, 1.0)})
		index[ids[i]] = i
	for e in elements:
		e.sys = index.get(e.get("sys_id", ""), 0)
	return systems


# --- SVG: note id -> normalized position ---------------------------------

static func _parse_svg(svg_path: String) -> Dictionary:
	var p := XMLParser.new()
	if p.open(svg_path) != OK:
		return {}
	var viewbox := Rect2(0, 0, 1, 1)
	var tstack := [Vector2.ZERO]
	var note_stack: Array = []     # current note id per open container ("" if none)
	var sys_stack: Array = []      # current system id per open container ("" if none)
	var recorded := {}             # note id -> true (first notehead only)
	var out := {}

	while p.read() == OK:
		var nt := p.get_node_type()
		if nt == XMLParser.NODE_ELEMENT:
			var name := p.get_node_name()
			var empty := p.is_empty()
			if name == "svg":
				var vb := p.get_named_attribute_value_safe("viewBox")
				if vb != "":
					viewbox = _viewbox(vb)
				if not empty:
					tstack.append(tstack[-1])
					note_stack.append(note_stack[-1] if note_stack.size() > 0 else "")
					sys_stack.append(sys_stack[-1] if sys_stack.size() > 0 else "")
			elif name == "g":
				var t := _translate(p.get_named_attribute_value_safe("transform"))
				var acc: Vector2 = tstack[-1] + t
				var cls := p.get_named_attribute_value_safe("class")
				var note_id: String = note_stack[-1] if note_stack.size() > 0 else ""
				var sys_id: String = sys_stack[-1] if sys_stack.size() > 0 else ""
				if cls == "note":
					note_id = p.get_named_attribute_value_safe("id")
				elif cls == "system":
					sys_id = p.get_named_attribute_value_safe("id")
				if not empty:
					tstack.append(acc)
					note_stack.append(note_id)
					sys_stack.append(sys_id)
			elif name == "use":
				# the notehead glyph: its translate is the note's anchor
				var cur: String = note_stack[-1] if note_stack.size() > 0 else ""
				if cur != "" and not recorded.has(cur):
					var t := _translate(p.get_named_attribute_value_safe("transform"))
					var pos: Vector2 = tstack[-1] + t
					recorded[cur] = true
					out[cur] = {
						"u": (pos.x - viewbox.position.x) / viewbox.size.x,
						"v": (pos.y - viewbox.position.y) / viewbox.size.y,
						"sys": sys_stack[-1] if sys_stack.size() > 0 else "",
					}
		elif nt == XMLParser.NODE_ELEMENT_END:
			var name := p.get_node_name()
			if name == "g" or name == "svg":
				if tstack.size() > 1:
					tstack.pop_back()
				if note_stack.size() > 0:
					note_stack.pop_back()
				if sys_stack.size() > 0:
					sys_stack.pop_back()
	return out


static func _parse_timemap(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Array):
		return out
	for ev in data:
		if ev is Dictionary and ev.has("on"):
			var q: float = float(ev.get("qstamp", 0.0))
			for id in ev["on"]:
				out[String(id)] = q
	return out


static func _viewbox(s: String) -> Rect2:
	var parts := s.split(" ", false)
	if parts.size() < 4:
		return Rect2(0, 0, 1, 1)
	return Rect2(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


static func _translate(transform: String) -> Vector2:
	var i := transform.find("translate(")
	if i < 0:
		return Vector2.ZERO
	var inner := transform.substr(i + 10)
	var close := inner.find(")")
	if close >= 0:
		inner = inner.left(close)
	var nums := inner.replace(",", " ").split(" ", false)
	if nums.size() < 2:
		return Vector2.ZERO
	return Vector2(float(nums[0]), float(nums[1]))
