extends RefCounted
## Conservative permission gate for everything that touches existing Godot objects.
##
## Defaults: bind only OSC-exposed nodes, instantiate only whitelisted scenes/prefixes,
## call/set only exposed members, never free. Developer mode relaxes all of this for local
## prototyping. Global toggles (bind_existing, instantiate, call_methods, set_props,
## free_nodes) can each hard-disable a capability regardless of exposure.

var developer_mode: bool = false

var bind_existing: bool = true
var instantiate: bool = true
var call_methods: bool = true
var set_props: bool = true
var free_nodes: bool = false

var _allowed_scenes := {}        # path -> true
var _allowed_prefixes: Array[String] = []


func can_bind(is_exposed: bool) -> bool:
	if not bind_existing:
		return false
	return developer_mode or is_exposed


func can_instantiate_path(path: String) -> bool:
	if not instantiate:
		return false
	if developer_mode:
		return true
	if _allowed_scenes.has(path):
		return true
	for prefix in _allowed_prefixes:
		if path.begins_with(prefix):
			return true
	return false


func can_call_method(exposed_methods: Array, method: String) -> bool:
	if not call_methods:
		return false
	return developer_mode or method in exposed_methods


func can_set_property(exposed_properties, prop: String) -> bool:
	if not set_props:
		return false
	if developer_mode:
		return true
	if exposed_properties is Dictionary:
		return exposed_properties.has(prop)
	if exposed_properties is Array:
		return prop in exposed_properties
	return false


func can_free(object_allow_free: bool) -> bool:
	return developer_mode or free_nodes or object_allow_free


# --- Whitelist management ------------------------------------------------

func allow_scene(path: String) -> void:
	_allowed_scenes[path] = true


func allow_prefix(prefix: String) -> void:
	if prefix not in _allowed_prefixes:
		_allowed_prefixes.append(prefix)


func list_allowed() -> Array:
	var out: Array = []
	out.append_array(_allowed_scenes.keys())
	for p in _allowed_prefixes:
		out.append(p + "*")
	return out
