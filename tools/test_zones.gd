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

func _make_zone_and_body(osc) -> void:
	osc.dispatcher.dispatch("/gscore/scene/zoneA", ["new", "circle"])
	osc.dispatcher.dispatch("/gscore/scene/zoneA/physics", ["enable", "area"])
	osc.dispatcher.dispatch("/gscore/scene/zoneA/collider", ["circle", 0.3])
	osc.dispatcher.dispatch("/gscore/scene/zoneA", ["pos", 0.0, 0.0, 0.0])
	osc.dispatcher.dispatch("/gscore/scene/ball", ["new", "circle"])
	osc.dispatcher.dispatch("/gscore/scene/ball/physics", ["enable", "rigid"])
	osc.dispatcher.dispatch("/gscore/scene/ball/collider", ["circle", 0.05])
	osc.dispatcher.dispatch("/gscore/scene/ball", ["pos", 0.1, 0.0, 0.0])

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
	if _f == 4:
		_make_zone_and_body(osc)
	if _f == 6:
		var zone = osc.registry.get_object("zoneA")
		var body = osc.registry.get_object("ball")
		var bnode = body.physics_adapter.body
		var data = CE._build_data(osc, zone, "areaStay", bnode)
		check(data.has("otherx") and data.has("otherspeed"), "data has other-centric fields")
		check(str(data["other"]) == "ball", "data.other resolves to 'ball'")
		check(absf(float(data["otherx"]) - 0.1) < 0.05, "data.otherx ~= ball normalized x (0.1)")
	if _f == 8:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
