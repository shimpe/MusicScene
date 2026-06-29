extends Node
## Events manager. Routes /on /off /payload /signal, owns Godot signal->OSC bindings, and
## handles mouse/touch interaction by hit-testing registered objects and notation regions.
## Physics/area events are stored as GScoreEventBinding on the object (wired by the physics
## adapter); input events are stored as lightweight dicts on the object.

const EventBinding := preload("res://addons/gscore_osc/events/GScoreEventBinding.gd")
const SignalBinding := preload("res://addons/gscore_osc/events/GScoreSignalBinding.gd")
const InputUtil := preload("res://addons/gscore_osc/events/GScoreInputEvents.gd")

const INPUT_EVENTS := ["click", "down", "up", "drag", "enter", "leave"]

var ctx = null
var _hover: Dictionary = {}      # osc_id -> bool
var _pressed: Array = []          # hit descriptors captured on mouse-down


func setup(p_ctx) -> void:
	ctx = p_ctx


# --- Registration --------------------------------------------------------

func handle_on(obj, args: Array) -> void:
	var event := String(args[0]) if args.size() > 0 else ""
	var target := String(args[1]) if args.size() > 1 else ""
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
	var event := String(args[0]) if args.size() > 0 else ""
	if event in INPUT_EVENTS:
		obj.input_bindings.erase(event)
	else:
		obj.event_bindings.erase(event)


func handle_payload(obj, args: Array) -> void:
	var event := String(args[0]) if args.size() > 0 else ""
	var fields := args.slice(1)
	if event in INPUT_EVENTS:
		if obj.input_bindings.has(event):
			obj.input_bindings[event]["payload"] = fields
	elif obj.event_bindings.has(event):
		obj.event_bindings[event].payload = fields


func handle_signal(obj, args: Array) -> void:
	var sig := String(args[0]) if args.size() > 0 else ""
	var target := String(args[1]) if args.size() > 1 else ""
	if sig == "" or target == "":
		ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/signal", "Need <signal> <target>")
		return
	# Replace any existing binding for this signal.
	if obj.signal_bindings.has(sig):
		obj.signal_bindings[sig].disconnect_signal()
	var sb = SignalBinding.new()
	sb.obj = obj
	sb.ctx = ctx
	sb.signal_name = sig
	sb.target = target
	var options := args.slice(2)
	if options.size() > 0 and String(options[0]) == "payload":
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
		b.set_option(String(options[i]), options[i + 1])
		i += 2


# --- Input ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if ctx == null:
		return
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var gpos: Vector2 = ctx.get_global_mouse_position()
		var npos: Vector2 = ctx.mapper.point_from_pixels(gpos, ctx.mapper.app_mode)
		if event.pressed:
			_pressed = _hits(gpos)
			for h in _pressed:
				_emit_input(h, "down", npos, gpos)
		else:
			var ups := _hits(gpos)
			for h in ups:
				_emit_input(h, "up", npos, gpos)
			for h in _pressed:
				if _same_hit_present(ups, h):
					_emit_input(h, "click", npos, gpos)
			_pressed = []
	elif event is InputEventMouseMotion:
		var gpos: Vector2 = ctx.get_global_mouse_position()
		var npos: Vector2 = ctx.mapper.point_from_pixels(gpos, ctx.mapper.app_mode)
		if not _pressed.is_empty():
			for h in _pressed:
				_emit_input(h, "drag", npos, gpos)
		_update_hover(gpos, npos)


func _hits(gpos: Vector2) -> Array:
	var out: Array = []
	for id in ctx.registry.list_ids():
		var obj = ctx.registry.get_object(id)
		if obj == null:
			continue
		if obj.notation != null:
			for reg in obj.notation.hit_test_regions(gpos):
				out.append({"type": "region", "obj": obj, "region": reg})
		if not obj.input_bindings.is_empty() and InputUtil.object_hit(obj, gpos):
			out.append({"type": "obj", "obj": obj})
	return out


func _emit_input(h: Dictionary, event: String, npos: Vector2, gpos: Vector2) -> void:
	if h.type == "obj":
		var obj = h.obj
		if obj.input_bindings.has(event):
			ctx.send_event(obj.input_bindings[event]["address"], [obj.osc_id, npos.x, npos.y])
		ctx.send_event("/gscore/event/input", [event, obj.osc_id, npos.x, npos.y])
	elif h.type == "region":
		var obj = h.obj
		var reg = h.region
		var uv := _region_uv(obj, gpos)
		if reg.bindings.has(event):
			ctx.send_event(reg.bindings[event], [obj.osc_id, reg.region_id, uv.x, uv.y])
		ctx.send_event("/gscore/event/input",
			[event, obj.osc_id + "/" + reg.region_id, uv.x, uv.y])


func _region_uv(obj, gpos: Vector2) -> Vector2:
	var n = obj.notation
	var local: Vector2 = n.to_local(gpos)
	if n.page_size.x <= 0 or n.page_size.y <= 0:
		return Vector2.ZERO
	return Vector2(local.x / n.page_size.x + 0.5, local.y / n.page_size.y + 0.5)


func _update_hover(gpos: Vector2, npos: Vector2) -> void:
	for id in ctx.registry.list_ids():
		var obj = ctx.registry.get_object(id)
		if obj == null or obj.input_bindings.is_empty():
			continue
		var hit := InputUtil.object_hit(obj, gpos)
		var was: bool = _hover.get(id, false)
		if hit and not was:
			_hover[id] = true
			if obj.input_bindings.has("enter"):
				ctx.send_event(obj.input_bindings["enter"]["address"], [obj.osc_id, npos.x, npos.y])
			ctx.send_event("/gscore/event/input", ["enter", obj.osc_id, npos.x, npos.y])
		elif not hit and was:
			_hover[id] = false
			if obj.input_bindings.has("leave"):
				ctx.send_event(obj.input_bindings["leave"]["address"], [obj.osc_id, npos.x, npos.y])
			ctx.send_event("/gscore/event/input", ["leave", obj.osc_id, npos.x, npos.y])


func _same_hit_present(arr: Array, h: Dictionary) -> bool:
	for o in arr:
		if o.type == h.type:
			if h.type == "obj" and o.obj == h.obj:
				return true
			if h.type == "region" and o.region == h.region:
				return true
	return false
