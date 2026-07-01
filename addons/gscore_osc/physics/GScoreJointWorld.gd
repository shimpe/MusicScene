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

func handle_global(rest, args: Array) -> void:
	# /gscore/joints list  — accept both path-tail form and OSC-arg form
	var query: String = str(rest[0]).to_lower() if rest.size() > 0 else (str(args[0]).to_lower() if args.size() > 0 else "")
	if query == "list":
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
		"info":
			ctx.reply("joint/info", [id, j.jtype, j.obj_a.osc_id, j.obj_b.osc_id, j.break_force, j.active_dof])
		_:
			if not j.apply(verb, rest_args):
				if ctx.verbose:
					print("[GScoreOSC] joint '%s' (%s): '%s' is a no-op for this type" % [id, j.jtype, verb])

func _create(id: String, args: Array) -> void:
	if id.is_empty():
		ctx.error("bad_arguments", "/gscore/joint", "Missing joint id"); return
	var jtype := str(args[0]).to_lower() if args.size() > 0 else ""
	var a_id := str(args[1]) if args.size() > 1 else ""
	var b_id := str(args[2]) if args.size() > 2 else ""
	var base := "/gscore/joint/" + id

	if not ctx.spatial.joint_types().has(jtype):
		ctx.error("bad_arguments", base, "joint type '%s' is not available in %s space" % [jtype, ctx.space])
		return
	var obj_a = ctx.registry.get_object(a_id)
	var obj_b = ctx.registry.get_object(b_id)
	if obj_a == null:
		ctx.error("unknown_object", base, "Unknown joint endpoint: " + a_id); return
	if obj_b == null:
		ctx.error("unknown_object", base, "Unknown joint endpoint: " + b_id); return
	var body_a = _body_of(obj_a)
	var body_b = _body_of(obj_b)
	if body_a == null:
		ctx.error("bad_arguments", base, "endpoint '%s' has no physics body; enable physics first" % a_id); return
	if body_b == null:
		ctx.error("bad_arguments", base, "endpoint '%s' has no physics body; enable physics first" % b_id); return

	if _joints.has(id):
		_remove(id)  # re-create frees the old joint first

	var node: Node = ctx.spatial.make_joint(jtype)
	if node == null:
		ctx.error("bad_arguments", base, "could not build joint of type: " + jtype); return
	node.name = id + "_joint"
	ctx.objects_root.add_child(node)              # in-tree (correctly-typed parent) before NodePaths are set
	ctx.spatial.joint_attach(node, body_a, body_b)

	var j = GScoreJoint.new(ctx, id)
	j.jtype = jtype
	j.node = node
	j.obj_a = obj_a; j.obj_b = obj_b
	j.body_a = body_a; j.body_b = body_b
	j.rest_separation = ctx.spatial.joint_separation(node, body_a, body_b)
	_joints[id] = j
	if jtype == "distance":
		# stiff-spring preset: near-rigid rod at the initial separation
		ctx.spatial.joint_set_param(node, jtype, "stiffness", [1.0], "all", ctx.mapper.physics_mode)
		ctx.spatial.joint_set_param(node, jtype, "damping", [0.8], "all", ctx.mapper.physics_mode)
	if jtype == "spring":
		# low-damping preset: distinguishes spring from dampedSpring (which keeps engine default)
		ctx.spatial.joint_set_param(node, jtype, "damping", [0.1], "all", ctx.mapper.physics_mode)
	if ctx.verbose:
		print("[GScoreOSC] joint '%s' (%s) %s <-> %s" % [id, jtype, a_id, b_id])

func _body_of(obj):
	if obj == null:
		return null
	if obj.physics_adapter != null and obj.physics_adapter.is_valid():
		return obj.physics_adapter.body
	if ctx.spatial.is_physics_body(obj.node):
		return obj.node
	return null

func _remove(id: String) -> void:
	var j = _joints.get(id)
	if j != null and is_instance_valid(j.node):
		j.node.queue_free()
	_joints.erase(id)

## Remove every joint and free its node. Called on scene clear so no stale joint survives a
## rebuild (a lingering joint's name-based node_a/node_b could re-bind to new bodies or dangle).
func clear() -> void:
	for id in _joints.keys():
		var j = _joints[id]
		if j != null and is_instance_valid(j.node):
			j.node.queue_free()
	_joints.clear()

# --- Per physics frame ---------------------------------------------------

func physics_step(_delta: float) -> void:
	var simulating: bool = ctx.physics_world != null and ctx.physics_world.is_simulating()
	# Joints have no visual; when the physics debug flag is on we draw a per-joint overlay so hinges,
	# springs, etc. are visible. Shares the /gscore/physics debug toggle with collision-shape display.
	var debug_on: bool = ctx.physics_world != null and ctx.physics_world.debug
	for id in _joints.keys().duplicate():
		var j = _joints[id]
		if not j.is_valid():
			_remove(id)  # endpoint died; prune silently
			continue
		if simulating and j.should_break():
			var a_id: String = j.obj_a.osc_id
			var b_id: String = j.obj_b.osc_id
			_remove(id)
			ctx.send_event("/gscore/event/jointBreak", [id, a_id, b_id])
			if ctx.verbose:
				print("[GScoreOSC] joint '%s' broke (overstretch)" % id)
			continue
		j.update_debug(debug_on)
