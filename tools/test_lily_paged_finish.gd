extends SceneTree
## Regression: _finish_lily_paged must not error blank when the paged render produced nothing. With
## neither <stem>-1.cropped.svg nor <stem>.cropped.svg present it reports a render failure (not a crash,
## not a silent success). Pure — no LilyPond/Python/render. Prints fail=0 on success.
const RenderQueue := preload("res://addons/musicscene/notation/MSRenderQueue.gd")

class StubObj:
	extends RefCounted
	var failed := ""
	var paged := false
	var single := false
	func _on_render_failed(msg: String) -> void: failed = msg
	func _on_pages_done(_p, _e, _n) -> void: paged = true
	func _on_elements_done(_t, _e, _s = []) -> void: single = true

# One cropped page: a filled notehead path inside an <a textedit> <g data-when> — enough for ThorVG to
# rasterise and for the parser to find one element (a blank SVG rasterises empty and would fail).
func _page() -> String:
	return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"'
		+ ' width="100mm" height="40mm" viewBox="0 0 100 40">'
		+ '<a xlink:href="textedit:///tmp/x.ly:5:2:2"><g transform="translate(10, 20)" data-when="0.0">'
		+ '<path d="M0 0 h4 v4 h-4 z" fill="black"/></g></a></svg>')

func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()

func _init() -> void:
	var q = RenderQueue.new()
	var obj := StubObj.new()
	var fails := 0

	# A stem that has no page files and no single cropped file -> must report failure.
	var stem := ProjectSettings.globalize_path("user://lypg_missing_stem")
	q._finish_lily_paged(obj, stem, {}, -1)
	if obj.failed == "":
		fails += 1; print("FAIL: expected a render failure for a stem with no pages")
	if obj.paged:
		fails += 1; print("FAIL: _on_pages_done fired despite no pages")

	# A stem with only <stem>.cropped.svg (paged wrapper fell back to a single image) -> must degrade to
	# the single-image finish (_on_elements_done), NOT report failure and NOT fire _on_pages_done.
	var obj2 := StubObj.new()
	var stem2 := ProjectSettings.globalize_path("user://lypg_single_stem")
	_write(stem2 + ".cropped.svg", _page())
	q._finish_lily_paged(obj2, stem2, {}, -1)
	if not obj2.single:
		fails += 1; print("FAIL: single fallback did not reach _on_elements_done")
	if obj2.failed != "":
		fails += 1; print("FAIL: single fallback reported a failure: ", obj2.failed)
	if obj2.paged:
		fails += 1; print("FAIL: _on_pages_done fired for a single-image fallback")

	print("failed_msg=", obj.failed)
	print("fail=", fails)
	q.free()
	quit()
