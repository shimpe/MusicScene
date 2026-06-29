extends Node
## Runs external engravers (MuseScore/LilyPond/…) without blocking the main thread.
## Instead of OS.execute (which freezes Godot until the engraver finishes), it launches the process
## with OS.create_process and polls OS.is_process_running each frame; when the process exits it
## finalizes (locates the output, loads the texture) and notifies the notation object. Cached
## results are applied immediately. A timeout guards against a hung engraver.

const Renderer := preload("res://addons/gscore_osc/notation/GScoreNotationRenderer.gd")
const ExternalBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendMusicXML.gd")

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
		print("[GScoreOSC] engraving '%s' (%s) in background, pid %d" % [notation_obj.osc_id, format, pid])
	_jobs.append({
		"pid": pid, "out_user": prep.out_user, "out_ext": prep.out_ext,
		"page": page, "options": options, "obj": notation_obj, "start": Time.get_ticks_msec(),
	})


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
		var res = ExternalBackend.finalize(j.out_user, j.out_ext, j.page, j.options)
		if res.ok:
			j.obj._on_render_done(res)
		else:
			j.obj._on_render_failed(res.error)
