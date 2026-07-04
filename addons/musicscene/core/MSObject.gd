extends RefCounted
## Wraps one Godot Node behind a stable OSC identity and applies the generic command surface
## (transforms, style, visibility, queries, controlled property/method access). Dimension-specific
## work (positioning, scale, primitives, physics) is delegated to ctx.spatial so the same wrapper
## serves both 2D and 3D. Type-specific behaviour (physics, notation, events, signals) is attached
## by the respective managers and stored here as opaque references.

# Identity
var osc_id: String = ""
var osc_path: String = ""          # e.g. /ms/scene/score
var ownership: String = "created_by_osc"
var type_hint: String = "node"

# Wrapped node + controller context (MSRoot)
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
var signal_bindings: Dictionary = {}
var event_bindings: Dictionary = {}
var input_bindings: Dictionary = {}


func _init(p_id: String, p_node: Node, p_ctx) -> void:
	osc_id = p_id
	node = p_node
	ctx = p_ctx
	osc_path = "/ms/scene/" + p_id


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
		"pos": ctx.spatial.set_position(node, _argf(args, 0), _argf(args, 1), _argf(args, 2), _mode())
		"x": ctx.spatial.set_axis(node, 0, _argf(args, 0), _mode())
		"y": ctx.spatial.set_axis(node, 1, _argf(args, 0), _mode())
		"z": ctx.spatial.set_axis(node, 2, _argf(args, 0), _mode())
		"size": ctx.spatial.set_size(node, _argf(args, 0), _argf(args, 1), _mode())
		"width": ctx.spatial.set_size(node, _argf(args, 0), ctx.spatial.get_size_norm(node, _mode()).y, _mode())
		"height": ctx.spatial.set_size(node, ctx.spatial.get_size_norm(node, _mode()).x, _argf(args, 0), _mode())
		"scale": _set_scale(args)
		"rotate", "rotation": ctx.spatial.set_rotation(node, args, _mode())
		"opacity": ctx.spatial.set_opacity(node, _argf(args, 0))
		"color": ctx.spatial.set_color(node, _args_color(args, 0))
		"shaded": ctx.spatial.set_shaded(node, _arg_bool(args, 0, true))
		"metallic": ctx.spatial.set_metallic(node, _argf(args, 0))
		"roughness": ctx.spatial.set_roughness(node, _argf(args, 0))
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
# Transforms / style (delegated to the spatial backend)
# =========================================================================

func _set_visible(v: bool) -> void:
	if "visible" in node:
		node.visible = v


func _set_scale(args: Array) -> void:
	if args.is_empty():
		return
	var sx := _argf(args, 0, 1.0)
	if args.size() == 1:
		ctx.spatial.set_scale(node, sx, sx, sx)
	elif args.size() == 2:
		ctx.spatial.set_scale(node, sx, _argf(args, 1, 1.0), 1.0)
	else:
		ctx.spatial.set_scale(node, sx, _argf(args, 1, 1.0), _argf(args, 2, 1.0))


func _set_text(t: String) -> void:
	if node.has_method("ms_set_text"):
		node.ms_set_text(t)
	elif "text" in node:
		node.text = t


# =========================================================================
# Controlled property / method access
# =========================================================================

func _set_prop(args: Array) -> void:
	if args.is_empty():
		ctx.error("bad_arguments", osc_path + "/prop", "Missing property name")
		return
	var prop := str(args[0])
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
	var method := str(args[0])
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
	var p = ctx.spatial.get_position_norm(node, _mode())
	match prop:
		"pos": return p
		"x": return p.x
		"y": return p.y
		"z": return (p.z if typeof(p) == TYPE_VECTOR3 else 0.0)
		"rotation": return ctx.spatial.get_rotation_deg(node)
		"scale": return ctx.spatial.get_scale(node)
		"opacity": return ctx.spatial.get_opacity(node)
		"visible": return node.visible if "visible" in node else true
		"type": return type_hint
		"text": return node.text if "text" in node else ""
		_: return null


func _dump() -> void:
	var p = ctx.spatial.get_position_norm(node, _mode())
	var values := [osc_id, type_hint, ownership, "pos"]
	values.append_array(_flatten(p))
	values.append_array([
		"visible", (node.visible if "visible" in node else true),
		"opacity", ctx.spatial.get_opacity(node),
		"node", str(node.get_path()) if node.is_inside_tree() else String(node.name),
		"class", node.get_class(),
	])
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
	return node is PhysicsBody2D or node is Area2D or node is PhysicsBody3D or node is Area3D


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
	return str(args[i]) if i < args.size() else def


func _args_color(args: Array, start: int) -> Color:
	return Color(_argf(args, start, 1.0), _argf(args, start + 1, 1.0),
		_argf(args, start + 2, 1.0), _argf(args, start + 3, 1.0))


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
