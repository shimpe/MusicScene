extends SceneTree
## Regression: LilyPond multi-page (paginate). finalize_paged must enumerate <stem>-N.cropped.svg in
## NUMERIC order, parse each page, stamp every element with its 1-based `page`, and return per-page
## systems. _page_cropped_svgs is tested purely (numeric vs lexical sort); finalize_paged is tested over
## two hand-written cropped-SVG fixtures (rasterised headless by ThorVG). Prints fail=0 on success.
const Lily := preload("res://addons/musicscene/notation/MSNotationLilyPositions.gd")

func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()

# One page: two noteheads (translate g's inside <a textedit>, each carrying data-when). A filled path
# gives ThorVG something to rasterise (a blank SVG would rasterise empty and fail).
func _page(w0: float, w1: float) -> String:
	return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"'
		+ ' width="100mm" height="40mm" viewBox="0 0 100 40">'
		+ '<a xlink:href="textedit:///tmp/x.ly:5:2:2"><g transform="translate(10, 20)" data-when="%f">'
		+ '<path d="M0 0 h4 v4 h-4 z" fill="black"/></g></a>'
		+ '<a xlink:href="textedit:///tmp/x.ly:5:8:8"><g transform="translate(60, 20)" data-when="%f">'
		+ '<path d="M0 0 h4 v4 h-4 z" fill="black"/></g></a></svg>') % [w0, w1]

func _init() -> void:
	var dir := ProjectSettings.globalize_path("user://")
	var fails := 0

	# --- A) _page_cropped_svgs enumerates in numeric (not lexical) order -----------------------------
	var estem := dir.path_join("lypg_enum")
	for n in [1, 2, 10]:
		_write("%s-%d.cropped.svg" % [estem, n], "<svg/>")
	var got: Array = Lily._page_cropped_svgs(estem)
	var order := got.map(func(p): return int(p.get_file().trim_prefix("lypg_enum-").trim_suffix(".cropped.svg")))
	if order != [1, 2, 10]:
		fails += 1; print("FAIL: page order ", order, " (expected [1,2,10] — numeric, not lexical)")

	# --- B) finalize_paged over two fixture pages ---------------------------------------------------
	var stem := dir.path_join("lypg_fin")
	_write(stem + "-1.cropped.svg", _page(0.0, 0.25))
	_write(stem + "-2.cropped.svg", _page(0.5, 0.75))
	var res := Lily.finalize_paged(stem, {})
	if not res.ok:
		fails += 1; print("FAIL: finalize_paged: ", res.get("error", "?"))
	else:
		if int(res.page_count) != 2:
			fails += 1; print("FAIL: page_count ", res.page_count, " (expected 2)")
		if res.pages.size() != 2:
			fails += 1; print("FAIL: pages ", res.pages.size(), " (expected 2)")
		for e in res.elements:
			if not e.has("page"):
				fails += 1; print("FAIL: element missing `page`: ", e); break
		# elements are when-sorted; page-1 elements (when < 0.5) precede page-2 elements
		var pages_seq: Array = res.elements.map(func(e): return int(e.page))
		if pages_seq != [1, 1, 2, 2]:
			fails += 1; print("FAIL: page sequence ", pages_seq, " (expected [1,1,2,2])")
		if res.pages.size() == 2 and (res.pages[0].systems.is_empty() or res.pages[1].systems.is_empty()):
			fails += 1; print("FAIL: a page has no systems")

	print("fail=", fails)
	quit()
