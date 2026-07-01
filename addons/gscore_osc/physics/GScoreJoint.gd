extends RefCounted
## One physics joint: wraps a native Godot joint node connecting two endpoint objects.
## Dimension-agnostic — all native mutation goes through ctx.spatial.

var ctx = null
var osc_id: String = ""
var jtype: String = ""
var node: Node = null            # the Godot joint node
var obj_a = null                 # GScoreObject endpoints
var obj_b = null
var body_a: Node = null
var body_b: Node = null
var rest_separation: float = 0.0 # native units, captured at creation; updated by restLength
var break_force: float = 0.0     # 0 disables breaking
var active_dof: String = "all"   # generic6dof DOF cursor
var debug_vis: Node = null       # optional debug overlay (line + pivot + axis), child of `node`

func _init(p_ctx, p_id: String) -> void:
	ctx = p_ctx
	osc_id = p_id

func is_valid() -> bool:
	return is_instance_valid(node) and is_instance_valid(body_a) and is_instance_valid(body_b)

func _mode() -> String:
	return ctx.mapper.physics_mode

## Apply a property verb. Returns false (logged no-op) when the joint type doesn't support it.
func apply(verb: String, args: Array) -> bool:
	match verb:
		"dof":
			if jtype != "generic6dof":
				return false   # logged no-op via the world's verbose message
			active_dof = str(args[0]).to_lower() if args.size() > 0 else "all"
			return true
		"breakforce":
			break_force = _f(args, 0, 0.0)
			return true
		"restlength":
			var ok: bool = ctx.spatial.joint_set_param(node, jtype, "restlength", args, active_dof, _mode())
			if ok and args.size() > 0:
				rest_separation = ctx.spatial.to_native_length(_f(args, 0, 0.0), _mode())
			return ok
		"stiffness", "damping", "limit", "motor", "axis":
			return ctx.spatial.joint_set_param(node, jtype, verb, args, active_dof, _mode())
		_:
			return false

## Overstretch proxy for breakForce. Godot exposes no joint reaction force, so we break when the
## endpoint separation exceeds rest + tolerance; tolerance shrinks as break_force -> 1.
## If rest_separation is 0 (bodies co-located at creation), the maxf clamp makes the tolerance
## nearly zero, so the joint breaks on any separation.
func should_break() -> bool:
	if break_force <= 0.0:
		return false
	var sep: float = ctx.spatial.joint_separation(node, body_a, body_b)
	var rest: float = maxf(rest_separation, 0.0001)
	var tol: float = rest * lerp(2.0, 0.1, clampf(break_force, 0.0, 1.0))
	return sep > rest + tol

## Show or hide the debug overlay for this joint. A Joint node has no visual of its own, so when
## enabled we attach a spatial-drawn overlay (connection line A<->B, a pivot marker, and — for
## hinge/slider — the working axis) as a child of the joint node and refresh it each frame. The
## overlay is freed automatically when the joint node is freed, or here when hidden.
func update_debug(show: bool) -> void:
	if not show:
		if debug_vis != null and is_instance_valid(debug_vis):
			debug_vis.queue_free()
		debug_vis = null
		return
	if not is_valid():
		return
	if debug_vis == null or not is_instance_valid(debug_vis):
		debug_vis = ctx.spatial.make_joint_debug()
		if debug_vis != null:
			node.add_child(debug_vis)
	if debug_vis != null:
		ctx.spatial.update_joint_debug(debug_vis, node, body_a, body_b, jtype)

func _f(args: Array, i: int, def: float) -> float:
	if i < args.size():
		var a = args[i]
		if a is float or a is int:
			return float(a)
		if a is String and a.is_valid_float():
			return float(a)
	return def
