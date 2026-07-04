extends RefCounted
## Buffers non-immediate event emissions and flushes them once per frame.
## - immediate: sent now (bypasses all buffers)
## - queued:    accumulated, flushed as individual messages at end of frame
## - bundle:    the frame's bundle-mode events sent as one OSC bundle
## - quantized: held until the transport beat crosses the next grid line, then sent

const MAX_QUANTIZED := 512

var ctx = null
var _queued: Array = []      # {address, args}
var _bundle: Array = []      # {address, args}
var _quantized: Array = []   # {address, args, fire_beat}; held until the transport beat reaches fire_beat. With a stopped transport these accumulate, so the queue is capped at MAX_QUANTIZED (oldest dropped). Use quantized mode with the transport playing.

func _init(p_ctx) -> void:
	ctx = p_ctx

func emit(address: String, args: Array, mode: String, grid: float) -> void:
	match mode:
		"queued":
			_queued.append({"address": address, "args": args})
		"bundle":
			_bundle.append({"address": address, "args": args})
		"quantized":
			var beat: float = ctx.transport.beat if ctx.transport != null else 0.0
			_quantized.append({"address": address, "args": args, "fire_beat": _next_grid(beat, grid)})
			if _quantized.size() > MAX_QUANTIZED:
				_quantized.pop_front()
		_:
			ctx.send_event(address, args)   # "immediate" and any unknown mode

func flush(now_beat: float) -> void:
	for m in _queued:
		ctx.send_event(m.address, m.args)
	_queued.clear()
	if not _bundle.is_empty():
		if ctx.server != null:
			ctx.server.send_bundle(_bundle)
		_bundle.clear()
	if not _quantized.is_empty():
		var keep: Array = []
		for m in _quantized:
			if now_beat >= m.fire_beat:
				ctx.send_event(m.address, m.args)
			else:
				keep.append(m)
		_quantized = keep

## Drop all buffered (queued/bundle/quantized) emissions — used by /ms/scene reset.
func clear() -> void:
	_queued.clear()
	_bundle.clear()
	_quantized.clear()

## Returns the next grid line strictly after `beat` (an on-grid beat advances to the following
## line). grid<=0 returns beat (fires on the next flush).
func _next_grid(beat: float, grid: float) -> float:
	if grid <= 0.0:
		return beat   # no grid -> fire on next flush
	return (floor(beat / grid) + 1.0) * grid
