extends RefCounted
## Collision reactors: bouncers (mirror-reflect + impulse) and portals (random teleport).
## Config is keyed by object id; behavior fires from MSPhysicsAdapter._on_area_enter via on_contact().

var ctx = null

# id -> { "strength": float, "gain": float, "min_speed": float }
var _bouncers: Dictionary = {}
# id -> Array[String] of target ids
var _portals: Dictionary = {}
# body instance id -> { "portal": <destination id>, "until": <expiry ms> }. Destination-scoped
# anti-ping-pong: a just-arrived body is still inside its destination Area, so it's skipped ONLY at
# that portal until it leaves/the window lapses — other portals stay live, so multi-portal scenes
# (e.g. a pinball with several pairs) don't suppress legitimate teleports.
var _recent: Dictionary = {}

const PORTAL_COOLDOWN_MS := 250
const PORTAL_NUDGE := 0.02   # small cosmetic center-offset along travel dir; does NOT clear the
                             # destination collider — the cooldown (above) is what prevents re-trigger

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
				ctx.error("bad_arguments", "/ms/scene/" + obj.osc_id + "/portal", "link needs at least one target id")
				return
			var ids: Array = []
			for j in range(1, args.size()):
				ids.append(str(args[j]))
			_portals[obj.osc_id] = ids
		"unlink":
			_portals.erase(obj.osc_id)
		_:
			ctx.error("bad_arguments", "/ms/scene/" + obj.osc_id + "/portal", "Expected link|unlink")

func on_contact(obj, other: Node) -> void:
	if not ctx.spatial.is_dynamic(other):
		return
	match obj.type_hint:
		"bouncer": _bounce(obj, other)
		"portal": _teleport(obj, other)

func _bounce(obj, other: Node) -> void:
	var cfg: Dictionary = _bouncers.get(obj.osc_id, {"strength": 0.0, "gain": 1.0, "min_speed": 0.0})
	var gain: float = cfg.get("gain", 1.0)             # dimensionless — no conversion
	var min_speed: float = maxf(0.0, cfg.get("min_speed", 0.0))   # clamp >= 0 so the outward guarantee can't be disabled
	# strength/minSpeed are user-facing normalized magnitudes (like radii/velocity); convert to
	# world units so they scale consistently across 2D (pixels) and 3D (world units).
	var mode: String = ctx.mapper.physics_mode
	var strength_w: float = ctx.spatial.length_to_world(cfg.get("strength", 0.0), mode)
	var min_speed_w: float = ctx.spatial.length_to_world(min_speed, mode)
	var v = ctx.spatial.body_get_velocity(other)
	var n = ctx.spatial.reactor_normal(obj.node, other)
	var v_ref = v - 2.0 * v.dot(n) * n            # mirror reflection (world space is isotropic)
	var v_out = v_ref * gain + n * strength_w      # + outward impulse kick
	var outward: float = v_out.dot(n)
	if outward < min_speed_w:                        # guarantee it leaves the bouncer
		v_out += n * (min_speed_w - outward)
	ctx.spatial.body_set_velocity_world(other, v_out)

func _teleport(obj, other: Node) -> void:
	var now: int = Time.get_ticks_msec()
	var bid: int = other.get_instance_id()
	# Prune expired immunities so _recent stays bounded to bodies currently within a window.
	for k in _recent.keys():
		if now >= _recent[k]["until"]:
			_recent.erase(k)
	# Skip ONLY re-entry to the portal this body just arrived at — that alone stops ping-pong (the
	# just-teleported body is still inside its destination Area). Other portals are unaffected, so a
	# fast body crossing several portals in quick succession still teleports at each one.
	if _recent.has(bid) and _recent[bid]["portal"] == obj.osc_id:
		return
	var targets: Array = _portals.get(obj.osc_id, [])
	var live: Array = []
	for tid in targets:
		var t = ctx.registry.get_object(tid)
		if t != null and t.node != null:
			live.append(t)
	if live.is_empty():
		return
	var dst = live[randi() % live.size()]
	var mode: String = ctx.mapper.physics_mode
	var dst_norm = ctx.spatial.point_to_norm(ctx.spatial.body_global_position(dst.node), mode)
	var v = ctx.spatial.body_get_velocity(other)
	var vnorm = ctx.spatial.vector_to_norm(v, mode)
	var vdir = vnorm.normalized() if vnorm.length() > 0.0 else Vector3.ZERO
	var target = dst_norm + vdir * PORTAL_NUDGE
	ctx.spatial.set_position(other, target.x, target.y, target.z, mode)   # velocity untouched -> preserved
	_recent[bid] = {"portal": dst.osc_id, "until": now + PORTAL_COOLDOWN_MS}
