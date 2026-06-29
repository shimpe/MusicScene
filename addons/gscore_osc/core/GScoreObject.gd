extends RefCounted
## Wraps one Godot Node behind a stable OSC identity and applies the generic command surface
## (transforms, style, visibility, queries, controlled property/method access). Type-specific
## behaviour (physics, notation, events, signals) is attached by the respective managers and
## stored here as opaque references, keeping this wrapper focused.

const Mapper := preload("res://addons/gscore_osc/core/GScoreCoordinateMapper.gd")

# Identity
var osc_id: String = ""
var osc_path: String = ""          # e.g. /gscore/scene/score
var ownership: String = "created_by_osc"
var type_hint: String = "node"

# Wrapped node + controller context (GScoreRoot)
var node: Node = null
var ctx = null

# Exposure (controlled access)
var exposed_methods: Array = []
var exposed_properties: Dictionary = {}
var exposed_signals: Array = []
var allow_free: bool = false

# Attached helpers (set by subsystem managers)
var physics_adapter = null
var notation = null
var signal_bindings: Dictionary = {}   # godot_signal -> GScoreSignalBinding
var event_bindings: Dictionary = {}     # event -> GScoreEventBinding
var input_bindings: Dictionary = {}     # input event -> {address, payload}


func _init(p_id: String, p_node: Node, p_ctx) -> void:
	osc_id = p_id
	node = p_node
	ctx = p_ctx
	osc_path = "/gscore/scene/" + p_id


func is_valid() -> bool:
	return is_instance_valid(node)


func _mode() -> String:
	return ctx.mapper.app_mode if ctx and ctx.mapper else "normalized"


# =========================================================================
# Generic command dispatch (verbs that arrive as the first OSC argument).
# =========================================================================

func apply_command(cmd: String, args: Array) -> void:
	if not is_valid():
		ctx.error("unknown_object", osc_path, "Wrapped node is gone: " + osc_id)
		return
	match cmd:
		"show": _set_visible(true)
		"hide": _set_visible(false)
		"visible": _set_visible(_arg_bool(args, 0, true))
		"del": ctx.registry.delete(osc_id)
		"unbind": ctx.registry.unbind(osc_id)
		"free": ctx.registry.free_object(osc_id)
		"pos": _set_pos(_argf(args, 0), _argf(args, 1))
		"x": _set_axis(0, _argf(args, 0))
		"y": _set_axis(1, _argf(args, 0))
		"z": _set_z(_argf(args, 0))
		"size": _set_size(_argf(args, 0), _argf(args, 1))
		"width": _set_size(_argf(args, 0), _current_size_norm().y)
		"height": _set_size(_current_size_norm().x, _argf(args, 0))
		"scale": _set_scale(args)
		"rotate", "rotation": _set_rotation(_argf(args, 0))
		"opacity": _set_opacity(_argf(args, 0))
		"color": _set_color(args)
		"text": _set_text(_args_str(args, 0))
		"prop": _set_prop(args)
		"getprop": _get_prop(_args_str(args, 0))
		"call": _call_method(args)
		"get": _query_get(args)
		"dump": _dump()
		"capabilities": reply_capabilities()
		"methods": ctx.reply("methods", [osc_id] + exposed_methods)
		"properties": ctx.reply("properties", [osc_id] + exposed_properties.keys())
		"signals": ctx.reply("signals", [osc_id] + exposed_signals)
		"exists": ctx.reply("exists", [osc_id, true])
		_:
			ctx.error("bad_arguments", osc_path, "Unknown command '%s' for %s" % [cmd, osc_id])


# =========================================================================
# Transforms / style
# =========================================================================

func _set_visible(v: bool) -> void:
	if node is CanvasItem:
		node.visible = v
	elif "visible" in node:
		node.visible = v


func _set_pos(x: float, y: float) -> void:
	_apply_pos_px(ctx.mapper.point_to_pixels(x, y, _mode()))


func _set_axis(axis: int, value: float) -> void:
	var cur := _current_pos_norm()
	if axis == 0:
		cur.x = value
	else:
		cur.y = value
	_apply_pos_px(ctx.mapper.point_to_pixels(cur.x, cur.y, _mode()))


func _apply_pos_px(px: Vector2) -> void:
	if node is Node2D:
		node.global_position = px
	elif node is Control:
		node.set_global_position(px)
	elif node.has_method("set_global_position"):
		node.set_global_position(px)


func _current_pos_norm() -> Vector2:
	var px := Vector2.ZERO
	if node is Node2D:
		px = node.global_position
	elif node is Control:
		px = node.global_position
	return ctx.mapper.point_from_pixels(px, _mode())


func _set_z(value: float) -> void:
	if node is CanvasItem:
		node.z_index = int(value)


func _set_size(w: float, h: float) -> void:
	var wpx: float = ctx.mapper.length_x_to_pixels(w, _mode())
	var hpx: float = ctx.mapper.length_y_to_pixels(h, _mode())
	if node.has_method("gscore_set_size"):
		node.gscore_set_size(wpx, hpx)
	elif node is Sprite2D:
		var spr := node as Sprite2D
		if spr.texture != null:
			var t := spr.texture.get_size()
			if t.x > 0 and t.y > 0:
				spr.scale = Vector2(wpx / t.x, hpx / t.y)
	elif node is Control:
		var ctrl := node as Control
		ctrl.custom_minimum_size = Vector2(wpx, hpx)
		ctrl.size = Vector2(wpx, hpx)


func _current_size_norm() -> Vector2:
	# Best-effort current size in the current coord units; used by width/height partial updates.
	var px := Vector2(80, 80)
	if node is Sprite2D:
		var spr := node as Sprite2D
		if spr.texture != null:
			px = spr.texture.get_size() * spr.scale
	elif node.has_method("gscore_get_bounds"):
		px = node.gscore_get_bounds().size
	elif node is Control:
		px = (node as Control).size
	if _mode() == "normalized":
		var vp: Vector2 = ctx.mapper.viewport_size()
		return Vector2(px.x / (vp.x * 0.5), px.y / (vp.y * 0.5))
	return px


func _set_scale(args: Array) -> void:
	var sx := _argf(args, 0, 1.0)
	var sy := _argf(args, 1, sx) if args.size() > 1 else sx
	if "scale" in node:
		node.scale = Vector2(sx, sy)


func _set_rotation(degrees: float) -> void:
	if "rotation" in node:
		node.rotation = deg_to_rad(degrees)


func _set_opacity(a: float) -> void:
	if node is CanvasItem:
		var m: Color = node.modulate
		m.a = clampf(a, 0.0, 1.0)
		node.modulate = m


func _set_color(args: Array) -> void:
	var c := _args_color(args, 0)
	if node.has_method("gscore_set_color"):
		node.gscore_set_color(c)
	elif node is CanvasItem:
		node.modulate = c


func _set_text(t: String) -> void:
	if node.has_method("gscore_set_text"):
		node.gscore_set_text(t)
	elif "text" in node:
		node.text = t


# =========================================================================
# Controlled property / method access
# =========================================================================

func _set_prop(args: Array) -> void:
	if args.is_empty():
		ctx.error("bad_arguments", osc_path + "/prop", "Missing property name")
		return
	var prop := String(args[0])
	if not ctx.permissions.can_set_property(exposed_properties, prop):
		ctx.error("permission_denied", osc_path + "/prop", "Property not exposed: " + prop)
		return
	var value = _coerce_value(args.slice(1))
	node.set(prop, value)


func _get_prop(prop: String) -> void:
	if prop == "":
		ctx.error("bad_arguments", osc_path + "/getProp", "Missing property name")
		return
	if not (prop in node):
		ctx.error("unknown_property", osc_path + "/getProp", "No such property: " + prop)
		return
	ctx.reply("getProp", [osc_id, prop] + _flatten(node.get(prop)))


func _call_method(args: Array) -> void:
	if args.is_empty():
		ctx.error("bad_arguments", osc_path + "/call", "Missing method name")
		return
	var method := String(args[0])
	if not ctx.permissions.can_call_method(exposed_methods, method):
		ctx.error("permission_denied", osc_path + "/call", "Method not OSC-exposed: " + method)
		return
	if not node.has_method(method):
		ctx.error("unknown_property", osc_path + "/call", "No such method: " + method)
		return
	var result = node.callv(method, args.slice(1))
	ctx.reply("call", [osc_id, method] + _flatten(result))


# =========================================================================
# Queries
# =========================================================================

func _query_get(args: Array) -> void:
	var prop := _args_str(args, 0)
	if prop == "*" or prop == "":
		_dump()
		return
	var value = _generic_get(prop)
	if value == null and not (prop in node):
		ctx.error("unknown_property", osc_path + "/get", "Unknown property: " + prop)
		return
	if value == null:
		value = node.get(prop)
	ctx.reply("get", [osc_id, prop] + _flatten(value))


func _generic_get(prop: String):
	match prop:
		"pos": return _current_pos_norm()
		"x": return _current_pos_norm().x
		"y": return _current_pos_norm().y
		"z": return node.z_index if node is CanvasItem else 0
		"rotation": return rad_to_deg(node.rotation) if "rotation" in node else 0.0
		"scale": return node.scale if "scale" in node else Vector2.ONE
		"opacity": return node.modulate.a if node is CanvasItem else 1.0
		"visible": return node.visible if node is CanvasItem else true
		"type": return type_hint
		"text": return node.text if "text" in node else ""
		_: return null


func _dump() -> void:
	var p := _current_pos_norm()
	var values := [
		osc_id, type_hint, ownership,
		"pos", p.x, p.y,
		"visible", (node.visible if node is CanvasItem else true),
		"opacity", (node.modulate.a if node is CanvasItem else 1.0),
		"rotation", (rad_to_deg(node.rotation) if "rotation" in node else 0.0),
		"node", str(node.get_path()) if node.is_inside_tree() else node.name,
		"class", node.get_class(),
	]
	ctx.reply("dump", values)


func reply_capabilities() -> void:
	var caps: Array = ["transform"]
	if physics_adapter != null or _is_physics_node():
		caps.append("physics")
	if physics_adapter != null:
		caps.append("collision")
	if notation != null:
		caps.append("notation")
	caps.append("input")
	if not exposed_properties.is_empty() or ctx.permissions.developer_mode:
		caps.append("customProperties")
	if not exposed_methods.is_empty() or ctx.permissions.developer_mode:
		caps.append("customMethods")
	if not exposed_signals.is_empty():
		caps.append("signals")
	ctx.reply("capabilities", [osc_id] + caps)


func _is_physics_node() -> bool:
	return node is PhysicsBody2D or node is Area2D or node is RigidBody2D


# =========================================================================
# Argument helpers
# =========================================================================

func _argf(args: Array, i: int, def: float = 0.0) -> float:
	if i < args.size() and (args[i] is float or args[i] is int):
		return float(args[i])
	if i < args.size() and args[i] is String and args[i].is_valid_float():
		return float(args[i])
	return def


func _arg_bool(args: Array, i: int, def: bool = false) -> bool:
	if i >= args.size():
		return def
	var a = args[i]
	if a is bool:
		return a
	if a is int or a is float:
		return float(a) != 0.0
	if a is String:
		return a == "1" or a.to_lower() == "true"
	return def


func _args_str(args: Array, i: int, def: String = "") -> String:
	return String(args[i]) if i < args.size() else def


func _args_color(args: Array, start: int) -> Color:
	var r := _argf(args, start, 1.0)
	var g := _argf(args, start + 1, 1.0)
	var b := _argf(args, start + 2, 1.0)
	var a := _argf(args, start + 3, 1.0)
	return Color(r, g, b, a)


## Build a single value from trailing OSC args: 1->scalar/string, 2->Vector2, 3->Vector3,
## 4->Color. Strings pass through untouched.
func _coerce_value(rest: Array):
	if rest.is_empty():
		return null
	if rest.size() == 1:
		return rest[0]
	var nums := true
	for v in rest:
		if not (v is int or v is float):
			nums = false
			break
	if not nums:
		return rest
	match rest.size():
		2: return Vector2(rest[0], rest[1])
		3: return Vector3(rest[0], rest[1], rest[2])
		4: return Color(rest[0], rest[1], rest[2], rest[3])
		_: return rest


## Flatten common Variant types into a flat Array of OSC-encodable scalars.
func _flatten(v) -> Array:
	match typeof(v):
		TYPE_NIL: return []
		TYPE_VECTOR2, TYPE_VECTOR2I: return [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I: return [v.x, v.y, v.z]
		TYPE_COLOR: return [v.r, v.g, v.b, v.a]
		TYPE_RECT2, TYPE_RECT2I: return [v.position.x, v.position.y, v.size.x, v.size.y]
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return [v]
		_:
			return [str(v)]
