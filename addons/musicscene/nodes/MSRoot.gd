extends Node
## Central MusicScene controller, installed as the `MusicSceneOSC` autoload. Owns and wires every
## subsystem, parents OSC-created objects, runs the per-frame clocks, and exposes the reply/error
## helpers used across the codebase as `ctx.*`.
##
## The dimension is chosen by ms/space ("2d" | "3d"): ctx.spatial is a MSSpatial2D or
## MSSpatial3D, and all dimension-specific work goes through it. Everything else is shared.

const OscServer := preload("res://addons/musicscene/core/OscServer.gd")
const OscDispatcher := preload("res://addons/musicscene/core/OscDispatcher.gd")
const MSRegistry := preload("res://addons/musicscene/core/MSRegistry.gd")
const MSPermissions := preload("res://addons/musicscene/core/MSPermissions.gd")
const MSCoordinateMapper := preload("res://addons/musicscene/core/MSCoordinateMapper.gd")
const MSSpatial2D := preload("res://addons/musicscene/core/MSSpatial2D.gd")
const MSSpatial3D := preload("res://addons/musicscene/core/MSSpatial3D.gd")
const MSPhysicsWorld := preload("res://addons/musicscene/physics/MSPhysicsWorld.gd")
const MSJointWorld := preload("res://addons/musicscene/physics/MSJointWorld.gd")
const MSReactors := preload("res://addons/musicscene/physics/MSReactors.gd")
const MSEvents := preload("res://addons/musicscene/events/MSEvents.gd")
const MSNotation := preload("res://addons/musicscene/notation/MSNotation.gd")
const MSRenderQueue := preload("res://addons/musicscene/notation/MSRenderQueue.gd")
const MSTransport := preload("res://addons/musicscene/transport/MSTransport.gd")
const MSTimeMapper := preload("res://addons/musicscene/transport/MSTimeMapper.gd")
const MSScriptRunner := preload("res://addons/musicscene/script/MSScriptRunner.gd")
const MSEmissionScheduler := preload("res://addons/musicscene/events/MSEmissionScheduler.gd")
const MSCamera := preload("res://addons/musicscene/core/MSCamera.gd")

# Subsystems (accessed as ctx.* throughout the codebase)
var server = null
var dispatcher = null
var registry = null
var permissions = null
var mapper = null
var spatial = null
var physics_world = null
var joints = null
var reactors = null
var events = null
var notation = null
var render_queue = null
var transport = null
var timemapper = null
var script_runner = null
var emitter = null
var camera = null
var objects_root: Node = null

var space: String = "2d"
var verbose: bool = true


func _ready() -> void:
	verbose = bool(_setting("logging/verbose", true))
	space = String(_setting("space", "2d")).to_lower()

	mapper = MSCoordinateMapper.new()
	mapper.host = self
	mapper.app_mode = String(_setting("app/coord_mode", "normalized"))
	mapper.physics_mode = String(_setting("physics/coord_mode", "normalized"))

	permissions = MSPermissions.new()
	permissions.developer_mode = bool(_setting("developer_mode", false))
	permissions.bind_existing = bool(_setting("permissions/bind_existing", true))
	permissions.instantiate = bool(_setting("permissions/instantiate", true))
	permissions.call_methods = bool(_setting("permissions/call_methods", true))
	permissions.set_props = bool(_setting("permissions/set_props", true))
	permissions.free_nodes = bool(_setting("permissions/free_nodes", false))
	permissions.allow_prefix("res://osc_spawnable/")

	spatial = MSSpatial3D.new(self) if space == "3d" else MSSpatial2D.new(self)

	registry = MSRegistry.new(self)
	camera = MSCamera.new(self)
	physics_world = MSPhysicsWorld.new(self)
	joints = MSJointWorld.new(self)
	reactors = MSReactors.new(self)
	transport = MSTransport.new(self)
	timemapper = MSTimeMapper.new(self)
	emitter = MSEmissionScheduler.new(self)
	notation = MSNotation.new(self)
	script_runner = MSScriptRunner.new(self)
	dispatcher = OscDispatcher.new(self)

	objects_root = spatial.create_objects_root()
	add_child(objects_root)

	events = MSEvents.new()
	events.name = "Events"
	events.setup(self)
	add_child(events)

	render_queue = MSRenderQueue.new()
	render_queue.name = "RenderQueue"
	render_queue.setup(self)
	add_child(render_queue)

	server = OscServer.new()
	server.name = "OscServer"
	server.verbose = verbose
	add_child(server)
	server.message_received.connect(_on_message)

	if bool(_setting("network/autostart", true)):
		var send_ports := OscServer.startup_ports(
			String(_setting("network/send_ports", "")),
			int(_setting("network/send_port", 7401)))
		server.start(
			int(_setting("network/listen_port", 7400)),
			String(_setting("network/send_host", "127.0.0.1")),
			send_ports)

	# Defer until the running scene is in the tree: auto-bind exposed nodes and (3D) add a
	# camera only if the scene didn't provide one.
	await get_tree().process_frame
	await get_tree().process_frame
	spatial.ensure_camera()
	spatial.ensure_lighting()
	registry.auto_bind_exposed()
	if verbose:
		print("[MusicSceneOSC] ready (space=%s). Send /ms/ping to test." % space)


func _exit_tree() -> void:
	if registry != null:
		registry.clear()
	if timemapper != null:
		timemapper.clear()
	if server != null:
		server.stop()


func _process(delta: float) -> void:
	if transport != null:
		transport.step(delta)
	if timemapper != null:
		timemapper.update(transport.time)
	if emitter != null and transport != null:
		emitter.flush(transport.beat)
	if camera != null:
		camera.step(delta)


func _physics_process(delta: float) -> void:
	if physics_world != null:
		physics_world.physics_step(delta)
	if joints != null:
		joints.physics_step(delta)


func _on_message(address: String, args: Array, _ip: String, _port: int) -> void:
	dispatcher.dispatch(address, args)


# --- ctx helpers ---------------------------------------------------------

func reply(topic: String, values: Array) -> void:
	if server != null:
		server.send("/ms/reply", [topic] + values)


func error(code: String, address: String, message: String) -> void:
	if server != null:
		server.send("/ms/error", [code, address, message])
	if verbose:
		push_warning("[MusicSceneOSC] error %s @ %s: %s" % [code, address, message])


func send_event(address: String, args: Array) -> void:
	if server != null:
		server.send(address, args)


func _setting(key: String, def):
	return ProjectSettings.get_setting("ms/" + key, def)
