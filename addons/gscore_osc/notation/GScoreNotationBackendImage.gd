extends RefCounted
## PNG / image notation backend. The canonical, always-available v1 backend: it displays any
## raster page produced by an external engraver (MuseScore, LilyPond, Verovio, Dorico, …).
##
## Multi-page: if the source contains the token "{page}" it is substituted with the 1-based
## page number, and the page count is probed by scanning for sequential files.

const Result := preload("res://addons/gscore_osc/notation/GScoreNotationRenderResult.gd")

const BACKEND := "image"
const MAX_PAGE_PROBE := 512


static func render(source: String, page: int, _options: Dictionary = {}):
	var path := source
	var page_count := 1
	if source.contains("{page}"):
		path = source.replace("{page}", str(page))
		page_count = _count_pages(source)
	var tex := _load_texture(path)
	if tex == null:
		return Result.make_error(BACKEND, "Could not load image: " + path)
	return Result.make_ok(BACKEND, tex, page_count)


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
