extends SceneTree
## Incremental notation updates must not flicker: on a re-render the previous page stays fully visible
## (no "engraving" tint) until the new page is ready. The tint only appears for the very first render,
## when there is nothing to show yet. (3D path; the 2D sprite already keeps its last texture.)
##   <godot> --headless --path . --script res://tools/test_notation_incremental.gd
const Cache := preload("res://addons/musicscene/notation/MSNotationCache.gd")
const TINT := Color(0.85, 0.85, 0.6, 1.0)
var _f := 0
var _pass := 0
var _fail := 0
var _phase := 0
var _done_at := 0

func check(c: bool, m: String) -> void:
	if c: _pass += 1; print("PASS: ", m)
	else: _fail += 1; print("FAIL: ", m)

func _approx(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) < 0.03 and abs(a.g - b.g) < 0.03 and abs(a.b - b.b) < 0.03

func _abc(notes: String) -> String:
	return "X: 1\nT: t\nM: 4/4\nL: 1/4\nK: C\n" + notes + "|"

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 1:
		Cache.clear()                                    # force async first render (not a cache hit)
		return false
	if _f == 2:
		osc.dispatcher.dispatch("/ms/scene/fx", ["new", "notation"])
		osc.dispatcher.dispatch("/ms/scene/fx", ["notationData", "abc", _abc("C ")])
		var n = osc.registry.get_object("fx").notation
		check("page_mat" in n, "3D notation object (has page_mat)")
		check(n._page_texture == null, "nothing rendered yet before the first engrave finishes")
		check(_approx(n.page_mat.albedo_color, TINT), "first render shows the engraving tint")
		_phase = 1
		return false
	if _phase == 1:
		var n = osc.registry.get_object("fx").notation
		if n._page_texture != null:                      # first render finished
			_phase = 2
			check(_approx(n.page_mat.albedo_color, Color.WHITE), "first page shown with no tint (white)")
			var prev = n.page_mat.albedo_texture
			osc.dispatcher.dispatch("/ms/scene/fx", ["notationData", "abc", _abc("C C ")])  # incremental
			check(not _approx(n.page_mat.albedo_color, TINT),
				"incremental re-render keeps last output — no engraving tint (got %s)" % n.page_mat.albedo_color)
			check(n.page_mat.albedo_texture == prev, "previous page still displayed while the update engraves")
			_done_at = _f
	if _phase == 2 and _f > _done_at + 2:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	if _f > 1500:
		check(false, "render did not complete in time")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
