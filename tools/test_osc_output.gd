extends SceneTree
## Headless test for OscServer's multi-port output: the pure parse/normalize helpers
## plus a real loopback check that one send() reaches TWO bound receiver sockets.
##   <godot> --headless --path . --script res://tools/test_osc_output.gd
const OscServer := preload("res://addons/musicscene/core/OscServer.gd")

var _f := 0
var _pass := 0
var _fail := 0
var _srv
var _rx_a: PacketPeerUDP
var _rx_b: PacketPeerUDP

const LISTEN := 7490
const PA := 7491
const PB := 7492

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _unit_tests() -> void:
	check(Array(OscServer.parse_ports("7401, 7402 7403")) == [7401, 7402, 7403], "parse csv + spaces")
	check(Array(OscServer.parse_ports("7401\t7402\n 7403 ")) == [7401, 7402, 7403], "parse tabs/newlines + edge whitespace")
	check(Array(OscServer.parse_ports("7401 abc 0 70000 7402")) == [7401, 7402], "parse drops invalid/out-of-range")
	check(Array(OscServer.parse_ports("")) == [], "parse empty -> []")
	check(Array(OscServer._normalize_ports([7401, 7401, 7402])) == [7401, 7402], "normalize de-dupes")
	check(Array(OscServer._normalize_ports([])) == [7401], "normalize empty -> [7401]")
	check(Array(OscServer.startup_ports("", 7401)) == [7401], "startup empty setting -> [send_port]")
	check(Array(OscServer.startup_ports("7402, 7403", 7401)) == [7402, 7403], "startup parses setting")
	check(Array(OscServer.startup_ports("garbage", 7401)) == [7401], "startup garbage setting -> [send_port]")

func _setup_loopback() -> void:
	_srv = OscServer.new()
	_srv.verbose = false
	var ok = _srv.start(LISTEN, "127.0.0.1", PackedInt32Array([PA]))
	check(ok, "server binds listen port")
	_srv.set_output("127.0.0.1", PackedInt32Array([PA, PA, 0, PB]))   # dupes/invalid get normalized away
	check(Array(_srv.get_send_ports()) == [PA, PB], "set_output normalizes to [PA, PB]")
	_rx_a = PacketPeerUDP.new(); _rx_a.bind(PA, "*")
	_rx_b = PacketPeerUDP.new(); _rx_b.bind(PB, "*")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		_unit_tests()
		_setup_loopback()
		return false
	# From here on, resend each frame (loopback is reliable, but this avoids a first-frame race)
	# and check both receivers eventually see the fanned-out message.
	_srv.send("/x", [1])
	var got_a := _rx_a.get_available_packet_count() > 0
	var got_b := _rx_b.get_available_packet_count() > 0
	if got_a and got_b:
		check(true, "one send() reached BOTH ports (fan-out)")
		return _finish()
	if _f >= 120:
		check(got_a, "port A received")
		check(got_b, "port B received")
		return _finish()
	return false

func _finish() -> bool:
	# Free the manually-created server + receiver sockets so the run exits clean (no leaked-instance notices).
	_srv.stop(); _srv.free()
	_rx_a.close(); _rx_b.close()
	print("DONE pass=%d fail=%d" % [_pass, _fail])
	return true
