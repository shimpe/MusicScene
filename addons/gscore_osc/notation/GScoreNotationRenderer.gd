extends RefCounted
## Backend-agnostic notation renderer. Maps a format string to a concrete backend and returns
## a GScoreNotationRenderResult. New engraving engines plug in by adding a backend and a case
## here; nothing else in the system changes.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")
const ImageBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendImage.gd")
const SvgBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendSvg.gd")
const ExternalBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendMusicXML.gd")

const RASTER_FORMATS := ["png", "image", "jpg", "jpeg", "webp", "bmp"]
const SYMBOLIC_FORMATS := ["musicxml", "mei", "guido", "abc", "lilypond", "ly", "pdf"]


static func backend_for(format: String) -> String:
	var f := format.to_lower()
	if f in RASTER_FORMATS:
		return "image"
	if f == "svg":
		return "svg"
	if f in SYMBOLIC_FORMATS:
		return "external"
	return "unknown"


## Render a single page. Returns a GScoreNotationRenderResult (check .ok / .error).
static func render(source: String, format: String, page: int, options: Dictionary = {}):
	var f := format.to_lower()
	if f in RASTER_FORMATS:
		return ImageBackend.render(source, page, options)
	if f == "svg":
		return SvgBackend.render(source, page, options)
	if f in SYMBOLIC_FORMATS:
		return ExternalBackend.render(source, f, page, options)
	if f == "glyphs":
		return Result.make_error("glyphs", "Lightweight glyph backend not implemented in v1")
	return Result.make_error("unknown", "Unsupported notation format: " + format)
