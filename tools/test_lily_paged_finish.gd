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

	print("failed_msg=", obj.failed)
	print("fail=", fails)
	q.free()
	quit()
