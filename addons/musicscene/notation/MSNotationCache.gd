extends RefCounted
## Disk cache for rendered notation pages under user://musicscene_cache/notation/.
## Pages are keyed by a stable hash of (source, format, page, backend, options) so re-rendering
## the same input is a no-op. Used mainly by backends that shell out to external engravers.

const DIR := "user://musicscene_cache/notation/"


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


static func key(source: String, format: String, page: int, backend: String, options: Dictionary = {}) -> String:
	var raw := "%s|%s|%d|%s|%s" % [source, format, page, backend, JSON.stringify(options)]
	return raw.sha256_text()


static func path_for(cache_key: String, ext: String) -> String:
	return DIR + cache_key + "." + ext


static func has(path: String) -> bool:
	return FileAccess.file_exists(path)


static func clear() -> int:
	var removed := 0
	var d := DirAccess.open(DIR)
	if d == null:
		return 0
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir():
			if d.remove(f) == OK:
				removed += 1
		f = d.get_next()
	d.list_dir_end()
	return removed


static func info() -> Dictionary:
	var count := 0
	var bytes := 0
	var d := DirAccess.open(DIR)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if not d.current_is_dir():
				count += 1
				var fa := FileAccess.open(DIR + f, FileAccess.READ)
				if fa != null:
					bytes += fa.get_length()
					fa.close()
			f = d.get_next()
		d.list_dir_end()
	return {"count": count, "bytes": bytes, "dir": DIR}
