extends RefCounted
## Forwards a Godot signal on a wrapped node to an OSC address. Because signal arity varies, we
## connect the correctly-sized handler (probed from the node's signal list) and forward the args.
##
## Default payload: <osc_id> <signal_name> <signal_args...>. Optional payload spec tokens:
##   self | signal | args | value | arg0..argN

var obj = null
var ctx = null
var signal_name: String = ""
var target: String = ""
var payload_spec: Array = []

var _connected: bool = false
var _handler: Callable


func connect_signal() -> bool:
	var node: Node = obj.node
	if not node.has_signal(signal_name):
		ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/signal",
			"No such signal: " + signal_name)
		return false
	var argc := _signal_arg_count(node, signal_name)
	match argc:
		0: _handler = _on0
		1: _handler = _on1
		2: _handler = _on2
		3: _handler = _on3
		_: _handler = _on4  # 4+ args: extras are dropped
	node.connect(signal_name, _handler)
	_connected = true
	return true


func disconnect_signal() -> void:
	if _connected and is_instance_valid(obj.node) and obj.node.is_connected(signal_name, _handler):
		obj.node.disconnect(signal_name, _handler)
	_connected = false


func _signal_arg_count(node: Node, sname: String) -> int:
	for s in node.get_signal_list():
		if s.name == sname:
			return (s.args as Array).size()
	return 0


func _on0() -> void: _emit([])
func _on1(a) -> void: _emit([a])
func _on2(a, b) -> void: _emit([a, b])
func _on3(a, b, c) -> void: _emit([a, b, c])
func _on4(a, b, c, d) -> void: _emit([a, b, c, d])


func _emit(sig_args: Array) -> void:
	var out: Array
	if payload_spec.is_empty():
		out = [obj.osc_id, signal_name]
		out.append_array(_sanitize(sig_args))
	else:
		out = []
		for tok in payload_spec:
			if String(tok) == "args":
				out.append_array(_sanitize(sig_args))
			else:
				out.append(_token(String(tok), sig_args))
	ctx.send_event(target, out)


func _token(tok: String, sig_args: Array):
	match tok:
		"self": return obj.osc_id
		"signal": return signal_name
		"value": return _san(sig_args[0]) if sig_args.size() > 0 else 0
		_:
			if tok.begins_with("arg"):
				var idx := tok.substr(3).to_int()
				return _san(sig_args[idx]) if idx < sig_args.size() else 0
			return tok


func _sanitize(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(_san(v))
	return out


func _san(v):
	match typeof(v):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return v
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return v.x  # collapse; clients can request specific args if needed
		_:
			return str(v)
