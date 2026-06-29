extends Node
## Events manager. Routes /on /off /payload /signal, owns Godot signal->OSC bindings, and
## handles mouse/touch interaction. Picking is delegated to ctx.spatial (2D hit-test or 3D camera
## ray), so this manager is dimension-agnostic. Physics/area events are stored as
## GScoreEventBinding on the object (wired by the physics adapter); input events are stored as
## lightweight dicts.

const EventBinding := preload("res://addons/gscore_osc/events/GScoreEventBinding.gd")
const SignalBinding := preload("res://addons/gscore_osc/events/GScoreSignalBinding.gd")

const INPUT_EVENTS := ["click", "down", "up", "drag", "enter", "leave"]

var ctx = null
var _hover: Dictionary = {}      # osc_id -> bool
var _pressed: Array = []          # hit descriptors captured on mouse-down


func setup(p_ctx) -> void:
	ctx = p_ctx


# --- Registration --------------------------------------------------------

func handle_on(obj, args: Array) -> void:
	var event := str(args[0]) if args.size() > 0 else ""
	var target := str(args[1]) if args.size() > 1 else ""
	if event == "" or target == "":
		ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/on", "Need <event> <target>")
		return
	if event in INPUT_EVENTS:
		obj.input_bindings[event] = {"address": target, "payload": []}
	else:
		var b = obj.event_bindings.get(event)
		if b == null:
			b = EventBinding.new()
			b.event = event
			obj.event_bindings[event] = b
		b.target = target
		_parse_options(b, args.slice(2))


func handle_off(obj, args: Array) -> void:
	var event := str(args[0]) if args.size() > 0 else ""
	if event in INPUT_EVENTS:
		obj.input_bindings.erase(event)
	else:
		obj.event_bindings.erase(event)


func handle_payload(obj, args: Array) -> void:
	var event := str(args[0]) if args.size() > 0 else ""
	var fields := args.slice(1)
	if event in INPUT_EVENTS:
		if obj.input_bindings.has(event):
			obj.input_bindings[event]["payload"] = fields
	elif obj.event_bindings.has(event):
		obj.event_bindings[event].payload = fields


func handle_signal(obj, args: Array) -> void:
	var sig := str(args[0]) if args.size() > 0 else ""
	var target := str(args[1]) if args.size() > 1 else ""
	if sig == "" or target == "":
		ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/signal", "Need <signal> <target>")
		return
	if obj.signal_bindings.has(sig):
		obj.signal_bindings[sig].disconnect_signal()
	var sb = SignalBinding.new()
	sb.obj = obj
	sb.ctx = ctx
	sb.signal_name = sig
	sb.target = target
	var options := args.slice(2)
	if options.size() > 0 and str(options[0]) == "payload":
		sb.payload_spec = options.slice(1)
	if sb.connect_signal():
		obj.signal_bindings[sig] = sb


func detach_object(obj) -> void:
	for sb in obj.signal_bindings.values():
		sb.disconnect_signal()
	obj.signal_bindings.clear()
	obj.event_bindings.clear()
	obj.input_bindings.clear()
	_hover.erase(obj.osc_id)


func _parse_options(b, options: Array) -> void:
	var i := 0
	while i + 1 < options.size():
		b.set_option(str(options[i]), options[i + 1])
		i += 2


# --- Input (dimension-agnostic via ctx.spatial.pick_hits) ----------------

func _input(event: InputEvent) -> void:
	if ctx == null:
		return
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var hits: Array = ctx.spatial.pick_hits(event.position)
		if event.pressed:
			_pressed = hits
			for h in hits:
				_emit_input(h, "down")
		else:
			for h in hits:
				_emit_input(h, "up")
			for h in _pressed:
				if _same_hit_present(hits, h):
					_emit_input(h, "click")
			_pressed = []
	elif event is InputEventMouseMotion:
		var hits: Array = ctx.spatial.pick_hits(event.position)
		if not _pressed.is_empty():
			for h in _pressed:
				_emit_input(h, "drag")
		_update_hover(hits)


func _emit_input(h: Dictionary, event: String) -> void:
	if h.type == "obj":
		var obj = h.obj
		if obj.input_bindings.has(event):
			ctx.send_event(obj.input_bindings[event]["address"], [obj.osc_id, h.nx, h.ny])
		ctx.send_event("/gscore/event/input", [event, obj.osc_id, h.nx, h.ny])
	elif h.type == "region":
		var obj = h.obj
		var reg = h.region
		if reg.bindings.has(event):
			ctx.send_event(reg.bindings[event], [obj.osc_id, reg.region_id, h.u, h.v])
		ctx.send_event("/gscore/event/input", [event, obj.osc_id + "/" + reg.region_id, h.u, h.v])


func _update_hover(hits: Array) -> void:
	var present := {}
	for h in hits:
		if h.type == "obj":
			present[h.obj.osc_id] = h
	# entered
	for id in present.keys():
		if not _hover.get(id, false):
			_hover[id] = true
			var h = present[id]
			var obj = h.obj
			if obj.input_bindings.has("enter"):
				ctx.send_event(obj.input_bindings["enter"]["address"], [obj.osc_id, h.nx, h.ny])
			ctx.send_event("/gscore/event/input", ["enter", obj.osc_id, h.nx, h.ny])
	# left
	for id in _hover.keys().duplicate():
		if _hover[id] and not present.has(id):
			_hover[id] = false
			var obj = ctx.registry.get_object(id)
			if obj != null and obj.input_bindings.has("leave"):
				ctx.send_event(obj.input_bindings["leave"]["address"], [obj.osc_id, 0.0, 0.0])
			ctx.send_event("/gscore/event/input", ["leave", id, 0.0, 0.0])


func _same_hit_present(arr: Array, h: Dictionary) -> bool:
	for o in arr:
		if o.type == h.type:
			if h.type == "obj" and o.obj == h.obj:
				return true
			if h.type == "region" and o.region == h.region:
				return true
	return false
