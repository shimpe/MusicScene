extends RefCounted
## Symbolic-format backend (MusicXML / MEI / GUIDO / ABC / LilyPond / PDF). Delegates engraving to
## an external command and displays the resulting page. The score may be a file PATH or inline
## TEXT/BYTES sent over OSC (written to a temp input file). Output is cached under
## user://musicscene_cache/notation/, so the engraver runs once per (source, format, page).
##
## Configure a per-format command (preferred) or a generic fallback in Project Settings:
##   musicscene/notation/engraver/musicxml   e.g. "\"C:/Program Files/MuseScore 4/bin/MuseScore4.exe\" {input} -o {output}"
##   musicscene/notation/engraver/lilypond   e.g. "\"C:/.../lilypond.exe\" --png -dcrop=#t -o {outbase} {input}"
##   musicscene/notation/engraver/abc        (defaults to the bundled Verovio wrapper — see below)
##   musicscene/notation/engraver/mei        (defaults to the bundled Verovio wrapper — see below)
##   musicscene/notation/external_renderer_path + external_renderer_args   (generic fallback)
##   musicscene/notation/engraver_output      "png" (default) | "svg"   (what the command writes)
## Tokens: {input} {output} {outbase} {outdir} {format} {page}
##
## Zero-config Verovio: MEI and ABC fall back to the bundled wrapper
## res://addons/musicscene/tools/verovio_render.py (launched via `py` on Windows, `python3`
## elsewhere), so they work after `pip install verovio` with no settings. Override the setting to
## point at a specific interpreter (e.g. a venv's python.exe) if Verovio lives in a virtualenv.

const Result := preload("res://addons/musicscene/notation/MSNotationRenderResult.gd")
const Cache := preload("res://addons/musicscene/notation/MSNotationCache.gd")
const ImageBackend := preload("res://addons/musicscene/notation/MSNotationBackendImage.gd")
const SvgBackend := preload("res://addons/musicscene/notation/MSNotationBackendSvg.gd")

const BACKEND := "external"


## Synchronous render (blocks until the engraver finishes). Used by the sync Renderer path.
static func render(content: Dictionary, format: String, page: int, options: Dictionary = {}):
	var prep := prepare(content, format, page, options)
	if not prep.ok:
		return Result.make_error(BACKEND, prep.error)
	if not prep.cached:
		var out_lines: Array = []
		var code := OS.execute(prep.exe, prep.args, out_lines, true)
		if code != 0:
			return Result.make_error(BACKEND,
				"Engraver exit %d (%s): %s" % [code, prep.exe, "\n".join(out_lines).left(240)])
	return finalize(prep.out_user, prep.out_ext, page, options)


## Prepare an engraver job WITHOUT running it (writes any inline input, builds the command).
## Returns {ok, error?, cached, out_user, out_ext, exe, args}. The caller runs exe/args (sync via
## OS.execute, or async via OS.create_process) then calls finalize().
static func prepare(content: Dictionary, format: String, page: int, options: Dictionary = {}) -> Dictionary:
	var cmd_tmpl := _command_for(format)
	if cmd_tmpl == "":
		return {"ok": false, "error":
			"No engraver configured for '%s'. Set musicscene/notation/engraver/%s (or pre-render to PNG/SVG)."
			% [format, format]}

	Cache.ensure_dir()
	var cid := _content_id(content)

	var input_abs := ""
	if content.kind == "path":
		input_abs = _globalize(content.path)
	else:
		var in_user := Cache.path_for(Cache.key(cid, format, 0, "in", options), _ext_for(format))
		if not _write_content(in_user, content):
			return {"ok": false, "error": "Could not write temp engraver input: " + in_user}
		input_abs = ProjectSettings.globalize_path(in_user)

	# Output format may be per-engraver (MuseScore -> png, Verovio -> svg).
	var out_ext := str(_setting("notation/engraver_output/" + format, _default_output_ext(cmd_tmpl)))
	# Fold the engraver command into the OUTPUT cache key (not the input) so a command change
	# (e.g. adding --text-to-path) invalidates stale renders instead of reusing the old output.
	var out_opts := options.duplicate()
	out_opts["engraver_cmd"] = cmd_tmpl
	var out_user := Cache.path_for(Cache.key(cid, format, page, BACKEND, out_opts), out_ext)
	if Cache.has(out_user):
		return {"ok": true, "cached": true, "out_user": out_user, "out_ext": out_ext}

	var out_abs := ProjectSettings.globalize_path(out_user)
	var argv := _build_argv(cmd_tmpl, input_abs, out_abs, format, page)
	if argv.is_empty():
		return {"ok": false, "error": "Empty engraver command for: " + format}
	return {
		"ok": true, "cached": false, "out_user": out_user, "out_ext": out_ext,
		"exe": argv[0], "args": argv.slice(1),
	}


## After the engraver has run, locate its output, normalise it to out_user, and load the page.
static func finalize(out_user: String, out_ext: String, page: int, options: Dictionary = {}):
	var produced := _resolve_output(out_user, out_ext, page)
	if produced == "":
		return Result.make_error(BACKEND,
			"Engraver ran but produced no recognizable %s page (looked for %s and .cropped / -page%d / -%d / -1 variants)."
			% [out_ext, out_user, page, page])
	if produced != out_user:
		_copy_file(produced, out_user)
	var page_content := {"kind": "path", "path": out_user, "text": "", "bytes": PackedByteArray()}
	if out_ext == "svg":
		return SvgBackend.render(page_content, 1, options)
	return ImageBackend.render(page_content, 1, options)


# --- helpers for the addressable pipeline (reuses command/input plumbing) ---

## The engraver executable for a format (first token of the configured command).
static func engraver_exe(format: String) -> String:
	var cmd := _command_for(format)
	if cmd == "":
		return ""
	var argv := _tokenize(cmd)
	return str(argv[0]) if argv.size() > 0 else ""


## Absolute path to the engraver input (writes inline content to a temp file if needed).
static func input_abs_for(content: Dictionary, format: String, options: Dictionary) -> String:
	Cache.ensure_dir()
	if content.kind == "path":
		return _globalize(content.path)
	var in_user := Cache.path_for(Cache.key(_content_id(content), format, 0, "in", options), _ext_for(format))
	if not _write_content(in_user, content):
		return ""
	return ProjectSettings.globalize_path(in_user)


static func content_id(content: Dictionary) -> String:
	return _content_id(content)


## The configured engraver command for a format (used to pick the addressable engine).
static func engraver_command(format: String) -> String:
	return _command_for(format)


## Build the engraver argv (tokens substituted, res:// resolved); public for the addressable paths.
static func build_argv(template: String, input: String, output: String, format: String, page: int) -> PackedStringArray:
	return _build_argv(template, input, output, format, page)


# --- command resolution --------------------------------------------------

static func _command_for(format: String) -> String:
	# "ly" and "lilypond" name the same engine; the documented setting key is /lilypond, so look
	# up either alias under it (the routing in MSRenderQueue already treats them the same).
	var key := "lilypond" if format == "ly" else format
	var c := str(_setting("notation/engraver/" + key, ""))
	if c != "":
		return c
	var exe := str(_setting("notation/external_renderer_path", ""))
	if exe != "":
		var a := str(_setting("notation/external_renderer_args", "{input} -o {output}"))
		return "\"%s\" %s" % [exe, a]
	return _builtin_default(format)


## Built-in engraver for formats we ship a wrapper for, so notation works with zero project settings.
## Verovio reads MEI and ABC natively; the bundled wrapper writes a cropped SVG (+ timemap when the
## addressable path appends --timemap). Uses the platform's default launcher; override the
## musicscene/notation/engraver/<format> setting to name a specific interpreter (e.g. a venv python).
static func _builtin_default(format: String) -> String:
	if format == "mei" or format == "abc":
		var py := "py" if OS.get_name() == "Windows" else "python3"
		return "%s \"res://addons/musicscene/tools/verovio_render.py\" {input} {output} --page {page} --text-to-path" % py
	return ""


## Default output extension for an engraver command when engraver_output/<format> isn't set.
## The bundled Verovio wrapper writes SVG; everything else defaults to the global engraver_output.
static func _default_output_ext(cmd: String) -> String:
	if cmd.to_lower().contains("verovio"):
		return "svg"
	return str(_setting("notation/engraver_output", "png"))


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
		# Let commands reference bundled tools portably (e.g. a res:// wrapper script).
		if s.begins_with("res://") or s.begins_with("user://"):
			s = ProjectSettings.globalize_path(s)
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


## Engravers append their own suffixes (LilyPond: ".cropped"; MuseScore: "-1"). Given the wanted
## out_user (e.g. .../<hash>.png), return whichever variant the engraver actually wrote.
static func _resolve_output(out_user: String, ext: String, page: int) -> String:
	# Prefer the tightly-cropped variant (LilyPond writes both <base>.cropped.png AND a full-page
	# <base>.png), then the exact target, then per-page suffixes (MuseScore writes <base>-1.png).
	var stem := out_user.get_basename()
	var variants := [
		"%s.cropped.%s" % [stem, ext],
		out_user,
		"%s-page%d.%s" % [stem, page, ext],
		"%s-%d.%s" % [stem, page, ext],
		"%s-page1.%s" % [stem, ext],
		"%s-1.%s" % [stem, ext],
	]
	for v in variants:
		if FileAccess.file_exists(v):
			return v
	return ""


static func _copy_file(src: String, dst: String) -> void:
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		return
	var data := f.get_buffer(f.get_length())
	f.close()
	var o := FileAccess.open(dst, FileAccess.WRITE)
	if o == null:
		return
	o.store_buffer(data)
	o.close()


static func _globalize(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _setting(key: String, def):
	return ProjectSettings.get_setting("musicscene/" + key, def)
