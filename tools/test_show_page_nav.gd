extends SceneTree
## Regression test for page navigation (showPage / page / nextPage / prevPage) on a paginated,
## async-rendered notation. Drives MSNotationObject deterministically with fake pre-rendered pages.
## Run: <godot> --headless --path . --script res://tools/test_show_page_nav.gd
## Prints "RESULT: PASS" / "RESULT: FAIL ...".

class StubCtx:
	var verbose := false
	var render_queue = null
	var transport = null
	func reply(_t, _v = []): pass
	func error(_a, _b, _c): pass

var _fails: Array = []

func _mktex(sz: int) -> Texture2D:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _pg(sz: int) -> Dictionary:
	return {"texture": _mktex(sz), "systems": []}

func _mk(Obj):
	var o = Obj.new()
	get_root().add_child(o)
	o.setup(StubCtx.new(), "t")
	o.addressable = true
	o.render_options = {"paginate": true, "page_height": 300}
	return o

func _chk(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)

func _init() -> void:
	var Obj = load("res://addons/musicscene/notation/MSNotationObject.gd")

	# A) render completes, THEN page(n): must show the requested page.
	var a = _mk(Obj)
	a._on_pages_done([_pg(100), _pg(200), _pg(300)], [], 3)
	a.handle("page", [2])
	_chk(a.current_page == 2, "A page(2) after render: current_page=%d (want 2)" % a.current_page)
	a.handle("prevpage", [])
	_chk(a.current_page == 1, "A prevpage: current_page=%d (want 1)" % a.current_page)

	# B) page(n) arrives BEFORE the async render completes (the showPage race): the request must be
	#    remembered and honored when the pages arrive (NOT lost / snapped to page 1).
	var b = _mk(Obj)
	b.format = ""   # no content -> the _render() inside _go_page is a no-op (simulates in-flight render)
	b.handle("page", [2])                                   # pages still empty here
	b._on_pages_done([_pg(100), _pg(200), _pg(300)], [], 3) # render lands afterwards
	_chk(b.current_page == 2, "B page(2) before render then render: current_page=%d (want 2)" % b.current_page)

	# C) new notation content must CLEAR stale pre-rendered pages (so a later page nav doesn't act on the
	#    previous score's pages).
	var c = _mk(Obj)
	c._on_pages_done([_pg(100), _pg(200)], [], 2)
	_chk(c.pages.size() == 2, "C precondition pages=%d (want 2)" % c.pages.size())
	c.handle("notationdata", ["mei", "<some new content>"])   # new content
	_chk(c.pages.is_empty(), "C stale pages not cleared on new content: pages=%d (want 0)" % c.pages.size())

	if _fails.is_empty():
		print("RESULT: PASS (page navigation robust to async render + content changes)")
	else:
		for m in _fails:
			print("  FAIL: ", m)
		print("RESULT: FAIL (%d)" % _fails.size())
	quit()
