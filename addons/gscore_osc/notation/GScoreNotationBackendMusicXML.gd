extends RefCounted
## Symbolic-format backend (MusicXML / MEI / GUIDO / ABC / LilyPond / PDF). Delegates engraving to
## an external command and displays the resulting page. The score may be a file PATH or inline
## TEXT/BYTES sent over OSC (written to a temp input file). Output is cached under
## user://gscore_cache/notation/, so the engraver runs once per (source, format, page).
##
## Configure a per-format command (preferred) or a generic fallback in Project Settings:
##   gscore_osc/notation/engraver/musicxml   e.g. "\"C:/Program Files/MuseScore 4/bin/MuseScore4.exe\" {input} -o {output}"
##   gscore_osc/notation/engraver/lilypond   e.g. "python tools/ly_to_png.py {input} {output}"
##   gscore_osc/notation/engraver/abc        e.g. "python tools/abc_to_png.py {input} {output}"
##   gscore_osc/notation/engraver/mei        ...
##   gscore_osc/notation/external_renderer_path + external_renderer_args   (generic fallback)
##   gscore_osc/notation/engraver_output      "png" (default) | "svg"   (what the command writes)
## Tokens: {input} {output} {outbase} {outdir} {format} {page}

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")
const Cache := preload("res://addons/gscore_osc/notation/GScoreNotationCache.gd")
const ImageBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendImage.gd")
const SvgBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendSvg.gd")

const BACKEND := "external"


static func render(content: Dictionary, format: String, page: int, options: Dictionary = {}):
	var cmd_tmpl := _command_for(format)
	if cmd_tmpl == "":
		return Result.make_error(BACKEND,
			"No engraver configured for '%s'. Set gscore_osc/notation/engraver/%s (or pre-render to PNG/SVG)."
			% [format, format])

	Cache.ensure_dir()
	var cid := _content_id(content)

	# Resolve the input file (write inline content to a temp file in the cache).
	var input_abs := ""
	if content.kind == "path":
		input_abs = _globalize(content.path)
	else:
		var in_user := Cache.path_for(Cache.key(cid, format, 0, "in", options), _ext_for(format))
		if not _write_content(in_user, content):
			return Result.make_error(BACKEND, "Could not write temp engraver input: " + in_user)
		input_abs = ProjectSettings.globalize_path(in_user)

	var out_ext := str(_setting("notation/engraver_output", "png"))
	var out_user := Cache.path_for(Cache.key(cid, format, page, BACKEND, options), out_ext)
	var out_abs := ProjectSettings.globalize_path(out_user)

	if not Cache.has(out_user):
		var argv := _build_argv(cmd_tmpl, input_abs, out_abs, format, page)
		if argv.is_empty():
			return Result.make_error(BACKEND, "Empty engraver command for: " + format)
		var exe: String = argv[0]
		var args := argv.slice(1)
		var out_lines: Array = []
		var code := OS.execute(exe, args, out_lines, true)
		if code != 0:
			return Result.make_error(BACKEND,
				"Engraver exit %d (%s): %s" % [code, exe, "\n".join(out_lines).left(240)])
		if not Cache.has(out_user):
			return Result.make_error(BACKEND, "Engraver produced no output page: " + out_user)

	# Display the produced page.
	var page_content := {"kind": "path", "path": out_user, "text": "", "bytes": PackedByteArray()}
	if out_ext == "svg":
		return SvgBackend.render(page_content, 1, options)
	return ImageBackend.render(page_content, 1, options)


# --- command resolution --------------------------------------------------

static func _command_for(format: String) -> String:
	var c := str(_setting("notation/engraver/" + format, ""))
	if c != "":
		return c
	var exe := str(_setting("notation/external_renderer_path", ""))
	if exe != "":
		var a := str(_setting("notation/external_renderer_args", "{input} -o {output}"))
		return "\"%s\" %s" % [exe, a]
	return ""


static func _build_argv(template: String, input: String, output: String, format: String, page: int) -> PackedStringArray:
	var outbase := output.get_basename()
	var outdir := output.get_base_dir()
	var argv := PackedStringArray()
	for tok in _tokenize(template):
		var s := String(tok)
		s = s.replace("{input}", input) \
			.replace("{output}", output) \
			.replace("{outbase}", outbase) \
			.replace("{outdir}", outdir) \
			.replace("{format}", format) \
			.replace("{page}", str(page))
		if s != "":
			argv.append(s)
	return argv


## Quote-aware split (double quotes group spaces) so engraver paths with spaces work.
static func _tokenize(s: String) -> Array:
	var out: Array = []
	var i := 0
	var n := s.length()
	while i < n:
		while i < n and s[i] == " ":
			i += 1
		if i >= n:
			break
		if s[i] == "\"":
			i += 1
			var start := i
			while i < n and s[i] != "\"":
				i += 1
			out.append(s.substr(start, i - start))
			i += 1
		else:
			var start := i
			while i < n and s[i] != " ":
				i += 1
			out.append(s.substr(start, i - start))
	return out


# --- helpers -------------------------------------------------------------

static func _content_id(content: Dictionary) -> String:
	match content.kind:
		"path": return content.path
		"text": return "text:" + content.text.sha256_text()
		"bytes": return "bytes:%d:%d" % [content.bytes.size(), content.bytes.hash()]
	return "?"


static func _write_content(user_path: String, content: Dictionary) -> bool:
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	if f == null:
		return false
	if content.kind == "bytes":
		f.store_buffer(content.bytes)
	else:
		f.store_string(content.text)
	f.close()
	return true


static func _ext_for(format: String) -> String:
	match format:
		"musicxml": return "musicxml"
		"mei": return "mei"
		"lilypond", "ly": return "ly"
		"abc": return "abc"
		"guido": return "gmn"
		"pdf": return "pdf"
	return "txt"


static func _globalize(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _setting(key: String, def):
	return ProjectSettings.get_setting("gscore_osc/" + key, def)
