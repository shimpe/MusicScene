extends RefCounted
## Collision reactors: bouncers (mirror-reflect + impulse) and portals (random teleport).
## Config is keyed by object id; behavior fires from GScorePhysicsAdapter._on_area_enter via on_contact().

var ctx = null

# id -> { "strength": float, "gain": float, "min_speed": float }
var _bouncers: Dictionary = {}
# id -> Array[String] of target ids
var _portals: Dictionary = {}
# body instance id -> cooldown expiry (ms) after a teleport, to stop ping-pong
var _recent: Dictionary = {}

const PORTAL_COOLDOWN_MS := 250
const PORTAL_NUDGE := 0.02   # normalized-space exit offset along travel direction

func _init(context) -> void:
	ctx = context

func configure_bouncer(obj, args: Array) -> void:
	var cfg: Dictionary = _bouncers.get(obj.osc_id, {"strength": 0.0, "gain": 1.0, "min_speed": 0.0})
	var i := 0
	while i + 1 < args.size():
		match str(args[i]).to_lower():
			"strength": cfg["strength"] = float(args[i + 1])
			"gain": cfg["gain"] = float(args[i + 1])
			"minspeed": cfg["min_speed"] = float(args[i + 1])
		i += 2
	_bouncers[obj.osc_id] = cfg

func configure_portal(obj, args: Array) -> void:
	var cmd := str(args[0]).to_lower() if args.size() > 0 else ""
	match cmd:
		"link":
			if args.size() < 2:
				ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/portal", "link needs at least one target id")
				return
			var ids: Array = []
			for j in range(1, args.size()):
				ids.append(str(args[j]))
			_portals[obj.osc_id] = ids
		"unlink":
			_portals.erase(obj.osc_id)
		_:
			ctx.error("bad_arguments", "/gscore/scene/" + obj.osc_id + "/portal", "Expected link|unlink")

func on_contact(obj, other: Node) -> void:
	if not ctx.spatial.is_dynamic(other):
		return
	match obj.type_hint:
		"bouncer": _bounce(obj, other)
		"portal": _teleport(obj, other)

func _bounce(_obj, _other: Node) -> void:
	pass   # implemented in Task 3

func _teleport(_obj, _other: Node) -> void:
	pass   # implemented in Task 4
