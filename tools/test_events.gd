extends SceneTree
## Headless event-system tests. Run:
##   <godot> --headless --path . --script res://tools/test_events.gd
## Space-aware (run once per space). Mixes unit (preloaded) + integration (live autoload) checks.
const EB := preload("res://addons/gscore_osc/events/GScoreEventBinding.gd")
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", msg)
	else:
		_fail += 1
		print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 2:
		var b = EB.new()
		b.layer_filter = "perc"
		check(b.should_emit(1.0, 0.0, "x", "perc,bass"), "layer filter matches a member")
		check(not b.should_emit(1.0, 0.0, "x", "bass,drums"), "layer filter rejects a non-member")
		b.layer_filter = ""
		check(b.should_emit(1.0, 0.0, "x", "anything"), "empty layer filter always passes")
	if _f == 3:
		osc.dispatcher.dispatch("/gscore/physics/layer", [3, "perc"])
		osc.dispatcher.dispatch("/gscore/scene/obj", ["new", "circle"])
		osc.dispatcher.dispatch("/gscore/scene/obj/physics", ["enable", "rigid"])
		osc.dispatcher.dispatch("/gscore/scene/obj/physics", ["layer", "perc"])
	if _f == 5:
		var o = osc.registry.get_object("obj")
		var names = osc.spatial.layer_names_for(o.physics_adapter.body)
		check("perc" in names, "layer_names_for resolves a named layer")
	if _f == 8:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
