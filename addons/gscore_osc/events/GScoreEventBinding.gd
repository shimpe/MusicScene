extends RefCounted
## One physics/collision event binding: which event, where to send it, gating options, and the
## payload field list. Shared by collision, area and continuous (velocity/position) events.

const DEFAULT_FIELDS := ["self", "other", "intensity", "x", "y", "vx", "vy", "time"]

var event: String = ""
var target: String = ""
var min_intensity: float = 0.0
var cooldown: float = 0.0
var max_rate: float = 0.0          # Hz; 0 = unlimited
var layer_filter: String = ""
var other_filter: String = ""
var mode: String = "immediate"
var payload: Array = []            # field names; empty -> DEFAULT_FIELDS

var _last_emit: float = -1.0
var state: bool = false            # edge-detection for continuous events


func set_option(key: String, value) -> void:
	match key.to_lower():
		"minintensity": min_intensity = float(value)
		"cooldown": cooldown = float(value)
		"maxrate": max_rate = float(value)
		"layer": layer_filter = str(value)
		"other": other_filter = str(value)
		"mode": mode = str(value)


func should_emit(intensity: float, now: float, other_id: String, layer: String) -> bool:
	if intensity < min_intensity:
		return false
	if other_filter != "" and not _match(other_id):
		return false
	if layer_filter != "" and layer != layer_filter:
		return false
	var gap := 0.0
	if cooldown > 0.0:
		gap = cooldown
	if max_rate > 0.0:
		gap = maxf(gap, 1.0 / max_rate)
	if gap > 0.0 and _last_emit >= 0.0 and (now - _last_emit) < gap:
		return false
	return true


func mark(now: float) -> void:
	_last_emit = now


func build_args(data: Dictionary) -> Array:
	var fields: Array = payload if not payload.is_empty() else DEFAULT_FIELDS
	var out: Array = []
	for f in fields:
		var s := str(f)
		if s.begins_with("'") or s.begins_with("="):
			out.append(s.substr(1))             # literal string (case preserved)
		else:
			var key := s.to_lower()
			out.append(data[key] if data.has(key) else 0)
	return out


func _match(other_id: String) -> bool:
	if other_filter == "*" or other_filter == "":
		return true
	if other_filter.ends_with("*"):
		return other_id.begins_with(other_filter.left(other_filter.length() - 1))
	return other_id == other_filter
