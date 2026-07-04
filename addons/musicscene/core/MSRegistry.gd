extends RefCounted
## The heart of OSC<->Godot identity decoupling. Maps stable OSC ids to MSObject wrappers,
## tracks ownership, and implements creation/binding/instantiation plus the unbind/del/free
## lifecycle. All object lookups in the system go through here.

const MSObject := preload("res://addons/musicscene/core/MSObject.gd")
const MSFactory := preload("res://addons/musicscene/core/MSFactory.gd")
const OscExposableClass := preload("res://addons/musicscene/nodes/OscExposable.gd")

# Ownership types
const OWN_CREATED := "created_by_osc"
const OWN_INSTANTIATED := "instantiated_by_osc"
const OWN_BOUND := "bound_existing"
const OWN_AUTO := "auto_bound"
const OWN_GROUP := "group_binding"

var ctx = null
var _objects: Dictionary = {}        # id -> MSObject
var _by_nodepath: Dictionary = {}    # node path string -> id
var app_root_path: NodePath = NodePath("")


func _init(p_ctx) -> void:
	ctx = p_ctx


# --- Lookup --------------------------------------------------------------

func has(id: String) -> bool:
	return _objects.has(id) and _objects[id].is_valid()


func get_object(id: String):
	var o = _objects.get(id)
	if o != null and not o.is_valid():
		_objects.erase(id)
		return null
	return o


func list_ids() -> Array:
	var ids: Array = []
	for id in _objects.keys():
		if _objects[id].is_valid():
			ids.append(id)
	return ids


func id_for_node(node: Node) -> String:
	if node == null or not node.is_inside_tree():
		return ""
	return _by_nodepath.get(str(node.get_path()), "")


## Called when an object's wrapped node changes (e.g. the physics adapter wraps a visual in a
## body). Keeps the node-path -> id reverse map consistent.
func update_node_mapping(obj, old_path: String) -> void:
	if old_path != "":
		_by_nodepath.erase(old_path)
	if obj.is_valid() and obj.node.is_inside_tree():
		_by_nodepath[str(obj.node.get_path())] = obj.osc_id


# --- Registration --------------------------------------------------------

func register_object(id: String, node: Node, ownership: String) -> MSObject:
	if node == null:
		ctx.error("internal_error", "/ms/scene/" + id, "Cannot register null node")
		return null
	if _objects.has(id):
		# Replacing an id: free the old node if MusicScene created/instantiated it (otherwise it would
		# orphan in the tree); for bound/auto-bound nodes just drop the binding (not ours to free).
		var prev = _objects[id]
		if prev.ownership == OWN_CREATED or prev.ownership == OWN_INSTANTIATED:
			delete(id)
		else:
			unbind(id)
	var obj := MSObject.new(id, node, ctx)
	obj.ownership = ownership
	_objects[id] = obj
	if node.is_inside_tree():
		_by_nodepath[str(node.get_path())] = id
	return obj


func create_builtin(id: String, type: String, args: Array) -> MSObject:
	var node := MSFactory.create(type, args, ctx)
	if node == null:
		return null
	ctx.objects_root.add_child(node)
	var obj := register_object(id, node, OWN_CREATED)
	obj.type_hint = type
	if type == "bouncer" or type == "portal":
		ctx.physics_world.enable_area(obj)
	if type == "notation" and ctx.notation != null:
		ctx.notation.attach(obj)
	if ctx.verbose:
		print("[MusicSceneOSC] created %s '%s'" % [type, id])
	return obj


func bind(id: String, abs_path: String) -> MSObject:
	var node: Node = ctx.get_node_or_null(NodePath(abs_path))
	return _bind_node(id, node, abs_path, OWN_BOUND)


func bind_rel(id: String, rel_path: String) -> MSObject:
	var root := _resolve_app_root()
	if root == null:
		ctx.error("unknown_object", "/ms/bindRel", "No app root set; use /ms/app/root")
		return null
	var node: Node = root.get_node_or_null(NodePath(rel_path))
	return _bind_node(id, node, rel_path, OWN_BOUND)


func _bind_node(id: String, node: Node, where: String, ownership: String) -> MSObject:
	if node == null:
		ctx.error("unknown_object", "/ms/bind", "No node at: " + where)
		return null
	var exposable = find_exposable(node)
	var is_exposed := exposable != null or node.has_meta("osc_expose")
	if not ctx.permissions.can_bind(is_exposed):
		ctx.error("permission_denied", "/ms/bind",
			"Node not OSC-exposed (enable developer_mode or add OscExposable): " + where)
		return null
	var obj := register_object(id, node, ownership)
	apply_exposure(obj)
	if ctx.verbose:
		print("[MusicSceneOSC] bound '%s' -> %s" % [id, where])
	return obj


func bind_group(group_id: String, godot_group: String) -> Array:
	var bound: Array = []
	var nodes = ctx.get_tree().get_nodes_in_group(godot_group)
	var i := 0
	for n in nodes:
		var sub_id := "%s.%d" % [group_id, i]
		var obj := register_object(sub_id, n, OWN_GROUP)
		apply_exposure(obj)
		bound.append(sub_id)
		i += 1
	return bound


func instantiate(id: String, scene_path: String, parent_ref: String = "") -> MSObject:
	if not ctx.permissions.can_instantiate_path(scene_path):
		ctx.error("permission_denied", "/ms/scene/" + id,
			"Scene not whitelisted: " + scene_path)
		return null
	if not ResourceLoader.exists(scene_path):
		ctx.error("load_failed", "/ms/scene/" + id, "Scene not found: " + scene_path)
		return null
	var packed = load(scene_path)
	if not (packed is PackedScene):
		ctx.error("load_failed", "/ms/scene/" + id, "Not a PackedScene: " + scene_path)
		return null
	var inst: Node = packed.instantiate()
	var parent := _resolve_parent(parent_ref)
	parent.add_child(inst)
	var obj := register_object(id, inst, OWN_INSTANTIATED)
	obj.type_hint = "scene"
	apply_exposure(obj)
	if ctx.verbose:
		print("[MusicSceneOSC] instantiated '%s' from %s" % [id, scene_path])
	return obj


# --- Lifecycle -----------------------------------------------------------

func unbind(id: String) -> void:
	var obj = _objects.get(id)
	if obj == null:
		return
	_cleanup(obj)
	if obj.is_valid() and obj.node.is_inside_tree():
		_by_nodepath.erase(str(obj.node.get_path()))
	_objects.erase(id)


func delete(id: String) -> void:
	var obj = get_object(id)
	if obj == null:
		ctx.error("unknown_object", "/ms/scene/" + id, "Unknown object: " + id)
		return
	if obj.ownership == OWN_CREATED or obj.ownership == OWN_INSTANTIATED:
		_cleanup(obj)
		var n = obj.node
		_objects.erase(id)
		if is_instance_valid(n):
			n.queue_free()
	else:
		unbind(id)


func free_object(id: String) -> void:
	var obj = get_object(id)
	if obj == null:
		ctx.error("unknown_object", "/ms/scene/" + id, "Unknown object: " + id)
		return
	if not ctx.permissions.can_free(obj.allow_free):
		ctx.error("permission_denied", "/ms/scene/" + id,
			"freeNodes disabled for: " + id)
		return
	_cleanup(obj)
	var n = obj.node
	_objects.erase(id)
	if is_instance_valid(n):
		n.queue_free()


func clear() -> void:
	for id in _objects.keys().duplicate():
		var obj = _objects[id]
		if obj.ownership == OWN_CREATED or obj.ownership == OWN_INSTANTIATED:
			delete(id)
		else:
			unbind(id)


func _cleanup(obj) -> void:
	if ctx.events != null:
		ctx.events.detach_object(obj)
	for sb in obj.signal_bindings.values():
		if sb.has_method("disconnect_signal"):
			sb.disconnect_signal()
	obj.signal_bindings.clear()
	# Break the MSObject <-> adapter reference cycle so nothing leaks at exit.
	if obj.physics_adapter != null:
		if ctx.physics_world != null:
			ctx.physics_world.remove_adapter(obj.physics_adapter)
		obj.physics_adapter.obj = null
		obj.physics_adapter = null
	obj.notation = null


# --- Discovery -----------------------------------------------------------

func discover_all() -> Array:
	var out: Array = []
	for n in _all_nodes_in_scene():
		out.append(_describe(n))
	return out


func discover_group(group: String) -> Array:
	var out: Array = []
	for n in ctx.get_tree().get_nodes_in_group(group):
		out.append(_describe(n))
	return out


func discover_type(cls: String) -> Array:
	var out: Array = []
	for n in _all_nodes_in_scene():
		if n.is_class(cls) or n.get_class() == cls:
			out.append(_describe(n))
	return out


func discover_meta(key: String, value = null) -> Array:
	var out: Array = []
	for n in _all_nodes_in_scene():
		if not n.has_meta(key):
			continue
		if value == null or str(n.get_meta(key)) == str(value):
			out.append(_describe(n))
	return out


func _describe(n: Node) -> Dictionary:
	var sid := id_for_node(n)
	if sid == "":
		var ex = find_exposable(n)
		sid = ex.suggested_id() if ex != null else n.name.to_snake_case()
	return {
		"suggested_id": sid,
		"path": str(n.get_path()) if n.is_inside_tree() else String(n.name),
		"class": n.get_class(),
		"name": String(n.name),
	}


# --- Exposure ------------------------------------------------------------

## Find the OscExposable controlling `node`: the node's own script, or a child marker.
func find_exposable(node: Node):
	if node is OscExposableClass and node.get_target() == node:
		return node
	for c in node.get_children():
		if c is OscExposableClass and c.get_target() == node:
			return c
	return null


func apply_exposure(obj) -> void:
	var node: Node = obj.node
	var ex = find_exposable(node)
	if ex != null:
		obj.exposed_methods = ex.osc_methods.duplicate()
		obj.exposed_properties = ex.osc_properties.duplicate()
		obj.exposed_signals = ex.osc_signals.duplicate()
		obj.allow_free = ex.osc_allow_free
	# Metadata-based extra exposure (merges with component config).
	if node.has_meta("osc_methods"):
		for m in node.get_meta("osc_methods"):
			if m not in obj.exposed_methods:
				obj.exposed_methods.append(m)
	if node.has_meta("osc_allow_free"):
		obj.allow_free = bool(node.get_meta("osc_allow_free"))


## Scan the running scene and auto-bind every OscExposable / osc_expose-tagged node.
func auto_bind_exposed() -> int:
	var count := 0
	for n in _all_nodes_in_scene():
		if n is OscExposableClass:
			if n.osc_auto_bind and n.osc_allow_bind:
				var target = n.get_target()
				if target != null and id_for_node(target) == "":
					var obj := register_object(n.suggested_id(), target, OWN_AUTO)
					apply_exposure(obj)
					count += 1
		elif n.has_meta("osc_expose") and bool(n.get_meta("osc_expose")):
			if id_for_node(n) == "":
				var mid := str(n.get_meta("osc_id")) if n.has_meta("osc_id") else String(n.name).to_snake_case()
				var obj := register_object(mid, n, OWN_AUTO)
				apply_exposure(obj)
				count += 1
	if ctx.verbose and count > 0:
		print("[MusicSceneOSC] auto-bound %d exposed node(s)" % count)
	return count


# --- Helpers -------------------------------------------------------------

func _resolve_app_root() -> Node:
	if String(app_root_path) == "":
		return null
	return ctx.get_node_or_null(app_root_path)


func _resolve_parent(parent_ref: String) -> Node:
	if parent_ref == "":
		return ctx.objects_root
	# Try an existing object id first, then a node path.
	var obj = get_object(parent_ref)
	if obj != null and obj.is_valid():
		return obj.node
	var by_path: Node = ctx.get_node_or_null(NodePath(parent_ref))
	if by_path != null:
		return by_path
	var rel_root := _resolve_app_root()
	if rel_root != null:
		var rel: Node = rel_root.get_node_or_null(NodePath(parent_ref))
		if rel != null:
			return rel
	return ctx.objects_root


func _all_nodes_in_scene() -> Array:
	var out: Array = []
	var scene = ctx.get_tree().current_scene
	if scene != null:
		_collect(scene, out)
	return out


func _collect(node: Node, out: Array) -> void:
	out.append(node)
	for c in node.get_children():
		_collect(c, out)
