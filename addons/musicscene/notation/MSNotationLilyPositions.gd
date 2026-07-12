extends RefCounted
## LilyPond addressable notation. LilyPond has no position-export file like MuseScore's .mpos, but
## its SVG backend wraps every element in a point-and-click <a xlink:href="textedit://file:line:char">
## link, and we can inject a tiny Scheme engraver (top-level \layout) that tags each notehead with
## its musical moment (data-when). So from the cropped SVG we extract, per note: its time (whole
## notes), source location (line:char), and page position -> note-level addressing + time following.

const SvgBackend := preload("res://addons/musicscene/notation/MSNotationBackendSvg.gd")

## Prepended to the user's LilyPond source: defines the moment tagger and applies it to all voices.
const TAGGER := """\\version \"2.24.0\"
#(define (MusicScene-moment-tagger context)
  (make-engraver
    (acknowledgers
      ((note-head-interface engraver grob source-engraver)
       (let ((m (ly:context-current-moment context)))
         (ly:grob-set-property! grob 'output-attributes
           (list (cons 'data-when (number->string (exact->inexact (ly:moment-main m)))))))))))
\\layout { \\context { \\Voice \\consists #MusicScene-moment-tagger } }
"""


## Wrap a LilyPond source so noteheads carry timing. Removes the user's \version (we supply one).
static func wrap_source(ly_text: String) -> String:
	var lines := ly_text.split("\n")
	var kept: Array = []
	for line in lines:
		if line.strip_edges().begins_with("\\version"):
			continue
		kept.append(line)
	return TAGGER + "\n" + "\n".join(kept)


## After LilyPond produced the cropped SVG: rasterize it (for display) and parse note elements.
## Returns {ok, texture, elements:[{index, when, line, char, u, v, sys}], systems:[{top, bottom}], error}.
static func finalize(svg_path: String, options: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(svg_path):
		return {"ok": false, "error": "lily addressable: no SVG at " + svg_path}
	var res = SvgBackend.render({"kind": "path", "path": svg_path, "text": "", "bytes": PackedByteArray()}, 1, options)
	if not res.ok:
		return {"ok": false, "error": "lily addressable: " + res.error}
	var parsed := _parse(svg_path)
	var systems := _build_systems(parsed, _staff_lines(svg_path))   # stamps `sys`; band = staff height
	return {"ok": true, "texture": res.texture, "elements": parsed, "systems": systems}


## Multi-page (paginated) variant. lily_render.py --paged already produced one cropped SVG per page
## (<stem>-1.cropped.svg, <stem>-2.cropped.svg, ...); enumerate them in numeric order, rasterize + parse
## each, group into per-page staff-systems, and tag every element with its 1-based `page`. Returns
## {ok, pages:[{texture, systems}], elements:[{index, when, line, char, u, v, sys, page}], page_count}.
## Mirrors MSNotationVerovioPositions.finalize_paged, but LilyPond carries its own data-when/textedit so
## there is no timemap, and pages are pre-cropped so no raster re-crop/rescale is needed.
static func finalize_paged(stem: String, options: Dictionary = {}) -> Dictionary:
	var page_paths := _page_cropped_svgs(stem)
	if page_paths.is_empty():
		return {"ok": false, "error": "lily addressable: no page SVGs at " + stem + "-N.cropped.svg"}
	var pages: Array = []
	var elements: Array = []
	for pi in page_paths.size():
		var svg_path: String = page_paths[pi]
		var res = SvgBackend.render({"kind": "path", "path": svg_path, "text": "", "bytes": PackedByteArray()}, 1, options)
		if not res.ok:
			return {"ok": false, "error": "lily addressable: " + res.error}
		var page_elements := _parse(svg_path)
		var systems := _build_systems(page_elements, _staff_lines(svg_path))   # band = staff height
		for e in page_elements:
			e["page"] = pi + 1
		pages.append({"texture": res.texture, "systems": systems})
		elements.append_array(page_elements)
	elements.sort_custom(func(a, b): return a.when < b.when)
	for i in elements.size():
		elements[i].index = i
	return {"ok": true, "pages": pages, "elements": elements, "page_count": pages.size()}


## Enumerate <stem>-1.cropped.svg, <stem>-2.cropped.svg, ... in NUMERIC order (a lexical sort would put
## -10 before -2). Returns absolute/user:// paths, or [] if none exist.
static func _page_cropped_svgs(stem: String) -> Array:
	var dir := stem.get_base_dir()
	var base := stem.get_file()
	var da := DirAccess.open(dir)
	if da == null:
		return []
	var found: Array = []
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if fn.begins_with(base + "-") and fn.ends_with(".cropped.svg"):
			var num := fn.substr((base + "-").length())
			num = num.left(num.length() - ".cropped.svg".length())
			if num.is_valid_int():
				found.append({"n": int(num), "path": dir.path_join(fn)})
		fn = da.get_next()
	da.list_dir_end()
	found.sort_custom(func(a, b): return a.n < b.n)
	var out: Array = []
	for f in found:
		out.append(f.path)
	return out


## Group the when-sorted note elements into staff-systems (lines) and return a vertical band
## {top, bottom} per system, so the follow cursor stays within the current line instead of spanning the
## whole page when several systems share one image. LilyPond's SVG has no system groups (unlike
## Verovio's <g class="system">), so a new system is detected where the horizontal position `u` jumps
## back to the left — within a system u only advances rightward (elements are when-sorted). Stamps each
## element's `sys` (top system = 0).
##
## The band is sized to the STAFF geometry (staff_lines, from _staff_lines) — the top staff line to the
## bottom staff line of that system, i.e. the full staff / grand-staff height — NOT the note extent. Sizing
## from notes alone makes the cursor track wherever notes happen to sit (a lone ledger note stretches it, a
## clustered measure shrinks it). Each staff line is assigned to the nearest system (by note-center v). When
## no staff lines are supplied (e.g. synthetic tests), fall back to the padded note extent.
static func _build_systems(elements: Array, staff_lines: Array = []) -> Array:
	if elements.is_empty():
		return []
	var sys := 0
	var run_max_u: float = float(elements[0].u)
	for e in elements:
		if float(e.u) < run_max_u - 0.30:
			sys += 1
			run_max_u = float(e.u)
		else:
			run_max_u = maxf(run_max_u, float(e.u))
		e["sys"] = sys
	var n := sys + 1
	var mn: Array = []        # note v extent per system (fallback + assignment center)
	var mx: Array = []
	var umn: Array = []       # note u extent per system (x-overlap gate for line assignment)
	var umx: Array = []
	mn.resize(n); mn.fill(1e20)
	mx.resize(n); mx.fill(-1e20)
	umn.resize(n); umn.fill(1e20)
	umx.resize(n); umx.fill(-1e20)
	for e in elements:
		var s: int = int(e.sys)
		mn[s] = minf(mn[s], float(e.v)); mx[s] = maxf(mx[s], float(e.v))
		umn[s] = minf(umn[s], float(e.u)); umx[s] = maxf(umx[s], float(e.u))
	# Assign each staff line to the system whose note-centre it is vertically nearest (among systems whose
	# horizontal span it overlaps — staff lines run the full system width, so this mainly separates the
	# vertically-stacked systems on a page). line_lo/hi accumulate each system's staff-line extent.
	var line_lo: Array = []
	var line_hi: Array = []
	line_lo.resize(n); line_lo.fill(1e20)
	line_hi.resize(n); line_hi.fill(-1e20)
	for L in staff_lines:
		var best := -1
		var bestd := 1e20
		for i in n:
			if float(L.x1) < umn[i] or float(L.x0) > umx[i]:
				continue
			var d: float = absf(float(L.y) - (mn[i] + mx[i]) * 0.5)
			if d < bestd:
				bestd = d; best = i
		if best >= 0:
			line_lo[best] = minf(line_lo[best], float(L.y))
			line_hi[best] = maxf(line_hi[best], float(L.y))
	var systems: Array = []
	for i in n:
		var top: float
		var bot: float
		if line_hi[i] >= line_lo[i]:
			var pad: float = maxf(0.01, (line_hi[i] - line_lo[i]) * 0.06)   # bracket just past the outer lines
			top = line_lo[i] - pad; bot = line_hi[i] + pad
		else:
			var npad: float = maxf(0.04, (mx[i] - mn[i]) * 0.15)            # no staff lines: note extent
			top = mn[i] - npad; bot = mx[i] + npad
		systems.append({"top": clampf(top, 0.0, 1.0), "bottom": clampf(bot, 0.0, 1.0)})
	return systems


## Horizontal staff rules (the 5-line staff) LilyPond draws as long <line> elements — used by
## _build_systems to size the cursor band to the true staff / grand-staff height. Walks the same
## translate stack as _parse. Keeps only horizontal (y1≈y2) lines that span a large fraction of the page
## width, which excludes vertical bar lines and short ledger lines. Returns [{y, x0, x1}] page-normalized.
static func _staff_lines(svg_path: String) -> Array:
	var p := XMLParser.new()
	if p.open(svg_path) != OK:
		return []
	var viewbox := Rect2(0, 0, 1, 1)
	var tstack := [Vector2.ZERO]
	var out: Array = []
	while p.read() == OK:
		var nt := p.get_node_type()
		if nt == XMLParser.NODE_ELEMENT:
			var name := p.get_node_name()
			var empty := p.is_empty()
			if name == "svg":
				viewbox = _viewbox(p.get_named_attribute_value_safe("viewBox"))
			elif name == "g":
				if not empty:
					tstack.append(tstack[-1] + _translate(p.get_named_attribute_value_safe("transform")))
			elif name == "line":
				var acc: Vector2 = tstack[-1] + _translate(p.get_named_attribute_value_safe("transform"))
				var x1 := float(p.get_named_attribute_value_safe("x1"))
				var x2 := float(p.get_named_attribute_value_safe("x2"))
				var y1 := float(p.get_named_attribute_value_safe("y1"))
				var y2 := float(p.get_named_attribute_value_safe("y2"))
				if absf(y1 - y2) < 0.01 and absf(x2 - x1) > 0.2 * viewbox.size.x and viewbox.size.x > 0.0:
					out.append({
						"y": (acc.y + y1 - viewbox.position.y) / viewbox.size.y,
						"x0": (acc.x + minf(x1, x2) - viewbox.position.x) / viewbox.size.x,
						"x1": (acc.x + maxf(x1, x2) - viewbox.position.x) / viewbox.size.x,
					})
		elif nt == XMLParser.NODE_ELEMENT_END:
			if p.get_node_name() == "g" and tstack.size() > 1:
				tstack.pop_back()
	return out


# --- SVG parsing ---------------------------------------------------------

static func _parse(svg_path: String) -> Array:
	var p := XMLParser.new()
	if p.open(svg_path) != OK:
		return []
	var viewbox := Rect2(0, 0, 1, 1)
	var tstack := [Vector2.ZERO]      # accumulated translate
	var when_stack := [NAN]           # inherited data-when
	var href := ""
	var seen := {}                    # href -> true (dedup: one hotspot per note)
	var out: Array = []
	var idx := 0

	while p.read() == OK:
		var nt := p.get_node_type()
		if nt == XMLParser.NODE_ELEMENT:
			var name := p.get_node_name()
			var empty := p.is_empty()
			if name == "svg":
				viewbox = _viewbox(p.get_named_attribute_value_safe("viewBox"))
			elif name == "a":
				var raw := p.get_named_attribute_value_safe("xlink:href")
				if raw == "":
					raw = p.get_named_attribute_value_safe("href")
				href = raw
			elif name == "g":
				var t := _translate(p.get_named_attribute_value_safe("transform"))
				var acc: Vector2 = tstack[-1] + t
				var dw := p.get_named_attribute_value_safe("data-when")
				var wv: float = float(dw) if dw != "" else when_stack[-1]
				# A positioned element inside an a-link with a known moment = a notehead anchor.
				if t != Vector2.ZERO and href != "" and not is_nan(wv) and not seen.has(href):
					seen[href] = true
					var lc := _line_char(href)
					out.append({
						"index": idx,
						"when": wv,
						"line": lc.x, "char": lc.y,
						"u": (acc.x - viewbox.position.x) / viewbox.size.x,
						"v": (acc.y - viewbox.position.y) / viewbox.size.y,
					})
					idx += 1
				if not empty:
					tstack.append(acc)
					when_stack.append(wv)
		elif nt == XMLParser.NODE_ELEMENT_END:
			var name := p.get_node_name()
			if name == "g":
				if tstack.size() > 1:
					tstack.pop_back()
				if when_stack.size() > 1:
					when_stack.pop_back()
			elif name == "a":
				href = ""

	out.sort_custom(func(a, b): return a.when < b.when)
	# reindex after sort so n0..nK follow musical order
	for i in out.size():
		out[i].index = i
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


## Extract (line, char) from "textedit://<path-with-colons>:line:char:col".
static func _line_char(href: String) -> Vector2i:
	var toks := href.split(":")
	if toks.size() < 3:
		return Vector2i(-1, -1)
	# last three are line:char:col
	var n := toks.size()
	return Vector2i(int(toks[n - 3]), int(toks[n - 2]))
