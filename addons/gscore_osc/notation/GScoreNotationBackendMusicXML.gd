extends RefCounted
## Symbolic-format backend (MusicXML / MEI / GUIDO / ABC / LilyPond / PDF) that delegates
## engraving to an external command and then displays the resulting PNG/SVG pages. This keeps
## the OSC API identical regardless of which engraver a site uses.
##
## Configure via project settings:
##   gscore_osc/notation/external_renderer_path  e.g. "C:/Program Files/MuseScore 4/bin/MuseScore4.exe"
##   gscore_osc/notation/external_renderer_args  e.g. "{input} -o {output}"
## Tokens substituted in the args: {input} {output} {format} {page}.
##
## The rendered page is cached under user://gscore_cache/notation/, so the external tool only
## runs once per (source, format, page) combination.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")
const Cache := preload("res://addons/gscore_osc/notation/GScoreNotationCache.gd")
const ImageBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendImage.gd")

const BACKEND := "external"


static func render(source: String, format: String, page: int, options: Dictionary = {}):
	var exe := str(ProjectSettings.get_setting("gscore_osc/notation/external_renderer_path", ""))
	if exe == "":
		return Result.make_error(BACKEND,
			"No external renderer configured for '%s'. Set gscore_osc/notation/external_renderer_path "
			% format + "or pre-render to PNG/SVG and use the image/svg backend.")

	Cache.ensure_dir()
	var cache_key := Cache.key(source, format, page, BACKEND, options)
	var out_png := Cache.path_for(cache_key, "png")
	var out_abs := ProjectSettings.globalize_path(out_png)

	if not Cache.has(out_png):
		var input_abs := ProjectSettings.globalize_path(source) if source.begins_with("res://") or source.begins_with("user://") else source
		var args_template := str(ProjectSettings.get_setting("gscore_osc/notation/external_renderer_args", "{input} -o {output}"))
		var args := _build_args(args_template, input_abs, out_abs, format, page)
		var output: Array = []
		var code := OS.execute(exe, args, output, true)
		if code != 0:
			return Result.make_error(BACKEND,
				"External renderer exit %d: %s" % [code, "\n".join(output).left(200)])
		if not Cache.has(out_png):
			return Result.make_error(BACKEND, "External renderer produced no output page: " + out_png)

	# Display the produced page via the image backend.
	return ImageBackend.render(out_png, 1, options)


static func _build_args(template: String, input: String, output: String, format: String, page: int) -> PackedStringArray:
	var subst := template \
		.replace("{input}", input) \
		.replace("{output}", output) \
		.replace("{format}", format) \
		.replace("{page}", str(page))
	var args := PackedStringArray()
	for tok in subst.split(" ", false):
		if tok != "":
			args.append(tok)
	return args
