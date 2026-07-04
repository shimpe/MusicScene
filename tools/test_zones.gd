extends SceneTree
## Headless sensor/zone tests. Run:
##   <godot> --headless --path . --script res://tools/test_zones.gd
## Space-aware (run once per space). Mixes unit checks (preloaded classes) with
## integration checks (live MusicSceneOSC autoload).
const EB := preload("res://addons/musicscene/events/MSEventBinding.gd")
const CE := preload("res://addons/musicscene/physics/MSCollisionEvents.gd")
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
	osc.dispatcher.dispatch("/ms/scene/zoneA", ["new", "circle"])
	osc.dispatcher.dispatch("/ms/scene/zoneA/physics", ["enable", "area"])
	osc.dispatcher.dispatch("/ms/scene/zoneA/collider", ["circle", 0.3])
	osc.dispatcher.dispatch("/ms/scene/zoneA", ["pos", 0.0, 0.0, 0.0])
	osc.dispatcher.dispatch("/ms/scene/ball", ["new", "circle"])
	osc.dispatcher.dispatch("/ms/scene/ball/physics", ["enable", "rigid"])
	osc.dispatcher.dispatch("/ms/scene/ball/collider", ["circle", 0.05])
	osc.dispatcher.dispatch("/ms/scene/ball", ["pos", 0.1, 0.0, 0.0])

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("MusicSceneOSC")
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
	if _f == 9:
		var b = EB.new()
		b.max_rate = 20.0   # gap = 0.05s
		check(b.should_emit_other(1.0, 100.0, "n1", ""), "n1 first emit allowed")
		b.mark_other("n1", 100.0)
		check(not b.should_emit_other(1.0, 100.01, "n1", ""), "n1 throttled within gap")
		check(b.should_emit_other(1.0, 100.01, "n2", ""), "n2 has its own timer")
		check(b.should_emit_other(1.0, 100.10, "n1", ""), "n1 allowed after gap")
		b.mark_other("n1", 100.0); b.mark_other("n2", 100.0)
		b.prune_others({"n1": true})
		check(b._last_emit_other.has("n1") and not b._last_emit_other.has("n2"), "prune drops absent bodies")
		var bc = EB.new()
		bc.cooldown = 0.2
		bc.mark_other("n1", 100.0)
		check(not bc.should_emit_other(1.0, 100.1, "n1", ""), "n1 throttled by cooldown")
		check(bc.should_emit_other(1.0, 100.25, "n1", ""), "n1 passes after cooldown")
	if _f == 13:
		osc.dispatcher.dispatch("/ms/physics", ["enable", 1])
		osc.dispatcher.dispatch("/ms/scene/zoneA/on", ["areaStay", "/zone/presence", "maxRate", 20])
	if _f == 14:
		var zone = osc.registry.get_object("zoneA")
		check(osc.spatial.is_area(zone.node), "zone node is an area")
		check(osc.spatial.overlapping_others(zone.node).size() >= 1, "zone overlaps the ball")
	if _f == 20:
		var zone = osc.registry.get_object("zoneA")
		var b = zone.event_bindings.get("areaStay")
		check(b != null, "areaStay binding registered")
		check(b != null and b._last_emit_other.has("ball"), "areaStay emitted for contained body (per-body timer set)")
	if _f == 22:
		osc.dispatcher.dispatch("/ms/scene/ball", ["pos", 0.9, 0.0, 0.0])  # move ball out of the zone
	if _f == 28:
		var zone = osc.registry.get_object("zoneA")
		var b = zone.event_bindings.get("areaStay")
		check(b != null and not b._last_emit_other.has("ball"), "left body's per-body timer is pruned")
	if _f == 30:
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
