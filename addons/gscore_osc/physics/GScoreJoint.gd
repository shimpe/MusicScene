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

func _init(p_ctx, p_id: String) -> void:
	ctx = p_ctx
	osc_id = p_id

func is_valid() -> bool:
	return is_instance_valid(node) and is_instance_valid(body_a) and is_instance_valid(body_b)
