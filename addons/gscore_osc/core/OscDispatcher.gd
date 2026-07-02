extends RefCounted
## Routes decoded OSC messages to subsystem handlers. Deliberately split into small per-area
## methods rather than one monolithic match, so each area stays readable and testable.
##
## Two command styles coexist (matching the spec):
##   /gscore/scene/<id> <verb> ...            verb arrives as the first OSC argument
##   /gscore/scene/<id>/<subsystem> ...       subsystem is part of the address

const NOTATION_VERBS := [
	"notation", "notationsource", "notationdata", "notationformat", "render", "reload",
	"page", "nextpage", "prevpage", "pages", "system", "staff", "measure",
	"part", "notationinfo", "currentpage", "addressable", "measures", "elements",
]

var ctx = null


func _init(p_ctx) -> void:
	ctx = p_ctx


func dispatch(address: String, args: Array) -> void:
	var parts := _segments(address)
	if parts.is_empty() or parts[0] != "gscore":
		return  # not ours; ignore silently
	var head := parts[1] if parts.size() > 1 else ""

	match head:
		"":
			_handle_root(args)
		"ping":
			ctx.server.send("/gscore/pong", [])
		"version":
			ctx.reply("version", ["0.8.0"])
		"info":
			_handle_info()
		"app":
			_handle_app(parts.slice(2), args)
		"camera":
			ctx.camera.handle(parts.slice(2), args)
		"physics":
			if parts.size() > 2 and parts[2] == "layer":
				ctx.physics_world.handle_layer(args)
			else:
				ctx.physics_world.handle_global(args)
		"joint", "joints":
			# head=="joint"  => /gscore/joint/<id> <verb> ...
			# head=="joints" => /gscore/joints <query>
			if head == "joints":
				ctx.joints.handle_global(parts.slice(2), args)
			else:
				var jid := str(parts[2]) if parts.size() > 2 else ""
				ctx.joints.handle(jid, args)
		"bind":
			ctx.registry.bind(_s(args, 0), _s(args, 1))
		"bindrel", "bindRel":
			ctx.registry.bind_rel(_s(args, 0), _s(args, 1))
		"bindgroup", "bindGroup":
			ctx.reply("bindGroup", ctx.registry.bind_group(_s(args, 0), _s(args, 1)))
		"bindall", "bindAll":
			_handle_bind_all(args)
		"discover":
			_handle_discover(parts.slice(2), args)
		"assets":
			_handle_assets(parts.slice(2), args)
		"notation":
			_handle_notation_global(parts.slice(2), args)
		"transport":
			ctx.transport.handle(args)
		"script":
			_handle_script(parts.slice(2), args)
		"scene":
			_handle_scene(parts.slice(2), args)
		"reply", "error", "event", "pong":
			pass  # outgoing namespaces; ignore if echoed back
		_:
			ctx.error("bad_arguments", address, "Unknown namespace: /gscore/" + head)


# --- Root / info ---------------------------------------------------------

func _handle_root(args: Array) -> void:
	match _s(args, 0):
		"ping": ctx.server.send("/gscore/pong", [])
		"version": ctx.reply("version", ["0.8.0"])
		"info": _handle_info()
		_: ctx.error("bad_arguments", "/gscore", "Expected ping|version|info")


func _handle_info() -> void:
	ctx.reply("info", [
		"gscore_osc", "0.8.0",
		"listen", ctx.server.get_listen_port(),
		"coord", ctx.mapper.app_mode,
		"objects", ctx.registry.list_ids().size(),
	])


# --- App -----------------------------------------------------------------

func _handle_app(rest, args: Array) -> void:
	var key := str(rest[0]) if rest.size() > 0 else ""
	match key:
		"coord":
			var mode := _s(args, 0)
			if ctx.mapper.is_valid_mode(mode):
				ctx.mapper.app_mode = mode
			else:
				ctx.error("bad_arguments", "/gscore/app/coord", "Bad coord mode: " + mode)
		"root":
			ctx.registry.app_root_path = NodePath(_s(args, 0))
		"permissions":
			_handle_permissions(args)
		"output":
			ctx.server.set_output(_s(args, 0), int(_f(args, 1, 7401)))
		"developer", "developer_mode":
			ctx.permissions.developer_mode = _b(args, 0)
		_:
			ctx.error("bad_arguments", "/gscore/app", "Unknown app key: " + key)


func _handle_permissions(args: Array) -> void:
	var key := _s(args, 0)
	var val := _b(args, 1)
	match key:
		"bindExisting", "bindexisting": ctx.permissions.bind_existing = val
		"instantiate": ctx.permissions.instantiate = val
		"callMethods", "callmethods": ctx.permissions.call_methods = val
		"setProps", "setprops": ctx.permissions.set_props = val
		"freeNodes", "freenodes": ctx.permissions.free_nodes = val
		_: ctx.error("bad_arguments", "/gscore/app/permissions", "Unknown flag: " + key)


# --- Discover / assets / bindAll -----------------------------------------

func _handle_discover(rest, args: Array) -> void:
	var results: Array
	if rest.is_empty():
		results = ctx.registry.discover_all()
	else:
		match rest[0]:
			"group": results = ctx.registry.discover_group(_s(args, 0))
			"type": results = ctx.registry.discover_type(_s(args, 0))
			"meta": results = ctx.registry.discover_meta(_s(args, 0), args[1] if args.size() > 1 else null)
			_: results = ctx.registry.discover_all()
	for d in results:
		ctx.reply("discover", [d.suggested_id, d.path, d["class"], d.name])


func _handle_bind_all(args: Array) -> void:
	if _s(args, 0) == "meta":
		var matches = ctx.registry.discover_meta(_s(args, 1), args[2] if args.size() > 2 else null)
		for d in matches:
			ctx.registry.bind(d.suggested_id, d.path)


func _handle_assets(rest, args: Array) -> void:
	var key := str(rest[0]) if rest.size() > 0 else ""
	match key:
		"allowScene", "allowscene": ctx.permissions.allow_scene(_s(args, 0))
		"allowPrefix", "allowprefix": ctx.permissions.allow_prefix(_s(args, 0))
		"listAllowed", "listallowed": ctx.reply("assets", ctx.permissions.list_allowed())
		_: ctx.error("bad_arguments", "/gscore/assets", "Unknown assets key: " + key)


func _handle_notation_global(rest, args: Array) -> void:
	# /gscore/notation/cache clear | info
	if rest.size() > 0 and rest[0] == "cache":
		ctx.notation.handle_cache(args)
	else:
		ctx.error("bad_arguments", "/gscore/notation", "Expected cache")


func _handle_script(rest, args: Array) -> void:
	var key := str(rest[0]) if rest.size() > 0 else ""
	match key:
		"run": ctx.script_runner.run_text(_s(args, 0))
		"load": ctx.script_runner.run_file(_s(args, 0))
		_: ctx.error("bad_arguments", "/gscore/script", "Expected run|load")


# --- Scene ---------------------------------------------------------------

func _handle_scene(rest, args: Array) -> void:
	if rest.is_empty():
		# /gscore/scene <verb>  (e.g. clear)
		match _s(args, 0):
			"clear":
				# Clear every scene-bound id-space: objects, joints, and time-maps. (Global config —
				# layer names, gravity, transport, permissions, coord modes — is intentionally kept.)
				ctx.registry.clear()
				ctx.joints.clear()
				ctx.timemapper.clear()
			"reset":
				# Full "like first run" reset: scene contents + runtime sim/view state. Keeps safety
				# config (permissions, whitelist, developer_mode) and the transport.
				ctx.registry.clear()
				ctx.joints.clear()
				ctx.timemapper.clear()
				ctx.emitter.clear()
				ctx.physics_world.reset()
				ctx.camera.reset()
				ctx.mapper.app_mode = str(ctx._setting("app/coord_mode", "normalized"))
				ctx.mapper.physics_mode = str(ctx._setting("physics/coord_mode", "normalized"))
			"list": ctx.reply("scene/list", ctx.registry.list_ids())
			"tree": _reply_tree()
			_: ctx.error("bad_arguments", "/gscore/scene", "Expected clear|reset|list|tree")
		return

	match rest[0]:
		"list":
			ctx.reply("scene/list", ctx.registry.list_ids())
			return
		"tree":
			_reply_tree()
			return

	var id := str(rest[0])
	var sub := str(rest[1]) if rest.size() > 1 else ""

	if sub == "":
		_handle_scene_object(id, args)
	else:
		_handle_scene_subsystem(id, sub, args)


func _handle_scene_object(id: String, args: Array) -> void:
	var verb := _s(args, 0).to_lower()
	var rest_args := args.slice(1)

	# Creation / binding verbs and `exists` work even when the object isn't registered yet.
	match verb:
		"new":
			ctx.registry.create_builtin(id, _s(rest_args, 0), rest_args.slice(1))
			return
		"instantiate":
			ctx.registry.instantiate(id, _s(rest_args, 0), _s(rest_args, 1))
			return
		"bind":
			ctx.registry.bind(id, _s(rest_args, 0))
			return
		"bindrel":
			ctx.registry.bind_rel(id, _s(rest_args, 0))
			return
		"exists":
			ctx.reply("exists", [id, ctx.registry.has(id)])
			return

	var obj = ctx.registry.get_object(id)
	if obj == null:
		ctx.error("unknown_object", "/gscore/scene/" + id, "Unknown object: " + id)
		return

	if verb == "map":
		ctx.timemapper.add_map(obj, rest_args)
	elif verb in NOTATION_VERBS:
		ctx.notation.handle_command(obj, verb, rest_args)
	else:
		obj.apply_command(verb, rest_args)


func _handle_scene_subsystem(id: String, sub: String, args: Array) -> void:
	var obj = ctx.registry.get_object(id)
	if obj == null:
		ctx.error("unknown_object", "/gscore/scene/" + id + "/" + sub, "Unknown object: " + id)
		return
	match sub:
		"physics": ctx.physics_world.handle_object(obj, args)
		"collider": ctx.physics_world.handle_collider(obj, args)
		"on": ctx.events.handle_on(obj, args)
		"off": ctx.events.handle_off(obj, args)
		"payload": ctx.events.handle_payload(obj, args)
		"signal": ctx.events.handle_signal(obj, args)
		"cursor": ctx.notation.handle_cursor(obj, args)
		"region": ctx.notation.handle_region(obj, args)
		"annotation": ctx.notation.handle_annotation(obj, args)
		"regions": ctx.notation.reply_regions(obj)
		"annotations": ctx.notation.reply_annotations(obj)
		"notationInfo", "notationinfo": ctx.notation.reply_info(obj)
		"pages": ctx.notation.reply_pages(obj)
		"currentPage", "currentpage": ctx.notation.reply_current_page(obj)
		_:
			ctx.error("bad_arguments", "/gscore/scene/" + id + "/" + sub,
				"Unknown subsystem: " + sub)


func _reply_tree() -> void:
	var values: Array = []
	for id in ctx.registry.list_ids():
		var obj = ctx.registry.get_object(id)
		var path := str(obj.node.get_path()) if obj.node.is_inside_tree() else str(obj.node.name)
		values.append(id)
		values.append(obj.type_hint)
		values.append(obj.ownership)
		values.append(path)
	ctx.reply("scene/tree", values)


# --- Argument helpers ----------------------------------------------------

func _segments(address: String) -> PackedStringArray:
	var out := PackedStringArray()
	for s in address.split("/"):
		if s != "":
			out.append(s)
	return out


func _s(args: Array, i: int, def: String = "") -> String:
	return str(args[i]) if i < args.size() else def


func _f(args: Array, i: int, def: float = 0.0) -> float:
	if i < args.size():
		var a = args[i]
		if a is float or a is int:
			return float(a)
		if a is String and a.is_valid_float():
			return float(a)
	return def


func _b(args: Array, i: int, def: bool = false) -> bool:
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
