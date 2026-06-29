extends RefCounted
## Maps transport time to object/cursor properties via linear interpolation. Each frame, every
## active map sets its property to lerp(from, to) across [time_start, time_end]; the value is
## held at the endpoints outside the window. Maps whose target has been deleted are dropped
## automatically (each entry carries an `alive` predicate).
##
##   /gscore/scene/<id> map <t0> <t1> <property> <from> <to>
##   /gscore/scene/<id>/cursor map <t0> <t1> <property> <from> <to>   (property x|y|opacity)

var ctx = null
# entry: {start, end, from, to, setter: Callable, target: Object, kind: "obj"|"node"}
# `target` is validated DIRECTLY (no lambda) so a freed target never triggers a lambda call.
var _maps: Array = []


func _init(p_ctx) -> void:
	ctx = p_ctx


func add_map(obj, args: Array) -> void:
	if args.size() < 5:
		ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/map",
			"Need <t0> <t1> <property> <from> <to>")
		return
	var prop := String(args[2])
	var setter := func(val): obj.apply_command(prop, [val])
	_append(args, setter, obj, "obj")


func add_cursor_map(notation, args: Array) -> void:
	if args.size() < 5:
		ctx.error("bad_arguments", "/gscore/scene/" + notation.osc_id + "/cursor/map",
			"Need <t0> <t1> <property> <from> <to>")
		return
	var prop := String(args[2])
	var setter := func(val):
		match prop:
			"x":
				notation.cursor.set_u(val)
			"y":
				notation.cursor.v = val
				notation.cursor.queue_redraw()
			"opacity":
				var c: Color = notation.cursor.line_color
				c.a = val
				notation.cursor.line_color = c
				notation.cursor.queue_redraw()
	_append(args, setter, notation, "node")


func _append(args: Array, setter: Callable, target, kind: String) -> void:
	_maps.append({
		"start": _f(args, 0), "end": _f(args, 1),
		"from": _f(args, 3), "to": _f(args, 4),
		"setter": setter, "target": target, "kind": kind,
	})


func clear() -> void:
	_maps.clear()


func update(time: float) -> void:
	var dead: Array = []
	for i in range(_maps.size()):
		var m = _maps[i]
		var ok: bool = m.target.is_valid() if m.kind == "obj" else is_instance_valid(m.target)
		if not ok:
			dead.append(i)
			continue
		var span: float = maxf(m.end - m.start, 0.000001)
		var t := clampf((time - m.start) / span, 0.0, 1.0)
		m.setter.call(lerpf(m.from, m.to, t))
	for j in range(dead.size() - 1, -1, -1):
		_maps.remove_at(dead[j])


func _f(args: Array, i: int, def: float = 0.0) -> float:
	if i < args.size():
		var x = args[i]
		if x is float or x is int:
			return float(x)
		if x is String and x.is_valid_float():
			return float(x)
	return def
