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

	var positions := _parse_svg(svg_path)          # id -> {u, v}
	var times := _parse_timemap(timemap_path)        # id -> qstamp (quarters)

	var elements: Array = []
	for id in positions.keys():
		if not times.has(id):
			continue
		var p: Vector2 = positions[id]
		elements.append({
			"id": id,
			"when": times[id] / 4.0,   # quarters -> whole notes (matches transport.beat/4)
			"line": -1, "char": -1,
			"u": p.x, "v": p.y,
		})
	elements.sort_custom(func(a, b): return a.when < b.when)
	for i in elements.size():
		elements[i].index = i
	return {"ok": true, "texture": res.texture, "elements": elements}


# --- SVG: note id -> normalized position ---------------------------------

static func _parse_svg(svg_path: String) -> Dictionary:
	var p := XMLParser.new()
	if p.open(svg_path) != OK:
		return {}
	var viewbox := Rect2(0, 0, 1, 1)
	var tstack := [Vector2.ZERO]
	var note_stack: Array = []     # current note id per open container ("" if none)
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
			elif name == "g":
				var t := _translate(p.get_named_attribute_value_safe("transform"))
				var acc: Vector2 = tstack[-1] + t
				var cls := p.get_named_attribute_value_safe("class")
				var note_id: String = note_stack[-1] if note_stack.size() > 0 else ""
				if cls == "note":
					note_id = p.get_named_attribute_value_safe("id")
				if not empty:
					tstack.append(acc)
					note_stack.append(note_id)
			elif name == "use":
				# the notehead glyph: its translate is the note's anchor
				var cur: String = note_stack[-1] if note_stack.size() > 0 else ""
				if cur != "" and not recorded.has(cur):
					var t := _translate(p.get_named_attribute_value_safe("transform"))
					var pos: Vector2 = tstack[-1] + t
					recorded[cur] = true
					out[cur] = Vector2(
						(pos.x - viewbox.position.x) / viewbox.size.x,
						(pos.y - viewbox.position.y) / viewbox.size.y)
		elif nt == XMLParser.NODE_ELEMENT_END:
			var name := p.get_node_name()
			if name == "g" or name == "svg":
				if tstack.size() > 1:
					tstack.pop_back()
				if note_stack.size() > 0:
					note_stack.pop_back()
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
