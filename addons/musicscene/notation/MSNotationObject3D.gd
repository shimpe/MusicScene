class_name MSNotationObject3D
extends Node3D
## First-class music-notation object for the 3D backend. The page renders on a textured QuadMesh
## placed/oriented anywhere in 3D space; cursor, regions and annotations are 3D children on the
## quad's surface, so they move/scale/rotate with it. Same OSC command surface as the 2D notation
## object. Page-internal coordinates are normalized [0,1] over the page (u left->right, v top->bottom).

const Renderer := preload("res://addons/musicscene/notation/MSNotationRenderer.gd")
const Region3D := preload("res://addons/musicscene/notation/MSNotationRegion3D.gd")

const PAGE_HEIGHT := 3.0   # default page height in world units

var ctx = null
var osc_id: String = ""

var page_mesh: MeshInstance3D
var page_mat: StandardMaterial3D
var cursor_node: MeshInstance3D
var cursor_mat: StandardMaterial3D

var regions: Dictionary = {}      # id -> MSNotationRegion3D
var annotations: Dictionary = {}  # id -> Label3D

var source_content = ""      # String (path or inline text) OR PackedByteArray
var source_label: String = ""  # human-readable, for notationInfo
var _force_data: bool = false
var _pending: bool = false      # an async engrave is in flight
var addressable: bool = false
var measures: Array = []        # [{index, rect:Rect2(normalized), time}]   (MuseScore)
var elements: Array = []        # [{index, when, line, char, u, v}]          (LilyPond notes)
var _follow: bool = false
var _last_passed: int = -1
var format: String = ""
var backend: String = ""
var current_page: int = 1
var page_count: int = 1
var page_size: Vector2 = Vector2(600, 800)         # texture pixels (for [0,1] mapping)
var page_world: Vector2 = Vector2(2.25, PAGE_HEIGHT)  # quad size in world units
var render_options: Dictionary = {}

# cursor state
var cur_u: float = 0.1
var cur_v: float = 0.5
var cur_color: Color = Color(1, 0, 0, 0.85)
var cur_width: float = 0.04

var system_no: int = -1
var staff_no: int = -1
var measure_no: int = -1
var part_id: String = ""


func setup(p_ctx, p_osc_id: String) -> void:
	ctx = p_ctx
	osc_id = p_osc_id

	page_mat = _mat(Color(0.97, 0.97, 0.95, 1.0))
	page_mesh = MeshInstance3D.new()
	page_mesh.name = "Page"
	var q := QuadMesh.new(); q.size = page_world
	page_mesh.mesh = q
	page_mesh.material_override = page_mat
	add_child(page_mesh)

	cursor_mat = _mat(cur_color)
	# Page, regions and cursor are coplanar transparent quads; Godot sorts transparents by origin
	# distance, so the moving cursor would flip behind the page off-centre. render_priority forces a
	# stable layering: page (0) < regions (1) < cursor (2) < annotations (3).
	page_mat.render_priority = 0
	cursor_mat.render_priority = 2
	cursor_node = MeshInstance3D.new()
	cursor_node.name = "Cursor"
	cursor_node.material_override = cursor_mat
	cursor_node.visible = false
	add_child(cursor_node)
	_update_cursor()


func _base() -> String:
	return "/ms/scene/" + osc_id


# --- Source / pages ------------------------------------------------------

func handle(verb: String, args: Array) -> void:
	match verb:
		"notation":
			format = _s(args, 0); _set_content(args[1] if args.size() > 1 else "", false); current_page = 1; _render()
		"notationsource":
			_set_content(args[0] if args.size() > 0 else "", false); _render()
		"notationdata":
			format = _s(args, 0); _set_content(args[1] if args.size() > 1 else "", true); current_page = 1; _render()
		"notationformat":
			format = _s(args, 0); _render()
		"render", "reload":
			_render()
		"page":
			current_page = clampi(int(_f(args, 0, 1)), 1, page_count); _render(); reply_current_page()
		"nextpage":
			current_page = clampi(current_page + 1, 1, page_count); _render(); reply_current_page()
		"prevpage":
			current_page = clampi(current_page - 1, 1, page_count); _render(); reply_current_page()
		"pages":
			reply_pages()
		"system": system_no = int(_f(args, 0, -1))
		"staff": staff_no = int(_f(args, 0, -1))
		"measure": measure_no = int(_f(args, 0, -1))
		"part": part_id = _s(args, 0)
		"notationinfo": reply_info()
		"currentpage": reply_current_page()
		"addressable":
			addressable = _b(args, 0, true)
			if not _is_content_empty():
				_render()
		"measures": reply_measures()
		"elements": reply_elements()


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
		page_mat.albedo_color = Color(0.85, 0.85, 0.6, 1.0)  # "engraving" tint
		if addressable:
			ctx.render_queue.submit_addressable(self, source_content, format, current_page, render_options, _force_data)
		else:
			ctx.render_queue.submit(self, source_content, format, current_page, render_options, _force_data)
		return
	_apply_result(Renderer.render(source_content, format, current_page, render_options, _force_data))


func _on_addressable_done(texture: Texture2D, p_measures: Array) -> void:
	_pending = false
	page_mat.albedo_texture = texture
	page_mat.albedo_color = Color.WHITE
	backend = "addressable"
	page_count = 1
	page_size = texture.get_size()
	var aspect := page_size.x / page_size.y if page_size.y > 0 else 1.0
	page_world = Vector2(PAGE_HEIGHT * aspect, PAGE_HEIGHT)
	(page_mesh.mesh as QuadMesh).size = page_world
	measures = p_measures
	for m in measures:
		var rid := "m%d" % (int(m.index) + 1)
		var reg := _ensure_region(rid)
		reg.rect_norm = m.rect
		if not reg.bindings.has("click"):
			reg.bindings["click"] = "/ms/event/measure"
	_update_all()
	if ctx.verbose:
		print("[MusicSceneOSC] notation3d '%s' addressable: %d measures, %dx%d px"
			% [osc_id, measures.size(), int(page_size.x), int(page_size.y)])


func reply_measures() -> void:
	var vals: Array = [osc_id]
	for m in measures:
		var r: Rect2 = m.rect
		vals.append_array([int(m.index) + 1, r.position.x, r.position.y, r.size.x, r.size.y, m.time])
	ctx.reply("measures", vals)


func _measure_u(mi: int, frac: float) -> float:
	for m in measures:
		if int(m.index) == mi:
			return m.rect.position.x + frac * m.rect.size.x
	return -1.0


# --- LilyPond note-level addressing + following --------------------------

func _on_elements_done(texture: Texture2D, p_elements: Array) -> void:
	_pending = false
	page_mat.albedo_texture = texture
	page_mat.albedo_color = Color.WHITE
	backend = "addressable-ly"
	page_count = 1
	page_size = texture.get_size()
	var aspect := page_size.x / page_size.y if page_size.y > 0 else 1.0
	page_world = Vector2(PAGE_HEIGHT * aspect, PAGE_HEIGHT)
	(page_mesh.mesh as QuadMesh).size = page_world
	elements = p_elements
	_last_passed = -1
	for e in elements:
		var rid := "n%d" % int(e.index)
		var reg := _ensure_region(rid)
		reg.rect_norm = Rect2(e.u - 0.018, e.v - 0.05, 0.036, 0.10)
		if not reg.bindings.has("click"):
			reg.bindings["click"] = "/ms/event/note"
	_update_all()
	if ctx.verbose:
		print("[MusicSceneOSC] notation3d '%s' addressable-ly: %d notes, %dx%d px"
			% [osc_id, elements.size(), int(page_size.x), int(page_size.y)])


func reply_elements() -> void:
	var vals: Array = [osc_id]
	for e in elements:
		vals.append_array([int(e.index), e.when, int(e.line), int(e.char), e.u, e.v])
	ctx.reply("elements", vals)


func set_follow(on: bool) -> void:
	_follow = on
	_last_passed = -1
	set_process(on)


func _follow_u(when: float) -> float:
	if elements.is_empty():
		return cur_u
	if when <= elements[0].when:
		return elements[0].u
	var last = elements[elements.size() - 1]
	if when >= last.when:
		return last.u
	for i in range(elements.size() - 1):
		var a = elements[i]
		var b = elements[i + 1]
		if when >= a.when and when <= b.when:
			var span: float = b.when - a.when
			return lerpf(a.u, b.u, (when - a.when) / span if span > 0.0 else 0.0)
	return last.u


func _process(_delta: float) -> void:
	if not _follow or ctx == null or ctx.transport == null or not ctx.transport.playing or elements.is_empty():
		return
	var when: float = ctx.transport.beat / 4.0
	if _last_passed >= 0 and _last_passed < elements.size() and when < elements[_last_passed].when:
		_last_passed = -1
	set_cursor_property("x", _follow_u(when))
	while _last_passed + 1 < elements.size() and elements[_last_passed + 1].when <= when:
		_last_passed += 1
		var e = elements[_last_passed]
		ctx.send_event("/ms/event/note", [osc_id, "n%d" % int(e.index), e.when, int(e.line), int(e.char)])


func _on_render_done(res) -> void:
	_pending = false
	_apply_result(res)


func _on_render_failed(err: String) -> void:
	_pending = false
	page_mat.albedo_color = Color(0.97, 0.97, 0.95, 1.0)
	ctx.error("load_failed", _base() + "/notation", err)


func _apply_result(res) -> void:
	if not res.ok:
		ctx.error("load_failed", _base() + "/notation", res.error)
		return
	page_mat.albedo_texture = res.texture
	page_mat.albedo_color = Color.WHITE
	backend = res.backend
	page_count = res.page_count
	page_size = res.texture.get_size()
	# Keep height fixed; derive width from texture aspect.
	var aspect := page_size.x / page_size.y if page_size.y > 0 else 0.75
	page_world = Vector2(PAGE_HEIGHT * aspect, PAGE_HEIGHT)
	(page_mesh.mesh as QuadMesh).size = page_world
	_update_all()
	if ctx.verbose:
		print("[MusicSceneOSC] notation3d '%s' rendered %s page %d/%d (%s) %dx%d px"
			% [osc_id, format, current_page, page_count, backend, int(page_size.x), int(page_size.y)])


# --- Cursor --------------------------------------------------------------

func handle_cursor(args: Array) -> void:
	var cmd := _s(args, 0)
	match cmd:
		"show": cursor_node.visible = _b(args, 1, true)
		"pos": cur_u = _f(args, 1); cur_v = _f(args, 2); _update_cursor()
		"measure":
			var mi := int(_f(args, 1, 1)) - 1
			var mu := _measure_u(mi, _f(args, 2, 0.0))
			if mu >= 0.0:
				cur_u = mu
			else:
				cur_v = _f(args, 1)
			_update_cursor()
		"beat", "time": cur_v = _f(args, 1); _update_cursor()
		"color": cur_color = _color(args, 1); cursor_mat.albedo_color = cur_color
		"width": cur_width = maxf(0.005, _f(args, 1, 0.04)); _update_cursor()
		"map": ctx.timemapper.add_cursor_map(self, args.slice(1))
		"follow": set_follow(_b(args, 1, true))
		_: ctx.error("bad_arguments", _base() + "/cursor", "Unknown cursor cmd: " + cmd)


## Used by the time mapper for cursor maps (x|y|opacity).
func set_cursor_property(prop: String, val: float) -> void:
	match prop:
		"x":
			cur_u = val
			_update_cursor()
		"y":
			cur_v = val
			_update_cursor()
		"opacity":
			cur_color.a = val
			cursor_mat.albedo_color = cur_color


func _update_cursor() -> void:
	var q := cursor_node.mesh as QuadMesh
	if q == null:
		q = QuadMesh.new()
		cursor_node.mesh = q
	q.size = Vector2(cur_width, page_world.y)
	cursor_node.position = Vector3((cur_u - 0.5) * page_world.x, 0.0, 0.02)


# --- Regions -------------------------------------------------------------

func handle_region(args: Array) -> void:
	var rid := _s(args, 0)
	if rid == "":
		ctx.error("bad_arguments", _base() + "/region", "Missing region id")
		return
	var cmd := _s(args, 1)
	var reg := _ensure_region(rid)
	match cmd:
		"rect": reg.rect_norm = Rect2(_f(args, 2), _f(args, 3), _f(args, 4), _f(args, 5)); _update_region(reg)
		"measure": reg.measure = int(_f(args, 2, -1)); reg.staff = int(_f(args, 3, -1))
		"on": reg.bindings[_s(args, 2)] = _s(args, 3)
		"highlight": reg.highlight = _b(args, 2, true); _update_region(reg)
		"color": reg.fill_color = _color(args, 2); _update_region(reg)
		_: ctx.error("bad_arguments", _base() + "/region", "Unknown region cmd: " + cmd)


func _ensure_region(rid: String) -> MSNotationRegion3D:
	if regions.has(rid):
		return regions[rid]
	var reg := Region3D.new()
	reg.region_id = rid
	var mi := MeshInstance3D.new()
	mi.name = "Region_" + rid
	mi.mesh = QuadMesh.new()
	mi.material_override = _mat(reg.fill_color)
	(mi.material_override as StandardMaterial3D).render_priority = 1   # above page, below cursor
	mi.visible = false
	add_child(mi)
	reg.node = mi
	regions[rid] = reg
	return reg


func _update_region(reg: MSNotationRegion3D) -> void:
	var mi := reg.node
	mi.visible = reg.highlight
	(mi.mesh as QuadMesh).size = Vector2(reg.rect_norm.size.x * page_world.x, reg.rect_norm.size.y * page_world.y)
	(mi.material_override as StandardMaterial3D).albedo_color = reg.fill_color
	var c := reg.center_norm()
	mi.position = _local_of(c.x, c.y, 0.015)


func raycast_regions(origin: Vector3, dir: Vector3) -> Array:
	var hit := _ray_plane(origin, dir)
	if not hit.hit:
		return []
	var out: Array = []
	for reg in regions.values():
		if not reg.bindings.is_empty() and reg.contains_uv(hit.u, hit.v):
			out.append({"region": reg, "u": hit.u, "v": hit.v})
	return out


func _ray_plane(origin: Vector3, dir: Vector3) -> Dictionary:
	var normal: Vector3 = (global_transform.basis * Vector3(0, 0, 1)).normalized()
	var denom := dir.dot(normal)
	if absf(denom) < 0.00001:
		return {"hit": false}
	var t := (global_position - origin).dot(normal) / denom
	if t < 0.0:
		return {"hit": false}
	var world := origin + dir * t
	var local := to_local(world)
	var u := local.x / page_world.x + 0.5
	var vv := 0.5 - local.y / page_world.y
	if u < 0.0 or u > 1.0 or vv < 0.0 or vv > 1.0:
		return {"hit": false}
	return {"hit": true, "u": u, "v": vv}


# --- Annotations ---------------------------------------------------------

func handle_annotation(args: Array) -> void:
	var aid := _s(args, 0)
	if aid == "":
		ctx.error("bad_arguments", _base() + "/annotation", "Missing annotation id")
		return
	var cmd := _s(args, 1)
	if cmd == "del":
		if annotations.has(aid):
			annotations[aid].queue_free(); annotations.erase(aid)
		return
	var ann := _ensure_annotation(aid)
	match cmd:
		"text": ann.text = _s(args, 2)
		"glyph": ann.text = _s(args, 2)
		"rect":
			ann.set_meta("rect", Rect2(_f(args, 2), _f(args, 3), _f(args, 4), _f(args, 5)))
			_place_annotation(ann)
		"color": ann.modulate = _color(args, 2)
		"show": ann.visible = true
		"hide": ann.visible = false
		_: ctx.error("bad_arguments", _base() + "/annotation", "Unknown annotation cmd: " + cmd)


func _ensure_annotation(aid: String) -> Label3D:
	if annotations.has(aid):
		return annotations[aid]
	var l := Label3D.new()
	l.name = "Annotation_" + aid
	l.font_size = 48
	l.pixel_size = 0.004
	l.modulate = Color(0.1, 0.1, 0.1)
	l.double_sided = true
	l.render_priority = 3   # above page/regions/cursor
	l.set_meta("rect", Rect2(0.1, 0.1, 0.2, 0.1))
	add_child(l)
	annotations[aid] = l
	_place_annotation(l)
	return l


func _place_annotation(l: Label3D) -> void:
	var r: Rect2 = l.get_meta("rect", Rect2(0.1, 0.1, 0.2, 0.1))
	l.position = _local_of(r.position.x, r.position.y, 0.03)


# --- Queries -------------------------------------------------------------

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


# --- Sizing / style ------------------------------------------------------

func ms_set_size(w_world: float, h_world: float) -> void:
	page_world = Vector2(w_world, h_world)
	(page_mesh.mesh as QuadMesh).size = page_world
	_update_all()

func ms_get_world_size() -> Vector3:
	return Vector3(page_world.x, page_world.y, 0.02)

func ms_set_opacity(a: float) -> void:
	var c := page_mat.albedo_color
	c.a = clampf(a, 0.0, 1.0)
	page_mat.albedo_color = c

func ms_set_color(c: Color) -> void:
	page_mat.albedo_color = c


func _update_all() -> void:
	_update_cursor()
	for reg in regions.values():
		_update_region(reg)
	for l in annotations.values():
		_place_annotation(l)


# --- helpers -------------------------------------------------------------

func _local_of(u: float, v: float, z: float) -> Vector3:
	return Vector3((u - 0.5) * page_world.x, (0.5 - v) * page_world.y, z)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


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
