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
	var systems := _build_systems(parsed)   # stamps each element's `sys`; padded band per staff-system
	return {"ok": true, "texture": res.texture, "elements": parsed, "systems": systems}


## Group the when-sorted note elements into staff-systems (lines) and return a padded vertical band
## {top, bottom} per system, so the follow cursor stays within the current line instead of spanning the
## whole page when several systems share one image. LilyPond's SVG has no system groups (unlike
## Verovio's <g class="system">), so a new system is detected where the horizontal position `u` jumps
## back to the left — within a system u only advances rightward (elements are when-sorted). Stamps each
## element's `sys` (top system = 0). Band padding mirrors the Verovio path.
static func _build_systems(elements: Array) -> Array:
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
	var mn: Array = []
	var mx: Array = []
	mn.resize(n); mn.fill(1e20)
	mx.resize(n); mx.fill(-1e20)
	for e in elements:
		var s: int = int(e.sys)
		mn[s] = minf(mn[s], float(e.v))
		mx[s] = maxf(mx[s], float(e.v))
	var systems: Array = []
	for i in n:
		var pad: float = maxf(0.04, (mx[i] - mn[i]) * 0.15)
		systems.append({"top": clampf(mn[i] - pad, 0.0, 1.0), "bottom": clampf(mx[i] + pad, 0.0, 1.0)})
	return systems


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
