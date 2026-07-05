extends Node
## Runs external engravers (MuseScore/LilyPond/…) without blocking the main thread.
## Instead of OS.execute (which freezes Godot until the engraver finishes), it launches the process
## with OS.create_process and polls OS.is_process_running each frame; when the process exits it
## finalizes (locates the output, loads the texture) and notifies the notation object. Cached
## results are applied immediately. A timeout guards against a hung engraver.

const Renderer := preload("res://addons/musicscene/notation/MSNotationRenderer.gd")
const ExternalBackend := preload("res://addons/musicscene/notation/MSNotationBackendMusicXML.gd")
const Cache := preload("res://addons/musicscene/notation/MSNotationCache.gd")
const Positions := preload("res://addons/musicscene/notation/MSNotationPositions.gd")
const LilyPositions := preload("res://addons/musicscene/notation/MSNotationLilyPositions.gd")
const VerovioPositions := preload("res://addons/musicscene/notation/MSNotationVerovioPositions.gd")

const TIMEOUT_MS := 60000

var ctx = null
var _jobs: Array = []


func setup(p_ctx) -> void:
	ctx = p_ctx


## Submit a notation render. The notation object receives _on_render_done(result) or
## _on_render_failed(error_string) — possibly synchronously (cached) or later (after engraving).
func submit(notation_obj, raw_content, format: String, page: int, options: Dictionary, force_data: bool) -> void:
	var content := Renderer.normalize(raw_content, format, force_data)
	var prep := ExternalBackend.prepare(content, format, page, options)
	if not prep.get("ok", false):
		notation_obj._on_render_failed(str(prep.get("error", "engraver prepare failed")))
		return
	if prep.get("cached", false):
		notation_obj._on_render_done(ExternalBackend.finalize(prep.out_user, prep.out_ext, page, options))
		return
	var pid := OS.create_process(prep.exe, prep.args, false)
	if pid <= 0:
		notation_obj._on_render_failed("Could not launch engraver: " + str(prep.exe))
		return
	if ctx.verbose:
		print("[MusicSceneOSC] engraving '%s' (%s) in background, pid %d" % [notation_obj.osc_id, format, pid])
	_jobs.append({
		"kind": "engrave", "pid": pid, "out_user": prep.out_user, "out_ext": prep.out_ext,
		"page": page, "options": options, "obj": notation_obj, "start": Time.get_ticks_msec(),
	})


## Submit an ADDRESSABLE render: one MuseScore batch job produces a full-page PNG (at a known DPI)
## plus a .mpos position export; on completion the page is cropped to the music and each measure is
## returned as a page-normalized rect. v1 supports MuseScore (musicxml/mei).
func submit_addressable(notation_obj, raw_content, format: String, page: int, options: Dictionary, force_data: bool) -> void:
	# Pick the addressable engine from the configured engraver command (or the format).
	var cmd_l := ExternalBackend.engraver_command(format).to_lower()
	if cmd_l.contains("verovio"):
		_submit_verovio(notation_obj, raw_content, format, page, options, force_data)
		return
	if format == "lilypond" or format == "ly" or cmd_l.contains("lilypond"):
		_submit_lily(notation_obj, raw_content, format, page, options, force_data)
		return
	var content := Renderer.normalize(raw_content, format, force_data)
	var exe := ExternalBackend.engraver_exe(format)
	if exe == "":
		notation_obj._on_render_failed("addressable needs a MuseScore engraver configured for '%s'" % format)
		return
	var input_abs := ExternalBackend.input_abs_for(content, format, options)
	if input_abs == "":
		notation_obj._on_render_failed("addressable: could not prepare engraver input")
		return
	Cache.ensure_dir()
	var base_key := Cache.key(ExternalBackend.content_id(content), format, page, "addr", options)
	var png_user := Cache.path_for(base_key, "png")
	var mpos_user := Cache.path_for(base_key, "mpos")

	if _addr_cached(png_user, mpos_user):
		_finish_addressable(notation_obj, png_user, mpos_user, page)
		return

	var job_user := Cache.path_for(base_key, "json")
	if not Positions.write_job(job_user, input_abs,
			ProjectSettings.globalize_path(png_user), ProjectSettings.globalize_path(mpos_user)):
		notation_obj._on_render_failed("addressable: could not write MuseScore job")
		return
	var args := PackedStringArray(["-r", str(int(Positions.RENDER_DPI)), "-j", ProjectSettings.globalize_path(job_user)])
	var pid := OS.create_process(exe, args, false)
	if pid <= 0:
		notation_obj._on_render_failed("addressable: could not launch " + exe)
		return
	if ctx.verbose:
		print("[MusicSceneOSC] analyzing '%s' (%s) in background, pid %d" % [notation_obj.osc_id, format, pid])
	_jobs.append({
		"kind": "addr", "pid": pid, "obj": notation_obj,
		"png_user": png_user, "mpos_user": mpos_user, "page": page,
		"start": Time.get_ticks_msec(),
	})


## LilyPond addressable: inject the timing tagger, render cropped SVG, parse note-level positions.
func _submit_lily(notation_obj, raw_content, format: String, page: int, options: Dictionary, force_data: bool) -> void:
	var content := Renderer.normalize(raw_content, format, force_data)
	var exe := ExternalBackend.engraver_exe(format)
	if exe == "":
		notation_obj._on_render_failed("addressable needs a LilyPond engraver configured for '%s'" % format)
		return
	var ly_text := ""
	if content.kind == "text":
		ly_text = content.text
	elif content.kind == "bytes":
		ly_text = content.bytes.get_string_from_utf8()
	else:
		var ap: String = content.path
		ly_text = FileAccess.get_file_as_string(ap if (ap.begins_with("res://") or FileAccess.file_exists(ap)) else ProjectSettings.globalize_path(ap))
	if ly_text.strip_edges() == "":
		notation_obj._on_render_failed("addressable: empty LilyPond source")
		return

	var wrapped := LilyPositions.wrap_source(ly_text)
	Cache.ensure_dir()
	var key := Cache.key(wrapped, format, page, "lyaddr", options)
	var in_user := Cache.path_for(key, "ly")
	var stem_user := Cache.path_for(key, "svg").get_basename()   # cache dir + key (no ext)
	var cropped_user := stem_user + ".cropped.svg"

	if FileAccess.file_exists(cropped_user):
		_finish_lily(notation_obj, cropped_user, options)
		return

	var f := FileAccess.open(in_user, FileAccess.WRITE)
	if f == null:
		notation_obj._on_render_failed("addressable: cannot write temp LilyPond")
		return
	f.store_string(wrapped)
	f.close()

	var args := PackedStringArray([
		"-dbackend=svg", "-dcrop=#t",
		"-o", ProjectSettings.globalize_path(stem_user), ProjectSettings.globalize_path(in_user),
	])
	var pid := OS.create_process(exe, args, false)
	if pid <= 0:
		notation_obj._on_render_failed("addressable: could not launch " + exe)
		return
	if ctx.verbose:
		print("[MusicSceneOSC] analyzing '%s' (lilypond) in background, pid %d" % [notation_obj.osc_id, pid])
	_jobs.append({
		"kind": "lyaddr", "pid": pid, "obj": notation_obj,
		"cropped_user": cropped_user, "options": options, "start": Time.get_ticks_msec(),
	})


func _finish_lily(obj, cropped_user: String, options: Dictionary, pid: int = -1) -> void:
	var res := LilyPositions.finalize(cropped_user, options)
	if res.ok:
		obj._on_elements_done(res.texture, res.elements)
	else:
		obj._on_render_failed(res.error + _exit_note(pid))


## Verovio addressable: run the wrapper to produce SVG + timemap, then join them into note elements.
func _submit_verovio(notation_obj, raw_content, format: String, page: int, options: Dictionary, force_data: bool) -> void:
	var content := Renderer.normalize(raw_content, format, force_data)
	var input_abs := ExternalBackend.input_abs_for(content, format, options)
	if input_abs == "":
		notation_obj._on_render_failed("verovio: could not prepare input")
		return
	Cache.ensure_dir()
	var key := Cache.key(ExternalBackend.content_id(content), format, page, "vrv", options)
	var svg_user := Cache.path_for(key, "svg")
	var tm_user := Cache.path_for(key, "json")

	var paginate: bool = options.get("paginate", false)
	var stem := svg_user.get_basename()

	if paginate:
		if FileAccess.file_exists(stem + "-1.svg") and FileAccess.file_exists(tm_user):
			_finish_verovio_paged(notation_obj, stem, tm_user, options)
			return
	elif FileAccess.file_exists(svg_user) and FileAccess.file_exists(tm_user):
		_finish_verovio(notation_obj, svg_user, tm_user, options)
		return

	var cmd := ExternalBackend.engraver_command(format)
	var argv := ExternalBackend.build_argv(cmd, input_abs, ProjectSettings.globalize_path(svg_user), format, page)
	argv.append("--timemap")
	argv.append(ProjectSettings.globalize_path(tm_user))
	if paginate:
		argv.append("--paginate")
		argv.append("--page-height")
		argv.append(str(int(options.get("page_height", 1200))))
	if argv.is_empty():
		notation_obj._on_render_failed("verovio: empty command")
		return
	var pid := OS.create_process(argv[0], argv.slice(1), false)
	if pid <= 0:
		notation_obj._on_render_failed("verovio: could not launch " + argv[0])
		return
	if ctx.verbose:
		print("[MusicSceneOSC] analyzing '%s' (%s/verovio%s) in background, pid %d"
			% [notation_obj.osc_id, format, ("/paged" if paginate else ""), pid])
	_jobs.append({
		"kind": "vrv", "pid": pid, "obj": notation_obj, "paginate": paginate, "stem": stem,
		"svg_user": svg_user, "tm_user": tm_user, "options": options, "start": Time.get_ticks_msec(),
	})


func _finish_verovio(obj, svg_user: String, tm_user: String, options: Dictionary, pid: int = -1) -> void:
	var res := VerovioPositions.finalize(svg_user, tm_user, options)
	if res.ok:
		obj._on_elements_done(res.texture, res.elements, res.get("systems", []))
	else:
		obj._on_render_failed(res.error + _exit_note(pid))


func _finish_verovio_paged(obj, svg_stem: String, tm_user: String, options: Dictionary, pid: int = -1) -> void:
	var res := VerovioPositions.finalize_paged(svg_stem, tm_user, options)
	if res.ok:
		obj._on_pages_done(res.pages, res.elements, res.page_count)
	else:
		obj._on_render_failed(res.error + _exit_note(pid))


func _addr_cached(png_user: String, mpos_user: String) -> bool:
	if not FileAccess.file_exists(mpos_user):
		return false
	var stem := png_user.get_basename()
	return FileAccess.file_exists(png_user) or FileAccess.file_exists("%s-1.png" % stem)


func _finish_addressable(obj, png_user: String, mpos_user: String, page: int, pid: int = -1) -> void:
	var res := Positions.finalize(png_user, mpos_user, page)
	if res.ok:
		obj._on_addressable_done(res.texture, res.measures)
	else:
		obj._on_render_failed(res.error + _exit_note(pid))


## When an async engraver job failed to produce output, explain why using its process exit code.
## (Pass -1 for cache hits, which never ran a process.) OS.get_process_exit_code is Godot 4.4+.
func _exit_note(pid: int) -> String:
	if pid < 0:
		return ""
	var code := OS.get_process_exit_code(pid)
	if code == 0:
		return ""
	return ("  [engraver process exited with code %d — check the command's interpreter/script path"
		+ " and that its dependencies are installed (e.g. `pip install verovio`)]") % code


func _process(_delta: float) -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		var j = _jobs[i]
		if not is_instance_valid(j.obj):
			_jobs.remove_at(i)
			continue
		if OS.is_process_running(j.pid):
			if Time.get_ticks_msec() - j.start > TIMEOUT_MS:
				OS.kill(j.pid)
				_jobs.remove_at(i)
				j.obj._on_render_failed("Engraver timed out after %d s" % (TIMEOUT_MS / 1000))
			continue
		_jobs.remove_at(i)
		if j.get("kind", "engrave") == "addr":
			_finish_addressable(j.obj, j.png_user, j.mpos_user, j.page, j.pid)
		elif j.kind == "lyaddr":
			_finish_lily(j.obj, j.cropped_user, j.options, j.pid)
		elif j.kind == "vrv":
			if j.get("paginate", false):
				_finish_verovio_paged(j.obj, j.stem, j.tm_user, j.options, j.pid)
			else:
				_finish_verovio(j.obj, j.svg_user, j.tm_user, j.options, j.pid)
		else:
			var res = ExternalBackend.finalize(j.out_user, j.out_ext, j.page, j.options)
			if res.ok:
				j.obj._on_render_done(res)
			else:
				j.obj._on_render_failed(res.error + _exit_note(j.pid))
