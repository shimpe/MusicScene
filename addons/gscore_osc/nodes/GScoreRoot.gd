extends Node
## Central gscore_osc controller, installed as the `GScoreOSC` autoload. Owns and wires every
## subsystem, parents OSC-created objects, runs the per-frame clocks, and exposes the reply/error
## helpers used across the codebase as `ctx.*`.
##
## The dimension is chosen by gscore_osc/space ("2d" | "3d"): ctx.spatial is a GScoreSpatial2D or
## GScoreSpatial3D, and all dimension-specific work goes through it. Everything else is shared.

const OscServer := preload("res://addons/gscore_osc/core/OscServer.gd")
const OscDispatcher := preload("res://addons/gscore_osc/core/OscDispatcher.gd")
const GScoreRegistry := preload("res://addons/gscore_osc/core/GScoreRegistry.gd")
const GScorePermissions := preload("res://addons/gscore_osc/core/GScorePermissions.gd")
const GScoreCoordinateMapper := preload("res://addons/gscore_osc/core/GScoreCoordinateMapper.gd")
const GScoreSpatial2D := preload("res://addons/gscore_osc/core/GScoreSpatial2D.gd")
const GScoreSpatial3D := preload("res://addons/gscore_osc/core/GScoreSpatial3D.gd")
const GScorePhysicsWorld := preload("res://addons/gscore_osc/physics/GScorePhysicsWorld.gd")
const GScoreJointWorld := preload("res://addons/gscore_osc/physics/GScoreJointWorld.gd")
const GScoreEvents := preload("res://addons/gscore_osc/events/GScoreEvents.gd")
const GScoreNotation := preload("res://addons/gscore_osc/notation/GScoreNotation.gd")
const GScoreRenderQueue := preload("res://addons/gscore_osc/notation/GScoreRenderQueue.gd")
const GScoreTransport := preload("res://addons/gscore_osc/transport/GScoreTransport.gd")
const GScoreTimeMapper := preload("res://addons/gscore_osc/transport/GScoreTimeMapper.gd")
const GScoreScriptRunner := preload("res://addons/gscore_osc/script/GScoreScriptRunner.gd")
const GScoreEmissionScheduler := preload("res://addons/gscore_osc/events/GScoreEmissionScheduler.gd")
const GScoreCamera := preload("res://addons/gscore_osc/core/GScoreCamera.gd")

# Subsystems (accessed as ctx.* throughout the codebase)
var server = null
var dispatcher = null
var registry = null
var permissions = null
var mapper = null
var spatial = null
var physics_world = null
var joints = null
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

	mapper = GScoreCoordinateMapper.new()
	mapper.host = self
	mapper.app_mode = String(_setting("app/coord_mode", "normalized"))
	mapper.physics_mode = String(_setting("physics/coord_mode", "normalized"))

	permissions = GScorePermissions.new()
	permissions.developer_mode = bool(_setting("developer_mode", false))
	permissions.bind_existing = bool(_setting("permissions/bind_existing", true))
	permissions.instantiate = bool(_setting("permissions/instantiate", true))
	permissions.call_methods = bool(_setting("permissions/call_methods", true))
	permissions.set_props = bool(_setting("permissions/set_props", true))
	permissions.free_nodes = bool(_setting("permissions/free_nodes", false))
	permissions.allow_prefix("res://osc_spawnable/")

	spatial = GScoreSpatial3D.new(self) if space == "3d" else GScoreSpatial2D.new(self)

	registry = GScoreRegistry.new(self)
	camera = GScoreCamera.new(self)
	physics_world = GScorePhysicsWorld.new(self)
	joints = GScoreJointWorld.new(self)
	transport = GScoreTransport.new(self)
	timemapper = GScoreTimeMapper.new(self)
	emitter = GScoreEmissionScheduler.new(self)
	notation = GScoreNotation.new(self)
	script_runner = GScoreScriptRunner.new(self)
	dispatcher = OscDispatcher.new(self)

	objects_root = spatial.create_objects_root()
	add_child(objects_root)

	events = GScoreEvents.new()
	events.name = "Events"
	events.setup(self)
	add_child(events)

	render_queue = GScoreRenderQueue.new()
	render_queue.name = "RenderQueue"
	render_queue.setup(self)
	add_child(render_queue)

	server = OscServer.new()
	server.name = "OscServer"
	server.verbose = verbose
	add_child(server)
	server.message_received.connect(_on_message)

	if bool(_setting("network/autostart", true)):
		server.start(
			int(_setting("network/listen_port", 7400)),
			String(_setting("network/send_host", "127.0.0.1")),
			int(_setting("network/send_port", 7401)))

	# Defer until the running scene is in the tree: auto-bind exposed nodes and (3D) add a
	# camera only if the scene didn't provide one.
	await get_tree().process_frame
	await get_tree().process_frame
	spatial.ensure_camera()
	registry.auto_bind_exposed()
	if verbose:
		print("[GScoreOSC] ready (space=%s). Send /gscore/ping to test." % space)


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
		server.send("/gscore/reply", [topic] + values)


func error(code: String, address: String, message: String) -> void:
	if server != null:
		server.send("/gscore/error", [code, address, message])
	if verbose:
		push_warning("[GScoreOSC] error %s @ %s: %s" % [code, address, message])


func send_event(address: String, args: Array) -> void:
	if server != null:
		server.send(address, args)


func _setting(key: String, def):
	return ProjectSettings.get_setting("gscore_osc/" + key, def)
