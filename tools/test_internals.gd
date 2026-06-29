extends SceneTree
## Headless self-tests for the OSC codec and the SVG notation backend.
## Run: godot --headless --script res://tools/test_internals.gd

func _init() -> void:
	_test_codec()
	_test_svg()
	quit()


func _test_codec() -> void:
	var P = load("res://addons/gscore_osc/core/OscPacket.gd")
	var bytes = P.encode_message("/gscore/scene/x", [42, 2.5, "hi", true, false])
	var dec = P.decode(bytes)
	print("[codec] message -> ", dec)
	assert(dec.size() == 1)
	assert(dec[0]["address"] == "/gscore/scene/x")
	var a = dec[0]["args"]
	assert(a[0] == 42 and abs(a[1] - 2.5) < 0.001 and a[2] == "hi" and a[3] == true and a[4] == false)

	var bundle = P.encode_bundle([
		{"address": "/a", "args": [1]},
		{"address": "/b", "args": ["x", 3.0]},
	], 1)
	var decb = P.decode(bundle)
	print("[codec] bundle  -> ", decb)
	assert(decb.size() == 2)
	assert(decb[0]["address"] == "/a" and decb[0]["args"][0] == 1)
	assert(decb[1]["address"] == "/b" and decb[1]["args"][0] == "x")
	print("[codec] PASS")


func _test_svg() -> void:
	var R = load("res://addons/gscore_osc/notation/GScoreNotationRenderer.gd")
	var res = R.render("res://icon.svg", "svg", 1, {})
	print("[svg] ok=%s backend=%s err=%s tex=%s" % [res.ok, res.backend, res.error, res.texture])
	if res.ok:
		print("[svg] PASS (rasterized %s)" % [res.texture.get_size()])
	else:
		print("[svg] backend reported: ", res.error)
