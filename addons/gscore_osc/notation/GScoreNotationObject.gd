class_name GScoreNotationObject
extends Node2D
## A first-class music-notation object. Behaves like any other GScore object (positioned,
## scaled, hidden, physics-enabled, clickable) while adding notation page display, a playback
## cursor, addressable regions and annotations. Overlays are children so they move/scale with
## the score. Page-internal coordinates are normalized [0,1] over the page rect (y-down).

const Renderer := preload("res://addons/gscore_osc/notation/GScoreNotationRenderer.gd")
const Cache := preload("res://addons/gscore_osc/notation/GScoreNotationCache.gd")

var ctx = null
var osc_id: String = ""

var sprite: Sprite2D
var regions_root: Node2D
var annotations_root: Node2D
var cursor: GScoreNotationCursor

var regions: Dictionary = {}        # id -> GScoreNotationRegion
var annotations: Dictionary = {}    # id -> GScoreNotationAnnotation

var source_content = ""      # String (path or inline text) OR PackedByteArray
var source_label: String = ""  # human-readable, for notationInfo
var _force_data: bool = false
var _pending: bool = false      # an async engrave is in flight
var format: String = ""
var backend: String = ""
var current_page: int = 1
var page_count: int = 1
var page_size: Vector2 = Vector2(600, 800)
var render_options: Dictionary = {}

# Symbolic addressing hints (no geometry in v1, stored for clients/future use).
var system_no: int = -1
var staff_no: int = -1
var measure_no: int = -1
var part_id: String = ""


func setup(p_ctx, p_osc_id: String) -> void:
	ctx = p_ctx
	osc_id = p_osc_id
	sprite = Sprite2D.new()
	sprite.name = "Page"
	sprite.centered = true
	add_child(sprite)
	regions_root = Node2D.new()
	regions_root.name = "Regions"
	add_child(regions_root)
	annotations_root = Node2D.new()
	annotations_root.name = "Annotations"
	add_child(annotations_root)
	cursor = GScoreNotationCursor.new()
	cursor.name = "Cursor"
	cursor.visible = false
	add_child(cursor)
	_update_geometry()


func _base_addr() -> String:
	return "/gscore/scene/" + osc_id


# =========================================================================
# Notation source / pages
# =========================================================================

func handle(verb: String, args: Array) -> void:
	match verb:
		"notation":
			format = _s(args, 0)
			_set_content(args[1] if args.size() > 1 else "", false)
			current_page = 1
			_render()
		"notationsource":
			_set_content(args[0] if args.size() > 0 else "", false)
			_render()
		"notationdata":
			format = _s(args, 0)
			_set_content(args[1] if args.size() > 1 else "", true)
			current_page = 1
			_render()
		"notationformat":
			format = _s(args, 0)
			_render()
		"render", "reload":
			_render()
		"page":
			current_page = clampi(int(_f(args, 0, 1)), 1, page_count)
			_render()
			reply_current_page()
		"nextpage":
			current_page = clampi(current_page + 1, 1, page_count)
			_render()
			reply_current_page()
		"prevpage":
			current_page = clampi(current_page - 1, 1, page_count)
			_render()
			reply_current_page()
		"pages":
			reply_pages()
		"system":
			system_no = int(_f(args, 0, -1))
		"staff":
			staff_no = int(_f(args, 0, -1))
		"measure":
			measure_no = int(_f(args, 0, -1))
		"part":
			part_id = _s(args, 0)
		"notationinfo":
			reply_info()
		"currentpage":
			reply_current_page()


func _set_content(value, force_data: bool) -> void:
	source_content = value
	_force_data = force_data
	if value is PackedByteArray:
		source_label = "<bytes:%d>" % value.size()
	else:
		var sv := str(value)
		if sv.length() <= 120 and not sv.contains("\n") and not sv.contains("<"):
			source_label = sv
		else:
			source_label = "<inline %s, %d chars>" % [format, sv.length()]


func _is_content_empty() -> bool:
	if source_content is PackedByteArray:
		return source_content.is_empty()
	return str(source_content) == ""


func _render() -> void:
	if _is_content_empty() or format == "":
		return
	# External engravers run async (non-blocking) via the render queue; fast backends stay sync.
	if Renderer.backend_for(format) == "external" and ctx.render_queue != null:
		_pending = true
		queue_redraw()
		ctx.render_queue.submit(self, source_content, format, current_page, render_options, _force_data)
		return
	_apply_result(Renderer.render(source_content, format, current_page, render_options, _force_data))


func _on_render_done(res) -> void:
	_pending = false
	_apply_result(res)


func _on_render_failed(err: String) -> void:
	_pending = false
	queue_redraw()
	ctx.error("load_failed", _base_addr() + "/notation", err)


func _apply_result(res) -> void:
	if not res.ok:
		ctx.error("load_failed", _base_addr() + "/notation", res.error)
		return
	sprite.texture = res.texture
	backend = res.backend
	page_count = res.page_count
	page_size = res.texture.get_size()
	_update_geometry()
	queue_redraw()
	if ctx.verbose:
		print("[GScoreOSC] notation '%s' rendered %s page %d/%d (%s) %dx%d px"
			% [osc_id, format, current_page, page_count, backend, int(page_size.x), int(page_size.y)])


func _update_geometry() -> void:
	if cursor != null:
		cursor.set_page_size(page_size)
	for r in regions.values():
		r.set_page_size(page_size)
	for a in annotations.values():
		a.set_page_size(page_size)


# =========================================================================
# Cursor
# =========================================================================

func handle_cursor(args: Array) -> void:
	var cmd := _s(args, 0)
	match cmd:
		"show":
			cursor.visible = _b(args, 1, true)
		"pos":
			cursor.u = _f(args, 1)
			cursor.v = _f(args, 2)
			cursor.queue_redraw()
		"measure", "beat", "time":
			# No time/measure map in v1: store v as a passthrough; clients can drive `pos`/`map`.
			cursor.v = _f(args, 1)
		"color":
			cursor.line_color = _color(args, 1)
			cursor.queue_redraw()
		"width":
			cursor.line_width = _f(args, 1, 3.0)
			cursor.queue_redraw()
		"map":
			ctx.timemapper.add_cursor_map(self, args.slice(1))
		_:
			ctx.error("bad_arguments", _base_addr() + "/cursor", "Unknown cursor cmd: " + cmd)


## Used by the time mapper for cursor maps (x|y|opacity).
func set_cursor_property(prop: String, val: float) -> void:
	match prop:
		"x":
			cursor.set_u(val)
		"y":
			cursor.v = val
			cursor.queue_redraw()
		"opacity":
			var c: Color = cursor.line_color
			c.a = val
			cursor.line_color = c
			cursor.queue_redraw()


# =========================================================================
# Regions
# =========================================================================

func handle_region(args: Array) -> void:
	var rid := _s(args, 0)
	if rid == "":
		ctx.error("bad_arguments", _base_addr() + "/region", "Missing region id")
		return
	var cmd := _s(args, 1)
	var reg := _ensure_region(rid)
	match cmd:
		"rect":
			reg.set_rect_norm(Rect2(_f(args, 2), _f(args, 3), _f(args, 4), _f(args, 5)))
		"measure":
			reg.measure = int(_f(args, 2, -1))
			reg.staff = int(_f(args, 3, -1))
		"on":
			reg.bindings[_s(args, 2)] = _s(args, 3)
		"highlight":
			reg.highlight = _b(args, 2, true)
			reg.queue_redraw()
		"color":
			reg.fill_color = _color(args, 2)
			reg.queue_redraw()
		_:
			ctx.error("bad_arguments", _base_addr() + "/region", "Unknown region cmd: " + cmd)


func _ensure_region(rid: String) -> GScoreNotationRegion:
	if regions.has(rid):
		return regions[rid]
	var reg := GScoreNotationRegion.new()
	reg.region_id = rid
	reg.set_page_size(page_size)
	regions_root.add_child(reg)
	regions[rid] = reg
	return reg


## Returns regions whose area contains the given global point (for input hit-testing).
func hit_test_regions(global_point: Vector2) -> Array:
	var out: Array = []
	for reg in regions.values():
		if reg.contains_local(reg.to_local(global_point)):
			out.append(reg)
	return out


# =========================================================================
# Annotations
# =========================================================================

func handle_annotation(args: Array) -> void:
	var aid := _s(args, 0)
	if aid == "":
		ctx.error("bad_arguments", _base_addr() + "/annotation", "Missing annotation id")
		return
	var cmd := _s(args, 1)
	if cmd == "del":
		if annotations.has(aid):
			annotations[aid].queue_free()
			annotations.erase(aid)
		return
	var ann := _ensure_annotation(aid)
	match cmd:
		"text":
			ann.text = _s(args, 2)
			ann.queue_redraw()
		"rect":
			ann.rect_norm = Rect2(_f(args, 2), _f(args, 3), _f(args, 4), _f(args, 5))
			ann.queue_redraw()
		"glyph":
			ann.glyph = _s(args, 2)
			ann.queue_redraw()
		"color":
			ann.text_color = _color(args, 2)
			ann.queue_redraw()
		"show":
			ann.visible = true
		"hide":
			ann.visible = false
		_:
			ctx.error("bad_arguments", _base_addr() + "/annotation", "Unknown annotation cmd: " + cmd)


func _ensure_annotation(aid: String) -> GScoreNotationAnnotation:
	if annotations.has(aid):
		return annotations[aid]
	var ann := GScoreNotationAnnotation.new()
	ann.ann_id = aid
	ann.set_page_size(page_size)
	annotations_root.add_child(ann)
	annotations[aid] = ann
	return ann


# =========================================================================
# Queries
# =========================================================================

func reply_info() -> void:
	ctx.reply("notationInfo", [osc_id, format, source_label, backend, page_count])

func reply_pages() -> void:
	ctx.reply("pages", [osc_id, page_count])

func reply_current_page() -> void:
	ctx.reply("page", [osc_id, current_page])

func reply_regions() -> void:
	var vals: Array = [osc_id]
	for rid in regions.keys():
		var c: Vector2 = regions[rid].center_norm()
		vals.append_array([rid, c.x, c.y])
	ctx.reply("regions", vals)

func reply_annotations() -> void:
	var vals: Array = [osc_id]
	for aid in annotations.keys():
		vals.append(aid)
	ctx.reply("annotations", vals)


# =========================================================================
# Sizing + placeholder render
# =========================================================================

func gscore_set_size(w_px: float, h_px: float) -> void:
	if page_size.x > 0 and page_size.y > 0:
		scale = Vector2(w_px / page_size.x, h_px / page_size.y)

func gscore_get_bounds() -> Rect2:
	return Rect2(-page_size * 0.5, page_size)

func gscore_contains_point(local: Vector2) -> bool:
	return gscore_get_bounds().has_point(local)


func _draw() -> void:
	# Placeholder page outline so a freshly-created notation object is visible before a source
	# is loaded.
	if sprite != null and sprite.texture != null:
		return
	var r := Rect2(-page_size * 0.5, page_size)
	draw_rect(r, Color(0.97, 0.97, 0.95, 1.0), true)
	draw_rect(r, Color(0.2, 0.2, 0.2, 0.6), false, 2.0)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := "engraving %s…" % format if _pending else "notation: %s" % (osc_id if osc_id != "" else "(empty)")
		draw_string(font, Vector2(-page_size.x * 0.5 + 16, -page_size.y * 0.5 + 36),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.3, 0.3, 0.3))


# --- arg helpers ---------------------------------------------------------

func _s(args: Array, i: int, def: String = "") -> String:
	return str(args[i]) if i < args.size() else def

func _f(args: Array, i: int, def: float = 0.0) -> float:
	if i < args.size():
		var a = args[i]
		if a is float or a is int:
			return float(a)
		if a is String and a.is_valid_float():
			return float(a)
	return def

func _b(args: Array, i: int, def: bool = false) -> bool:
	if i >= args.size():
		return def
	var a = args[i]
	if a is bool:
		return a
	if a is int or a is float:
		return float(a) != 0.0
	if a is String:
		return a == "1" or a.to_lower() == "true"
	return def

func _color(args: Array, start: int) -> Color:
	return Color(_f(args, start, 1.0), _f(args, start + 1, 1.0),
		_f(args, start + 2, 1.0), _f(args, start + 3, 1.0))
