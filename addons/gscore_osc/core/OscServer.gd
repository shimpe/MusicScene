extends Node
## UDP OSC server: receives datagrams, decodes them with OscPacket, and emits one
## `message_received` per OSC message. Also sends replies/events back out.
##
## Replies and events are sent to the most recent sender's IP on each configured `send_port`
## (so a client that pings us gets the pong on its own listening port). If no datagram has
## been received yet, `send_host` is used as a fallback. The socket is bound for both receive
## and send, so clients see replies coming from this server's listen port.

const OscPacket := preload("res://addons/gscore_osc/core/OscPacket.gd")

signal message_received(address: String, args: Array, sender_ip: String, sender_port: int)

var verbose: bool = true

var _udp := PacketPeerUDP.new()
var _running: bool = false
var _listen_port: int = 7400
var _send_host: String = "127.0.0.1"
var _send_ports: PackedInt32Array = PackedInt32Array([7401])
var _last_sender_ip: String = ""
var _last_sender_port: int = 0


func _ready() -> void:
	set_process(true)


func start(listen_port: int, send_host: String, send_ports: PackedInt32Array) -> bool:
	stop()
	_listen_port = listen_port
	_send_host = send_host
	_send_ports = _normalize_ports(send_ports)
	var err := _udp.bind(_listen_port, "*")
	if err != OK:
		push_error("[GScoreOSC] Failed to bind UDP port %d (error %d)" % [_listen_port, err])
		_running = false
		return false
	_running = true
	if verbose:
		print("[GScoreOSC] OSC server listening on udp:%d, replies -> %s:%s"
			% [_listen_port, _send_host, str(Array(_send_ports))])
	return true


func stop() -> void:
	if _udp.is_bound():
		_udp.close()
	_running = false


func is_running() -> bool:
	return _running


func set_output(host: String, send_ports: PackedInt32Array) -> void:
	_send_host = host
	_send_ports = _normalize_ports(send_ports)
	if verbose:
		print("[GScoreOSC] OSC output set to %s:%s" % [host, str(Array(_send_ports))])


func get_send_ports() -> PackedInt32Array:
	return _send_ports


## Parse a "7401, 7402 7403"-style setting string into valid ports (may contain duplicates).
static func parse_ports(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var norm := text.replace(",", " ").replace("\t", " ").replace("\n", " ")
	for tok in norm.split(" ", false):
		var t := tok.strip_edges()
		if t.is_valid_int():
			var p := t.to_int()
			if p >= 1 and p <= 65535:
				out.append(p)
	return out


## De-duplicate (order-preserving), drop out-of-range ports, and never return empty.
static func _normalize_ports(raw) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in raw:
		var p := int(v)
		if p >= 1 and p <= 65535 and not (p in out):
			out.append(p)
	if out.is_empty():
		out.append(7401)
	return out


## Resolve the startup port list: the `send_ports` string if it yields any, else [send_port].
static func startup_ports(send_ports_str: String, send_port: int) -> PackedInt32Array:
	if send_ports_str.strip_edges() != "":
		var parsed := parse_ports(send_ports_str)
		if not parsed.is_empty():
			return parsed
	return PackedInt32Array([send_port])


func get_listen_port() -> int:
	return _listen_port


func _process(_delta: float) -> void:
	if not _running:
		return
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		_last_sender_ip = _udp.get_packet_ip()
		_last_sender_port = _udp.get_packet_port()
		var messages := OscPacket.decode(pkt)
		for m in messages:
			if m is Dictionary:
				message_received.emit(
					String(m.get("address", "")),
					m.get("args", []),
					_last_sender_ip,
					_last_sender_port)


## Send a single OSC message to the active reply target.
func send(address: String, args: Array = []) -> void:
	_send_bytes(OscPacket.encode_message(address, args))


## Send an OSC bundle (elements: PackedByteArray or {address,args} dicts).
func send_bundle(elements: Array, timetag: int = 1) -> void:
	_send_bytes(OscPacket.encode_bundle(elements, timetag))


## Send an OSC message to an explicit host:port (used for event targets if ever overridden).
func send_to(host: String, port: int, address: String, args: Array = []) -> void:
	var bytes := OscPacket.encode_message(address, args)
	if _udp.set_dest_address(host, port) == OK:
		_udp.put_packet(bytes)


func _send_bytes(bytes: PackedByteArray) -> void:
	if not _running:
		return
	var host := _last_sender_ip if _last_sender_ip != "" else _send_host
	if host == "":
		host = "127.0.0.1"
	for port in _send_ports:
		if _udp.set_dest_address(host, port) == OK:
			_udp.put_packet(bytes)
