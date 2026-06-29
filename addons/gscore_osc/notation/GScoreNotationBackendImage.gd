extends RefCounted
## PNG / raster notation backend. The canonical, always-available backend: it displays any raster
## page produced by an external engraver (MuseScore, LilyPond, Verovio, Dorico, …), whether from a
## file PATH (res:// / user:// / absolute) or from raw BYTES sent over an OSC blob.
##
## Multi-page (path only): if the source contains "{page}" it is substituted with the 1-based page
## number and the count is probed by scanning for sequential files.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")

const BACKEND := "image"
const MAX_PAGE_PROBE := 512


## content: {kind, path, text, bytes} from the renderer.
static func render(content: Dictionary, page: int, _options: Dictionary = {}):
	if content.kind == "bytes":
		var tex := _texture_from_bytes(content.bytes)
		if tex == null:
			return Result.make_error(BACKEND, "Could not decode image bytes (expected png/jpg/webp/bmp)")
		return Result.make_ok(BACKEND, tex, 1)

	# path (or stray text treated as a path)
	var src: String = content.path if content.kind == "path" else content.text
	var path := src
	var page_count := 1
	if src.contains("{page}"):
		path = src.replace("{page}", str(page))
		page_count = _count_pages(src)
	var tex := _load_texture(path)
	if tex == null:
		return Result.make_error(BACKEND, "Could not load image: " + path)
	return Result.make_ok(BACKEND, tex, page_count)


static func _texture_from_bytes(bytes: PackedByteArray) -> Texture2D:
	var img := Image.new()
	for loader in ["load_png_from_buffer", "load_jpg_from_buffer", "load_webp_from_buffer", "load_bmp_from_buffer"]:
		if img.call(loader, bytes) == OK:
			return ImageTexture.create_from_image(img)
	return null


static func _count_pages(template: String) -> int:
	var n := 0
	for i in range(1, MAX_PAGE_PROBE + 1):
		if _exists(template.replace("{page}", str(i))):
			n = i
		else:
			break
	return maxi(1, n)


static func _exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null
