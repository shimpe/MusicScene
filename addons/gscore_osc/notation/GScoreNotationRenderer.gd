extends RefCounted
## Backend-agnostic notation renderer. Accepts a score as a file PATH, inline TEXT (e.g. a
## runtime-generated SVG / MusicXML / LilyPond / ABC string), or BYTES (e.g. PNG data over an OSC
## blob), normalizes it, and dispatches to the right backend. New engines plug in by adding a
## backend and a case here; nothing else changes.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")
const ImageBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendImage.gd")
const SvgBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendSvg.gd")
const ExternalBackend := preload("res://addons/gscore_osc/notation/GScoreNotationBackendMusicXML.gd")

const RASTER_FORMATS := ["png", "image", "jpg", "jpeg", "webp", "bmp"]
const SYMBOLIC_FORMATS := ["musicxml", "mei", "guido", "abc", "lilypond", "ly", "pdf"]
const TEXTUAL_FORMATS := ["svg", "musicxml", "mei", "guido", "abc", "lilypond", "ly"]


static func backend_for(format: String) -> String:
	var f := format.to_lower()
	if f in RASTER_FORMATS:
		return "image"
	if f == "svg":
		return "svg"
	if f in SYMBOLIC_FORMATS:
		return "external"
	return "unknown"


## content: a String (path OR inline text) or a PackedByteArray (raw bytes).
## force_data: when true, a String content is treated as inline text rather than a path.
static func render(content, format: String, page: int, options: Dictionary = {}, force_data: bool = false):
	var f := format.to_lower()
	var c := _normalize(content, f, force_data)
	if f in RASTER_FORMATS:
		return ImageBackend.render(c, page, options)
	if f == "svg":
		return SvgBackend.render(c, page, options)
	if f in SYMBOLIC_FORMATS:
		return ExternalBackend.render(c, f, page, options)
	if f == "glyphs":
		return Result.make_error("glyphs", "Lightweight glyph backend not implemented in v1")
	return Result.make_error("unknown", "Unsupported notation format: " + format)


## Returns {kind: "path"|"text"|"bytes", path, text, bytes}.
static func _normalize(content, f: String, force_data: bool) -> Dictionary:
	if content is PackedByteArray:
		return {"kind": "bytes", "path": "", "text": "", "bytes": content}
	var s := String(content)
	if not force_data and _looks_like_path(s):
		return {"kind": "path", "path": s.replace("\\", "/"), "text": "", "bytes": PackedByteArray()}
	# Inline content. Textual formats keep it as text; a raster format with a non-path string is a
	# best-effort path (nothing else makes sense for raw raster).
	if force_data or f in TEXTUAL_FORMATS:
		return {"kind": "text", "path": "", "text": s, "bytes": PackedByteArray()}
	return {"kind": "path", "path": s.replace("\\", "/"), "text": "", "bytes": PackedByteArray()}


static func _looks_like_path(s: String) -> bool:
	if s == "":
		return false
	if s.begins_with("res://") or s.begins_with("user://"):
		return true
	if s.begins_with("/"):
		return true   # unix absolute
	if s.length() >= 3 and s[1] == ":" and (s[2] == "/" or s[2] == "\\"):
		return true   # windows absolute (C:/ or C:\)
	# Markup or multiple lines => inline data, not a path.
	if s.contains("<") or s.contains("\n"):
		return false
	# Short, single-line, no markup: treat as a (relative) path.
	return true
