extends RefCounted
## Value object returned by every notation backend. Decouples the renderer/display node from
## how a page was produced (PNG file, SVG raster, external engraver, …).

var ok: bool = false
var texture: Texture2D = null
var page_count: int = 1
var backend: String = ""
var error: String = ""


static func make_error(backend_name: String, message: String):
	var r = new()
	r.backend = backend_name
	r.error = message
	r.ok = false
	return r


static func make_ok(backend_name: String, tex: Texture2D, pages: int = 1):
	var r = new()
	r.backend = backend_name
	r.texture = tex
	r.page_count = maxi(1, pages)
	r.ok = true
	return r
