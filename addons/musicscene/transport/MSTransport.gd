extends RefCounted
## Simple transport clock: play/stop/pause/seek/tempo, exposing time (seconds) and beat. Drives
## the time mapper each frame. Kept deliberately minimal (no song position, loop, etc. in v1).

var ctx = null
var playing: bool = false
var time: float = 0.0
var tempo: float = 120.0
var beat: float = 0.0


func _init(p_ctx) -> void:
	ctx = p_ctx


func handle(args: Array) -> void:
	var cmd := str(args[0]) if args.size() > 0 else ""
	match cmd:
		"play":
			playing = true
		"stop":
			playing = false
			time = 0.0
			beat = 0.0
		"pause":
			playing = false
		"seek":
			time = _f(args, 1)
			beat = time * tempo / 60.0
		"tempo":
			tempo = _f(args, 1, 120.0)
		"time":
			ctx.reply("transport", ["time", time])
		"beat":
			ctx.reply("transport", ["beat", beat])
		"state":
			ctx.reply("transport", ["state", "playing" if playing else "stopped", time, tempo])
		_:
			ctx.error("bad_arguments", "/ms/transport", "Unknown transport cmd: " + cmd)


func step(delta: float) -> void:
	if playing:
		time += delta
		beat = time * tempo / 60.0


func _f(args: Array, i: int, def: float = 0.0) -> float:
	if i < args.size():
		var x = args[i]
		if x is float or x is int:
			return float(x)
		if x is String and x.is_valid_float():
			return float(x)
	return def
