extends SceneTree
## Headless sensor/zone tests. Run:
##   <godot> --headless --path . --script res://tools/test_zones.gd
## Space-aware (run once per space). Mixes unit checks (preloaded classes) with
## integration checks (live GScoreOSC autoload).
const EB := preload("res://addons/gscore_osc/events/GScoreEventBinding.gd")
const CE := preload("res://addons/gscore_osc/physics/GScoreCollisionEvents.gd")
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
		b.payload = ["self", "other", "=A"]
		var out = b.build_args({"self": "zoneA", "other": "note17"})
		check(out == ["zoneA", "note17", "A"], "literal =A in payload -> 'A'")
		var b2 = EB.new()
		b2.payload = ["self", "'B", "missingfield"]
		var out2 = b2.build_args({"self": "z"})
		check(out2 == ["z", "B", 0], "literal 'B passes through; unknown field -> 0")
	if _f == 5:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
