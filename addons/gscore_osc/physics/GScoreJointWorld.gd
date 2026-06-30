extends RefCounted
## Owns the joint id-space and routes /gscore/joint(s) commands. Mirrors GScorePhysicsWorld:
## a per-frame physics_step monitors breakForce and prunes joints whose endpoints died.

const GScoreJoint := preload("res://addons/gscore_osc/physics/GScoreJoint.gd")

var ctx = null
var _joints: Dictionary = {}     # id -> GScoreJoint

func _init(p_ctx) -> void:
	ctx = p_ctx

func list_ids() -> Array:
	var out: Array = []
	for id in _joints.keys():
		if _joints[id].is_valid():
			out.append(id)
	return out

func has(id: String) -> bool:
	return _joints.has(id) and _joints[id].is_valid()

# --- Routing -------------------------------------------------------------

func handle_global(rest, _args: Array) -> void:
	# /gscore/joints list
	if rest.size() > 0 and str(rest[0]) == "list":
		var values: Array = []
		for id in list_ids():
			values.append(id)
			values.append(_joints[id].jtype)
		ctx.reply("joints/list", values)
	else:
		ctx.error("bad_arguments", "/gscore/joints", "Expected list")

func handle(id: String, args: Array) -> void:
	var verb := str(args[0]).to_lower() if args.size() > 0 else ""
	var rest_args := args.slice(1)
	if verb == "new":
		_create(id, rest_args)
		return
	var j = _joints.get(id)
	if j == null or not j.is_valid():
		ctx.error("unknown_object", "/gscore/joint/" + id, "Unknown joint: " + id)
		return
	match verb:
		"del", "delete":
			_remove(id)
		_:
			ctx.error("bad_arguments", "/gscore/joint/" + id, "Unknown joint cmd: " + verb)

func _create(_id: String, _args: Array) -> void:
	pass  # implemented in Task 2

func _remove(id: String) -> void:
	var j = _joints.get(id)
	if j != null and is_instance_valid(j.node):
		j.node.queue_free()
	_joints.erase(id)

# --- Per physics frame ---------------------------------------------------

func physics_step(_delta: float) -> void:
	for id in _joints.keys().duplicate():
		if not _joints[id].is_valid():
			_remove(id)  # endpoint died; prune silently
