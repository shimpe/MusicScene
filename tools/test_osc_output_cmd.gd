extends SceneTree
## Headless test for the runtime output command + /gscore/info output ports (uses the autoload).
##   <godot> --headless --path . --script res://tools/test_osc_output_cmd.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 2:
		var d = osc.dispatcher
		d.dispatch("/gscore/app/output", ["127.0.0.1", 7401, 7402, 7403])
		check(Array(osc.server.get_send_ports()) == [7401, 7402, 7403], "output sets three ports")
		d.dispatch("/gscore/app/output", ["127.0.0.1", 7411])
		check(Array(osc.server.get_send_ports()) == [7411], "output with one port")
		d.dispatch("/gscore/app/output", ["127.0.0.1"])   # no ports
		check(Array(osc.server.get_send_ports()) == [7411], "output with no port leaves the list unchanged")
		d.dispatch("/gscore/app/output", ["127.0.0.1", 99999])   # only out-of-range ports
		check(Array(osc.server.get_send_ports()) == [7411], "output with only invalid ports leaves the list unchanged")
		var payload = osc.dispatcher._info_payload()
		check(payload.has("output") and payload.has(7411), "/gscore/info payload includes the output ports")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
