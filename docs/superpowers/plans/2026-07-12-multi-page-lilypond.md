# True Multi-Page LilyPond Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `MSScore notation: \lilypond` render **turnable pages** in the Godot app (like the Verovio paged path) instead of one cropped image, driven by `pageBreaks` and page-height auto-fill, with the addressable cursor following across pages.

**Architecture:** Mirror the existing Verovio paged path. `lily_render.py` gains a `--paged` mode that renders one SVG per page and crops each to content (uniform width). A new `MSNotationLilyPositions.finalize_paged` parses those pages into `{pages:[{texture,systems}], elements:[…page], page_count}`. `MSRenderQueue._submit_lily` gets a paged branch that calls `obj._on_pages_done(...)`. `MSScore.pr_emitSetup` stops forcing `paginate` off for LilyPond. The page-turn / cursor side of the notation object is already engine-agnostic and is **not touched**.

**Tech Stack:** Python 3 (LilyPond wrapper), GDScript (Godot 4.7), SuperCollider (msscore quark), LilyPond ≥ 2.24, pytest, Godot headless self-tests, whelk schelp generator.

**Two repositories:**
- **MusicScene** (`D:\Projects\MusicScene`): `lily_render.py`, `MSRenderQueue.gd`, `MSNotationLilyPositions.gd`, tests, example, CHANGELOG/version files. Branch already created: `multi-page-lilypond`.
- **msscore quark** (`C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore`): its own git repo — `Classes/MSScore.sc`, `HelpSource/Classes/MSScore.schelp`, `msscore.quark`. Commit there separately.

**Standing constraints (do not violate):**
- Commit only the files a task names. **Never** stage/commit `examples/supercollider/example_lilypond.scd` or `example_lyrics.scd` — they carry the user's uncommitted working-tree edits. (This is why Task 5 adds a *new* example file rather than editing `example_lilypond.scd`.)
- **Never** `git push` and **never** `git tag` — the user does that, across repos, in dependency order.
- When editing a quark `.sc` file, keep the whelk doc comments current AND regenerate + parse-verify the schelp (Task 4).

---

## File Structure

| File | Repo | Responsibility | Change |
|------|------|----------------|--------|
| `addons/musicscene/tools/lily_render.py` | MusicScene | Render LilyPond → cropped SVG(s) for ThorVG | **Modify**: add `--paged` multi-page mode |
| `addons/musicscene/notation/MSNotationLilyPositions.gd` | MusicScene | Parse LilyPond SVG → addressable elements/systems | **Modify**: add `finalize_paged` + `_page_cropped_svgs` |
| `addons/musicscene/notation/MSRenderQueue.gd` | MusicScene | Launch engraver, dispatch finish | **Modify**: `_submit_lily` paged branch + `_finish_lily_paged` + job dispatch |
| `Classes/MSScore.sc` | msscore | Emit OSC setup | **Modify**: `pr_emitSetup` paginate for LilyPond + `pr_paginateInt` + whelk docs |
| `tools/verovio/test_lily_render.py` | MusicScene | pytest for the wrapper | **Modify**: add paged multipage test |
| `tools/test_lily_paged.gd` | MusicScene | Godot self-test for `finalize_paged` | **Create** |
| `tools/test_lily_paged_finish.gd` | MusicScene | Godot self-test for `_finish_lily_paged` fallback | **Create** |
| `tools/msscore/test_lilypond.py` | MusicScene | pytest (sclang) for MSScore | **Modify**: add paginate-int test |
| `examples/supercollider/example_lilypond_multipage.scd` | MusicScene | Runnable multi-page demo | **Create** |
| `CHANGELOG.md`, `addons/musicscene/plugin.cfg`, `addons/musicscene/core/OscDispatcher.gd`, `README.md`, `TUTORIAL.md`, `ADVANCED.md` | MusicScene | Docs + version | **Modify** (Task 5) |
| `msscore.quark`, `HelpSource/Classes/MSScore.schelp` | msscore | Version + generated docs | **Modify** (Task 4) |

---

## Task 1: `lily_render.py` — add `--paged` multi-page mode

**Files:**
- Modify: `addons/musicscene/tools/lily_render.py`
- Test: `tools/verovio/test_lily_render.py`

The wrapper today converts every `\pageBreak` to `\break`, renders one tall page, and crops the whole thing to `<stem>.cropped.svg`. Paged mode must instead keep `\pageBreak`, inject a *finite* page height (from a `--paged <pageHeight>` arg), let LilyPond emit one SVG per page (`<stem>-1.svg`, `<stem>-2.svg`, …), and crop each page to content at a **uniform width**, writing `<stem>-1.cropped.svg`, `<stem>-2.cropped.svg`, …. If anything in the paged path fails it falls back to the existing single-image render.

- [ ] **Step 1: Write the failing test**

Add to `tools/verovio/test_lily_render.py` (after the existing test):

```python
@pytest.mark.skipif(not os.path.exists(LILYPOND), reason="LilyPond not installed (set $LILYPOND)")
def test_lily_render_paged_multipage():
    """--paged renders a score with an explicit \\pageBreak to one cropped SVG per page."""
    d = tempfile.mkdtemp(prefix="lily_paged_")
    try:
        ly = (
            '\\version "2.24.0"\n\\header { tagline = ##f }\n'
            '\\score { <<\n'
            '  \\new Staff \\new Voice = "v1" { c\'1 \\pageBreak d\'1 }\n'
            '>> }\n'
        )
        ly_path = os.path.join(d, "s.ly")
        with open(ly_path, "w", encoding="utf-8") as f:
            f.write(ly)
        stem = os.path.join(d, "out")
        r = subprocess.run([sys.executable, WRAPPER, LILYPOND, ly_path, stem, "--paged", "1200"],
                           capture_output=True, text=True, timeout=120)
        assert r.returncode == 0, r.stderr[-1000:]
        p1 = stem + "-1.cropped.svg"
        p2 = stem + "-2.cropped.svg"
        assert os.path.exists(p1), "no page 1 (%s)" % r.stdout
        assert os.path.exists(p2), "no page 2 (\\pageBreak did not split): %s" % r.stdout
        # Each page is a real cropped SVG that kept its point-and-click links.
        for p in (p1, p2):
            svg = open(p, encoding="utf-8").read()
            assert "viewBox" in svg
            assert "textedit" in svg, "point-and-click links lost on " + p
        # Uniform page width (so pages don't shift horizontally when turned).
        import re as _re
        def _w(path):
            m = _re.search(r'width="([-\d.]+)mm"', open(path, encoding="utf-8").read())
            return float(m.group(1)) if m else -1.0
        assert abs(_w(p1) - _w(p2)) < 0.01, "page widths differ (%s vs %s)" % (_w(p1), _w(p2))
    finally:
        shutil.rmtree(d, ignore_errors=True)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `py -m pytest tools/verovio/test_lily_render.py::test_lily_render_paged_multipage -q`
Expected: FAIL — the current wrapper ignores `--paged` (treats it as junk argv / crops to a single `out.cropped.svg`), so `out-2.cropped.svg` does not exist. (If LilyPond is absent the test SKIPS — run the remaining steps and verify locally where LilyPond is installed.)

- [ ] **Step 3: Rewrite `lily_render.py` with paged mode**

Replace the **entire** contents of `addons/musicscene/tools/lily_render.py` with:

```python
#!/usr/bin/env python3
"""Render a LilyPond source to cropped SVG(s) for the MusicScene notation preview.

Two jobs, both so the preview looks right in Godot's ThorVG rasteriser:

1. Vertical spacing. LilyPond's own ``-dcrop`` removes the vertical space between systems (a documented
   limitation), so several systems on one image clash. Instead we render a full page — where LilyPond
   spaces the systems correctly — and then crop the SVG's viewBox to the inked content ourselves. If
   anything about that path fails we fall back to plain ``-dcrop`` (systems may clash, render succeeds).

2. Text. LilyPond emits lyrics, dynamics and tuplet numbers as SVG ``<text>``, which ThorVG cannot draw.
   We outline them to ``<path>`` via the shared svg_text_to_path module (best-effort: a missing fontTools
   only leaves the text unoutlined, never blank).

Two modes:
  * Single image (default): one tall page, ``\\pageBreak`` -> ``\\break``, one ``<stem>.cropped.svg``.
  * Paged (``--paged <pageHeight>``): keep ``\\pageBreak``, a finite page height from <pageHeight>, so
    LilyPond emits one SVG per page; each is cropped to content at a uniform width, written
    ``<stem>-1.cropped.svg``, ``<stem>-2.cropped.svg``, ...  If the paged path fails we fall back to the
    single-image render (so a render is never blank).

Usage:  python lily_render.py <lilypond_exe> <input.ly> <output_stem> [--paged <pageHeight>]
"""
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
# A page tall enough for any realistic single-image score (empty space below is cropped away), with a
# controlled inter-system distance — full-page layout respects system-system-spacing (unlike -dcrop).
FULLPAGE_PAPER = ("\n\\paper { page-count = #1 paper-height = 12000\\mm ragged-bottom = ##t"
                  " ragged-last-bottom = ##t system-system-spacing.basic-distance = #12"
                  " system-system-spacing.padding = #2 }\n")
# Paged mode uses a finite page height derived from the Verovio-style pageHeight (units). The default
# 1200 maps to ~250 mm (A4-ish content height); smaller pageHeight => shorter pages => more pages.
PAGED_SPACING = ("ragged-bottom = ##t ragged-last-bottom = ##t"
                 " system-system-spacing.basic-distance = #12 system-system-spacing.padding = #2")
CROP_MARGIN = 3.0   # viewBox units of slack so glyph/stem/ledger edges are never clipped


def _translate(el):
    m = re.search(r"translate\(([-\d.eE]+)[ ,]+([-\d.eE]+)\)", el.get("transform", ""))
    return (float(m.group(1)), float(m.group(2))) if m else (0.0, 0.0)


def _content_bbox(root):
    """Bounding box (minx, miny, maxx, maxy) of the inked content, accumulating <g translate>.
    Rects/lines/polygons are exact; glyph/text/use are taken at their placement point (CROP_MARGIN
    covers their small extent). Returns None if nothing was found."""
    box = [1e18, 1e18, -1e18, -1e18]

    def add(x, y):
        if x < box[0]: box[0] = x
        if y < box[1]: box[1] = y
        if x > box[2]: box[2] = x
        if y > box[3]: box[3] = y

    def walk(el, ax, ay):
        for ch in el:
            tag = ch.tag.split("}")[-1]
            dx, dy = _translate(ch)
            nx, ny = ax + dx, ay + dy
            if tag == "rect":
                x = float(ch.get("x", 0)); y = float(ch.get("y", 0))
                add(nx + x, ny + y); add(nx + x + float(ch.get("width", 0)), ny + y + float(ch.get("height", 0)))
            elif tag == "line":
                add(nx + float(ch.get("x1", 0)), ny + float(ch.get("y1", 0)))
                add(nx + float(ch.get("x2", 0)), ny + float(ch.get("y2", 0)))
            elif tag == "polygon":
                for a, b in re.findall(r"([-\d.eE]+)[ ,]([-\d.eE]+)", ch.get("points", "")):
                    add(nx + float(a), ny + float(b))
            elif tag in ("path", "text", "use"):
                add(nx, ny)
            walk(ch, nx, ny)

    walk(root, 0.0, 0.0)
    if box[0] > box[2] or box[1] > box[3]:
        return None
    return tuple(box)


def _measure(svg_path):
    """Parse svg_path and return (tree, root, minx, miny, maxx, maxy, mm_per_unit) or None."""
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    tree = ET.parse(svg_path)
    root = tree.getroot()
    vb = (root.get("viewBox") or "").split()
    width_mm = float(re.sub(r"[a-z]+$", "", root.get("width", "0")))
    if len(vb) != 4 or width_mm <= 0.0:
        return None
    denom = float(vb[2])
    mm_per_unit = width_mm / denom if denom else 0.0
    bbox = _content_bbox(root)
    if bbox is None or mm_per_unit <= 0.0:
        return None
    return (tree, root, bbox[0], bbox[1], bbox[2], bbox[3], mm_per_unit)


def _write_cropped(meas, out_path, view_width=None):
    """Rewrite a measured SVG's viewBox/width/height to its content (plus margin) and save. When
    view_width (in viewBox units, margins included) is given, use it as the viewBox width instead of the
    content width — so several pages share one width and stay left-aligned. Returns True on success."""
    tree, root, minx, miny, maxx, maxy, mm_per_unit = meas
    m = CROP_MARGIN
    x0, y0 = minx - m, miny - m
    w = ((maxx - minx) + 2 * m) if view_width is None else view_width
    h = (maxy - miny) + 2 * m
    if w <= 0.0 or h <= 0.0:
        return False
    root.set("viewBox", "%.4f %.4f %.4f %.4f" % (x0, y0, w, h))
    root.set("width", "%.4fmm" % (w * mm_per_unit))
    root.set("height", "%.4fmm" % (h * mm_per_unit))
    tree.write(out_path, encoding="unicode")
    return True


def _crop_to_content(svg_path, out_path):
    """Single-image crop: viewBox -> content, saved to out_path. Returns True on success."""
    meas = _measure(svg_path)
    return bool(meas) and _write_cropped(meas, out_path)


def _crop_pages(page_svgs, stem):
    """Crop each page SVG to content at a uniform (max) width; write <stem>-<i>.cropped.svg (1-based).
    Returns the list of written paths, or [] if any page could not be measured (caller falls back)."""
    measured = [_measure(sp) for sp in page_svgs]
    if any(m is None for m in measured):
        return []
    common_w = max((mx - mnx) for (_t, _r, mnx, _mny, mx, _mxy, _mm) in measured) + 2 * CROP_MARGIN
    out_paths = []
    for i, meas in enumerate(measured, start=1):
        out = "%s-%d.cropped.svg" % (stem, i)
        if not _write_cropped(meas, out, view_width=common_w):
            return []
        out_paths.append(out)
    return out_paths


def _text_to_path(cropped):
    """Best-effort: outline <text> to <path> in place (never fails the render)."""
    if not os.path.exists(cropped):
        return
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from svg_text_to_path import svg_text_to_path
        with open(cropped, encoding="utf-8") as f:
            svg = f.read()
        with open(cropped, "w", encoding="utf-8") as f:
            f.write(svg_text_to_path(svg))
    except Exception as e:
        sys.stderr.write("lily_render: text->path skipped: %s\n" % e)


def _run(lilypond, args):
    return subprocess.run([lilypond] + args).returncode


def _page_svgs(stem):
    """LilyPond writes <stem>-1.svg.. for multi-page and <stem>.svg for a single page. Return the list
    of page SVGs in order (possibly one), or [] if none were produced."""
    if os.path.exists(stem + "-1.svg"):
        pages, i = [], 1
        while os.path.exists("%s-%d.svg" % (stem, i)):
            pages.append("%s-%d.svg" % (stem, i)); i += 1
        return pages
    if os.path.exists(stem + ".svg"):
        return [stem + ".svg"]
    return []


def _render_paged(lilypond, src, stem, paged_height):
    """Render src (with \\pageBreak kept) onto finite pages and crop each. Returns written cropped paths,
    or [] on any failure (so the caller falls back to a single image)."""
    mm = max(80.0, paged_height * 250.0 / 1200.0)
    paper = "\n\\paper { paper-height = %.1f\\mm %s }\n" % (mm, PAGED_SPACING)
    render_ly = stem + ".render.ly"
    try:
        with open(render_ly, "w", encoding="utf-8") as f:
            f.write(src + paper)
    except Exception as e:
        sys.stderr.write("lily_render: could not write paged source (%s)\n" % e)
        return []
    if _run(lilypond, ["-dbackend=svg", "-o", stem, render_ly]) != 0:
        return []
    pages = _page_svgs(stem)
    if not pages:
        return []
    return _crop_pages(pages, stem)


def _render_single(lilypond, raw, inp, stem):
    """Existing single-image behaviour: \\pageBreak -> \\break, full page + custom crop, else -dcrop."""
    cropped = stem + ".cropped.svg"
    src = None
    preview = inp
    if raw is not None:
        src = raw.replace("\\pageBreak", "\\break")
        preview = stem + ".preview.ly"
        try:
            with open(preview, "w", encoding="utf-8") as f:
                f.write(src)
        except Exception as e:
            sys.stderr.write("lily_render: could not write preview (%s)\n" % e)

    ok = False
    if src is not None:
        try:
            render_ly = stem + ".render.ly"
            with open(render_ly, "w", encoding="utf-8") as f:
                f.write(src + FULLPAGE_PAPER)
            if _run(lilypond, ["-dbackend=svg", "-o", stem, render_ly]) == 0:
                full = stem + ".svg"
                if not os.path.exists(full) and os.path.exists(stem + "-1.svg"):
                    full = stem + "-1.svg"
                if os.path.exists(full):
                    ok = _crop_to_content(full, cropped)
        except Exception as e:
            sys.stderr.write("lily_render: full-page crop failed (%s); using -dcrop\n" % e)
            ok = False

    if not ok:
        rc = _run(lilypond, ["-dbackend=svg", "-dcrop=#t", "-o", stem, preview])
        if rc != 0:
            return rc
        if not os.path.exists(cropped):
            sys.stderr.write("lily_render: no cropped SVG produced\n")
            return 1

    _text_to_path(cropped)
    sys.stdout.write("lily_render: wrote %s (%s)\n" % (cropped, "full-page crop" if ok else "-dcrop fallback"))
    return 0


def main() -> int:
    argv = sys.argv[1:]
    paged_height = None
    if "--paged" in argv:
        i = argv.index("--paged")
        try:
            paged_height = float(argv[i + 1])
        except (IndexError, ValueError):
            sys.stderr.write("lily_render: --paged needs a numeric page height\n")
            return 2
        argv = argv[:i] + argv[i + 2:]
    if len(argv) < 3:
        sys.stderr.write("lily_render: usage: lily_render.py <lilypond_exe> <input.ly> <output_stem> "
                         "[--paged <pageHeight>]\n")
        return 2
    lilypond, inp, stem = argv[0], argv[1], argv[2]

    try:
        with open(inp, encoding="utf-8") as f:
            raw = f.read()
    except Exception as e:
        raw = None
        sys.stderr.write("lily_render: could not read source (%s)\n" % e)

    if paged_height is not None and raw is not None:
        outs = _render_paged(lilypond, raw, stem, paged_height)   # keeps \pageBreak
        if outs:
            for o in outs:
                _text_to_path(o)
            sys.stdout.write("lily_render: wrote %d page(s) %s-N.cropped.svg\n" % (len(outs), stem))
            return 0
        sys.stderr.write("lily_render: paged render failed; falling back to single image\n")

    return _render_single(lilypond, raw, inp, stem)


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the paged test to verify it passes**

Run: `py -m pytest tools/verovio/test_lily_render.py::test_lily_render_paged_multipage -q`
Expected: PASS (two cropped pages, both with `textedit`, equal widths). SKIPS cleanly if LilyPond is absent.

- [ ] **Step 5: Run the existing wrapper test to verify no regression**

Run: `py -m pytest tools/verovio/test_lily_render.py -q`
Expected: both tests PASS (single-image behaviour unchanged) or SKIP if LilyPond is absent.

- [ ] **Step 6: Commit**

```bash
git add addons/musicscene/tools/lily_render.py tools/verovio/test_lily_render.py
git commit -m "feat(notation): lily_render.py --paged renders one cropped SVG per page

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `MSNotationLilyPositions.finalize_paged` + `_page_cropped_svgs`

**Files:**
- Modify: `addons/musicscene/notation/MSNotationLilyPositions.gd`
- Test: `tools/test_lily_paged.gd` (create)

`finalize_paged` mirrors `MSNotationVerovioPositions.finalize_paged` but without a timemap (LilyPond elements carry their own `data-when`/textedit, parsed by the existing `_parse`). Because `lily_render.py` already cropped each page, no raster re-crop/rescale is needed here — the parsed `u`/`v` are already in cropped space.

- [ ] **Step 1: Write the failing test**

Create `tools/test_lily_paged.gd`:

```gdscript
extends SceneTree
## Regression: LilyPond multi-page (paginate). finalize_paged must enumerate <stem>-N.cropped.svg in
## NUMERIC order, parse each page, stamp every element with its 1-based `page`, and return per-page
## systems. _page_cropped_svgs is tested purely (numeric vs lexical sort); finalize_paged is tested over
## two hand-written cropped-SVG fixtures (rasterised headless by ThorVG). Prints fail=0 on success.
const Lily := preload("res://addons/musicscene/notation/MSNotationLilyPositions.gd")

func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(body)
	f.close()

# One page: two noteheads (translate g's inside <a textedit>, each carrying data-when). A filled path
# gives ThorVG something to rasterise (a blank SVG would rasterise empty and fail).
func _page(w0: float, w1: float) -> String:
	return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"'
		+ ' width="100mm" height="40mm" viewBox="0 0 100 40">'
		+ '<a xlink:href="textedit:///tmp/x.ly:5:2:2"><g transform="translate(10, 20)" data-when="%f">'
		+ '<path d="M0 0 h4 v4 h-4 z" fill="black"/></g></a>'
		+ '<a xlink:href="textedit:///tmp/x.ly:5:8:8"><g transform="translate(60, 20)" data-when="%f">'
		+ '<path d="M0 0 h4 v4 h-4 z" fill="black"/></g></a></svg>') % [w0, w1]

func _init() -> void:
	var dir := ProjectSettings.globalize_path("user://")
	var fails := 0

	# --- A) _page_cropped_svgs enumerates in numeric (not lexical) order -----------------------------
	var estem := dir.path_join("lypg_enum")
	for n in [1, 2, 10]:
		_write("%s-%d.cropped.svg" % [estem, n], "<svg/>")
	var got: Array = Lily._page_cropped_svgs(estem)
	var order := got.map(func(p): return int(p.get_file().trim_prefix("lypg_enum-").trim_suffix(".cropped.svg")))
	if order != [1, 2, 10]:
		fails += 1; print("FAIL: page order ", order, " (expected [1,2,10] — numeric, not lexical)")

	# --- B) finalize_paged over two fixture pages ---------------------------------------------------
	var stem := dir.path_join("lypg_fin")
	_write(stem + "-1.cropped.svg", _page(0.0, 0.25))
	_write(stem + "-2.cropped.svg", _page(0.5, 0.75))
	var res := Lily.finalize_paged(stem, {})
	if not res.ok:
		fails += 1; print("FAIL: finalize_paged: ", res.get("error", "?"))
	else:
		if int(res.page_count) != 2:
			fails += 1; print("FAIL: page_count ", res.page_count, " (expected 2)")
		if res.pages.size() != 2:
			fails += 1; print("FAIL: pages ", res.pages.size(), " (expected 2)")
		for e in res.elements:
			if not e.has("page"):
				fails += 1; print("FAIL: element missing `page`: ", e); break
		# elements are when-sorted; page-1 elements (when < 0.5) precede page-2 elements
		var pages_seq := res.elements.map(func(e): return int(e.page))
		if pages_seq != [1, 1, 2, 2]:
			fails += 1; print("FAIL: page sequence ", pages_seq, " (expected [1,1,2,2])")
		if res.pages.size() == 2 and (res.pages[0].systems.is_empty() or res.pages[1].systems.is_empty()):
			fails += 1; print("FAIL: a page has no systems")

	print("fail=", fails)
	quit()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `& "<godot>" --headless --path . --script res://tools/test_lily_paged.gd` (use the Godot binary path from memory `godot-binary-path`).
Expected: FAIL — `finalize_paged` / `_page_cropped_svgs` do not exist yet (script/parse error or missing-method). Prints a nonzero `fail=` or errors.

- [ ] **Step 3: Add `finalize_paged` and `_page_cropped_svgs`**

In `addons/musicscene/notation/MSNotationLilyPositions.gd`, insert after `finalize` (i.e. after its closing line ~44, before `_build_systems`):

```gdscript

## Multi-page (paginated) variant. lily_render.py --paged already produced one cropped SVG per page
## (<stem>-1.cropped.svg, <stem>-2.cropped.svg, ...); enumerate them in numeric order, rasterize + parse
## each, group into per-page staff-systems, and tag every element with its 1-based `page`. Returns
## {ok, pages:[{texture, systems}], elements:[{index, when, line, char, u, v, sys, page}], page_count}.
## Mirrors MSNotationVerovioPositions.finalize_paged, but LilyPond carries its own data-when/textedit so
## there is no timemap, and pages are pre-cropped so no raster re-crop/rescale is needed.
static func finalize_paged(stem: String, options: Dictionary = {}) -> Dictionary:
	var page_paths := _page_cropped_svgs(stem)
	if page_paths.is_empty():
		return {"ok": false, "error": "lily addressable: no page SVGs at " + stem + "-N.cropped.svg"}
	var pages: Array = []
	var elements: Array = []
	for pi in page_paths.size():
		var svg_path: String = page_paths[pi]
		var res = SvgBackend.render({"kind": "path", "path": svg_path, "text": "", "bytes": PackedByteArray()}, 1, options)
		if not res.ok:
			return {"ok": false, "error": "lily addressable: " + res.error}
		var page_elements := _parse(svg_path)
		var systems := _build_systems(page_elements)   # stamps each element's `sys` within this page
		for e in page_elements:
			e["page"] = pi + 1
		pages.append({"texture": res.texture, "systems": systems})
		elements.append_array(page_elements)
	elements.sort_custom(func(a, b): return a.when < b.when)
	for i in elements.size():
		elements[i].index = i
	return {"ok": true, "pages": pages, "elements": elements, "page_count": pages.size()}


## Enumerate <stem>-1.cropped.svg, <stem>-2.cropped.svg, ... in NUMERIC order (a lexical sort would put
## -10 before -2). Returns absolute/user:// paths, or [] if none exist.
static func _page_cropped_svgs(stem: String) -> Array:
	var dir := stem.get_base_dir()
	var base := stem.get_file()
	var da := DirAccess.open(dir)
	if da == null:
		return []
	var found: Array = []
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if fn.begins_with(base + "-") and fn.ends_with(".cropped.svg"):
			var num := fn.substr((base + "-").length())
			num = num.left(num.length() - ".cropped.svg".length())
			if num.is_valid_int():
				found.append({"n": int(num), "path": dir.path_join(fn)})
		fn = da.get_next()
	da.list_dir_end()
	found.sort_custom(func(a, b): return a.n < b.n)
	var out: Array = []
	for f in found:
		out.append(f.path)
	return out
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `& "<godot>" --headless --path . --script res://tools/test_lily_paged.gd`
Expected: `fail=0`.

- [ ] **Step 5: Commit**

```bash
git add addons/musicscene/notation/MSNotationLilyPositions.gd tools/test_lily_paged.gd
git commit -m "feat(notation): finalize_paged parses LilyPond pages into turnable pages

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `MSRenderQueue` paged branch + `_finish_lily_paged`

**Files:**
- Modify: `addons/musicscene/notation/MSRenderQueue.gd`
- Test: `tools/test_lily_paged_finish.gd` (create)

`_submit_lily` must, when `options.paginate` is set (and a Python interpreter is available to run the wrapper), launch `lily_render.py --paged <page_height>`, mark the job `paged`, and on completion call `_finish_lily_paged` → `obj._on_pages_done(...)`. Because the cache key already folds the full `options` dict (which carries `paginate` and `page_height`, exactly as the Verovio path reads them), a changed score / pageHeight / paginate flag yields a fresh stem — no stale page files are reused. If the paged render fell back to a single image (no `-1.cropped.svg`), `_finish_lily_paged` degrades to the single-image finish rather than erroring blank.

- [ ] **Step 1: Write the failing test**

Create `tools/test_lily_paged_finish.gd`:

```gdscript
extends SceneTree
## Regression: _finish_lily_paged must not error blank when the paged render produced nothing. With
## neither <stem>-1.cropped.svg nor <stem>.cropped.svg present it reports a render failure (not a crash,
## not a silent success). Pure — no LilyPond/Python/render. Prints fail=0 on success.
const RenderQueue := preload("res://addons/musicscene/notation/MSRenderQueue.gd")

class StubObj:
	extends RefCounted
	var failed := ""
	var paged := false
	var single := false
	func _on_render_failed(msg: String) -> void: failed = msg
	func _on_pages_done(_p, _e, _n) -> void: paged = true
	func _on_elements_done(_t, _e, _s = []) -> void: single = true

func _init() -> void:
	var q = RenderQueue.new()
	var obj := StubObj.new()
	var fails := 0

	# A stem that has no page files and no single cropped file -> must report failure.
	var stem := ProjectSettings.globalize_path("user://lypg_missing_stem")
	q._finish_lily_paged(obj, stem, {}, -1)
	if obj.failed == "":
		fails += 1; print("FAIL: expected a render failure for a stem with no pages")
	if obj.paged:
		fails += 1; print("FAIL: _on_pages_done fired despite no pages")

	print("failed_msg=", obj.failed)
	print("fail=", fails)
	q.free()
	quit()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `& "<godot>" --headless --path . --script res://tools/test_lily_paged_finish.gd`
Expected: FAIL — `_finish_lily_paged` does not exist (missing-method / parse error).

- [ ] **Step 3: Add `_finish_lily_paged`**

In `addons/musicscene/notation/MSRenderQueue.gd`, insert after `_finish_lily` (after line ~165):

```gdscript

func _finish_lily_paged(obj, stem_user: String, options: Dictionary, pid: int = -1) -> void:
	# The paged wrapper writes <stem>-1.cropped.svg..; if it fell back to a single image there is only
	# <stem>.cropped.svg — degrade to the single-image finish rather than reporting blank.
	if not FileAccess.file_exists(stem_user + "-1.cropped.svg"):
		var single := stem_user + ".cropped.svg"
		if FileAccess.file_exists(single):
			_finish_lily(obj, single, options, pid)
			return
		obj._on_render_failed("lily addressable: no pages at " + stem_user + "-N.cropped.svg" + _exit_note(pid))
		return
	var res := LilyPositions.finalize_paged(stem_user, options)
	if res.ok:
		obj._on_pages_done(res.pages, res.elements, res.page_count)
	else:
		obj._on_render_failed(res.error + _exit_note(pid))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `& "<godot>" --headless --path . --script res://tools/test_lily_paged_finish.gd`
Expected: `fail=0` and `failed_msg=` shows the "no pages" message.

- [ ] **Step 5: Wire the paged branch into `_submit_lily`**

In `addons/musicscene/notation/MSRenderQueue.gd`, replace the block from the cache-check through the `_jobs.append` at the end of `_submit_lily` (current lines ~124–157, starting at `var cropped_user := stem_user + ".cropped.svg"`) with:

```gdscript
	var cropped_user := stem_user + ".cropped.svg"

	# Paged (turnable pages) needs the wrapper to render N pages, so it requires a Python interpreter.
	# Without one, degrade to the single cropped image. paginate + page_height ride in `options`, which
	# Cache.key already folds into the stem — so a changed flag/height yields fresh page files.
	var paginate: bool = bool(options.get("paginate", false)) and t2p_py != ""
	var page_height: int = int(options.get("page_height", 1200))

	if paginate:
		if FileAccess.file_exists(stem_user + "-1.cropped.svg"):
			_finish_lily_paged(notation_obj, stem_user, options)
			return
	elif FileAccess.file_exists(cropped_user):
		_finish_lily(notation_obj, cropped_user, options)
		return

	var f := FileAccess.open(in_user, FileAccess.WRITE)
	if f == null:
		notation_obj._on_render_failed("addressable: cannot write temp LilyPond")
		return
	f.store_string(wrapped)
	f.close()

	var pid: int
	if t2p_py != "":
		# Run LilyPond via lily_render.py, which renders the cropped SVG(s) and outlines their <text> to
		# <path> so lyrics/dynamics/tuplet numbers show (ThorVG cannot draw SVG <text>). With paginate,
		# --paged makes it emit one cropped SVG per page.
		var wrapper := ProjectSettings.globalize_path("res://addons/musicscene/tools/lily_render.py")
		var wargs := [wrapper, exe, ProjectSettings.globalize_path(in_user), ProjectSettings.globalize_path(stem_user)]
		if paginate:
			wargs.append("--paged")
			wargs.append(str(page_height))
		pid = OS.create_process(t2p_py, wargs, false)
	else:
		# No fontTools Python available: render directly (LilyPond text stays invisible in ThorVG).
		pid = OS.create_process(exe, ["-dbackend=svg", "-dcrop=#t",
			"-o", ProjectSettings.globalize_path(stem_user), ProjectSettings.globalize_path(in_user)], false)
	if pid <= 0:
		notation_obj._on_render_failed("addressable: could not launch " + (t2p_py if t2p_py != "" else exe))
		return
	if ctx.verbose:
		print("[MusicSceneOSC] analyzing '%s' (lilypond%s%s) in background, pid %d"
			% [notation_obj.osc_id, (" +text2path" if t2p_py != "" else ""), (" /paged" if paginate else ""), pid])
	_jobs.append({
		"kind": "lyaddr", "pid": pid, "obj": notation_obj, "paged": paginate,
		"stem_user": stem_user, "cropped_user": cropped_user, "options": options, "start": Time.get_ticks_msec(),
	})
```

- [ ] **Step 6: Route the paged job in the poll loop**

In the same file, in `_process`, replace the `elif j.kind == "lyaddr":` branch (currently line ~296–297):

```gdscript
			elif j.kind == "lyaddr":
				_finish_lily(j.obj, j.cropped_user, j.options, j.pid)
```

with:

```gdscript
			elif j.kind == "lyaddr":
				if j.get("paged", false):
					_finish_lily_paged(j.obj, j.stem_user, j.options, j.pid)
				else:
					_finish_lily(j.obj, j.cropped_user, j.options, j.pid)
```

- [ ] **Step 7: Re-run the finish test + the paged parse test (no regression)**

Run: `& "<godot>" --headless --path . --script res://tools/test_lily_paged_finish.gd`
Expected: `fail=0`.
Run: `& "<godot>" --headless --path . --script res://tools/test_lily_paged.gd`
Expected: `fail=0`.

- [ ] **Step 8: Commit**

```bash
git add addons/musicscene/notation/MSRenderQueue.gd tools/test_lily_paged_finish.gd
git commit -m "feat(notation): _submit_lily paged branch -> _on_pages_done for LilyPond

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: MSScore — emit `paginate` for LilyPond (msscore quark repo)

**Files (msscore quark repo `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore`):**
- Modify: `Classes/MSScore.sc`
- Modify: `HelpSource/Classes/MSScore.schelp` (regenerated)
- Modify: `msscore.quark` (version)
- Test (MusicScene repo): `tools/msscore/test_lilypond.py`

`pr_emitSetup` currently forces pagination off for LilyPond. Change it to send `paginate` for both engines via a tiny testable helper `pr_paginateInt`, and update the whelk docs that claim LilyPond has no pagination.

- [ ] **Step 1: Write the failing test**

Add to `tools/msscore/test_lilypond.py`:

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lilypond_paginate_int():
    """LilyPond no longer forces pagination off: pr_paginateInt reflects the paginate flag for \\lilypond."""
    r = _run(r'''(
var on  = MSScore(voices: ["c5_4 e5"], clefs: [\treble], notation: \lilypond, paginate: true);
var off = MSScore(voices: ["c5_4 e5"], clefs: [\treble], notation: \lilypond, paginate: false);
("ON="  ++ on.pr_paginateInt.asString).postln;
("OFF=" ++ off.pr_paginateInt.asString).postln;
0.exit;
)''')
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "ON=1" in r.stdout, r.stdout[-1500:]
    assert "OFF=0" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `py -m pytest tools/msscore/test_lilypond.py::test_lilypond_paginate_int -q`
Expected: FAIL — `pr_paginateInt` does not exist (`doesNotUnderstand`). (SKIPS if sclang absent — verify locally.)

- [ ] **Step 3: Add `pr_paginateInt` and use it in `pr_emitSetup`**

In `Classes/MSScore.sc`, add the helper method (place it just before `pr_emitSetup`, after the `ly { ... }` accessor near line 440):

```supercollider
	/*
	[method.pr_paginateInt]
	description = "(private) the paginate flag as 1/0 for OSC. LilyPond now paginates like Verovio (no forced off)."
	[method.pr_paginateInt.returns]
	what = "1 if paginating, else 0"
	*/
	pr_paginateInt { ^paginate.if({ 1 }, { 0 }) }
```

Then change the paginate line inside `pr_emitSetup` (line ~457) from:

```supercollider
		snd.("/ms/scene/" ++ id, "paginate", (isLy.not and: { paginate }).if({ 1 }, { 0 }), pageHeight);
```

to:

```supercollider
		snd.("/ms/scene/" ++ id, "paginate", this.pr_paginateInt, pageHeight);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `py -m pytest tools/msscore/test_lilypond.py -q`
Expected: all tests PASS (or SKIP without sclang).

- [ ] **Step 5: Update the whelk docs that claim LilyPond can't paginate**

In `Classes/MSScore.sc`, update the three `notation`-related doc strings so they no longer say LilyPond is a single image / no page-turn. Replace exactly:

Line ~154 (`[method.notation]` description):
```supercollider
	description = "the notation engine: \\verovio (default; MEI rendered by Verovio, paginated) or \\lilypond (LilyPond source rendered by the LilyPond engraver as a single cropped image — no auto page-turn). For \\lilypond, set the musicscene/notation/engraver/lilypond project setting to your LilyPond executable."
```
with:
```supercollider
	description = "the notation engine: \\verovio (default; MEI rendered by Verovio) or \\lilypond (LilyPond source rendered by the LilyPond engraver). Both paginate into auto-turning pages (use paginate:/pageHeight:/pageBreaks:); \\lilypond additionally outlines its text (lyrics/dynamics/tuplet numbers) so it shows in Godot. For \\lilypond, set the musicscene/notation/engraver/lilypond project setting to your LilyPond executable."
```

Line ~322 (the `*new` arg doc for `notation`):
```supercollider
	notation = "the notation engine: \\verovio (default, MEI + Verovio, paginated) or \\lilypond (LilyPond, a single cropped image). For \\lilypond set the musicscene/notation/engraver/lilypond project setting."
```
with:
```supercollider
	notation = "the notation engine: \\verovio (default, MEI + Verovio) or \\lilypond (LilyPond). Both paginate into auto-turning pages. For \\lilypond set the musicscene/notation/engraver/lilypond project setting."
```

Line ~371 (the inline `init` comment):
```supercollider
		notation = ntn ? \verovio;                          // \verovio (MEI, paginated) or \lilypond (single cropped image)
```
with:
```supercollider
		notation = ntn ? \verovio;                          // \verovio (MEI) or \lilypond — both paginate into auto-turning pages
```

- [ ] **Step 6: Regenerate and parse-verify the schelp**

Regenerate: run `gendoc.bat` in the msscore quark root.
```bash
cd "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" && cmd //c gendoc.bat
```
Expected: prints `Done.` and rewrites `HelpSource/Classes/MSScore.schelp`.

Parse-verify the regenerated schelp mentions the new wording and contains no stray tag errors:
```bash
grep -c "both paginate into auto-turning pages" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore/HelpSource/Classes/MSScore.schelp"
```
Expected: ≥ 1. (If sclang is handy, additionally `SCDoc.parseFileFull` on the file must not raise; otherwise the whelk run succeeding is the parse gate.)

- [ ] **Step 7: Bump the msscore quark version**

In `msscore.quark`, change `version: "0.6.0",` to `version: "0.7.0",`.

- [ ] **Step 8: Commit (in the msscore quark repo)**

```bash
cd "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore"
git add Classes/MSScore.sc HelpSource/Classes/MSScore.schelp msscore.quark
git commit -m "feat: MSScore notation:\\lilypond paginates into turnable pages

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Then return to the MusicScene repo and commit the test there:
```bash
cd "D:/Projects/MusicScene"
git add tools/msscore/test_lilypond.py
git commit -m "test(msscore): LilyPond honours the paginate flag (pr_paginateInt)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Runnable example + docs + version sync

**Files (MusicScene repo):**
- Create: `examples/supercollider/example_lilypond_multipage.scd`
- Modify: `CHANGELOG.md`
- Modify: `addons/musicscene/plugin.cfg`
- Modify: `addons/musicscene/core/OscDispatcher.gd`
- Modify: `README.md`, `TUTORIAL.md`, `ADVANCED.md`

> **Version decision:** this plan cuts MusicScene **0.20.0** (msscore **0.7.0** from Task 4). If you would rather fold multi-page into the still-unreleased **0.19.0** section instead, use `0.19.0` everywhere below and skip the plugin.cfg/OscDispatcher bumps (they are already `0.19.0`). Pick one before running this task.

A dedicated new example file is used (not an edit of `example_lilypond.scd`) because that file holds the user's uncommitted edits, which must never be staged.

- [ ] **Step 1: Create the runnable multi-page example**

Create `examples/supercollider/example_lilypond_multipage.scd`:

```supercollider
// example_lilypond_multipage.scd
// -----------------------------------------------------------------------------
// True multi-page LilyPond in the app. `notation: \lilypond` now paginates into
// turnable pages exactly like the Verovio path: a small `pageHeight` fills pages
// by height, and `pageBreaks` force a new page at the listed bars. `nextPage` /
// `prevPage` / `page(n)` flip pages; the follow cursor auto-turns across pages.
//
// Requires the `musicscene/notation/engraver/lilypond` project setting pointing at
// your LilyPond executable, and a fontTools-capable Python (reused from the Verovio
// engraver) so LilyPond's text is outlined for ThorVG.
// -----------------------------------------------------------------------------

// Part A — page-fill by height: a long single line, small pageHeight => several pages.
(
s.waitForBoot({
    ~score = MSScore(
        voices: [ (1..48).collect({ |i| ["c5","e5","g5","a5","f5","d5"].wrapAt(i) ++ "_8" }).join(" ") ],
        clefs:  [ \treble ],
        notation: \lilypond,
        paginate: true, pageHeight: 320,     // small page => multiple auto-turning pages
        tempo: 96, scale: 1.0, instruments: [\default]
    );
});
)

// Part B — explicit page breaks: a new PAGE at bars 3 and 5, still with the cursor.
(
s.waitForBoot({
    ~score = MSScore(
        voices: [ "c5_4 e5 g5 e5 d5_4 f5 a5 f5 e5_4 g5 b5 g5 f5_4 a5 c6 a5 g5_1" ],
        clefs:  [ \treble ],
        notation: \lilypond,
        paginate: true, pageHeight: 900,
        systemBreaks: [2],                    // new line at bar 2
        pageBreaks:   [3, 5],                 // new page at bars 3 and 5
        tempo: 92, scale: 1.0, instruments: [\default]
    );
});
)

// Part C — display only (no cursor, no playback): show page 1, then flip pages.
(
~score = MSScore(
    voices: [ (1..48).collect({ |i| ["c5","e5","g5","a5","f5","d5"].wrapAt(i) ++ "_8" }).join(" ") ],
    clefs:  [ \treble ],
    notation: \lilypond,
    paginate: true, pageHeight: 320,
    scale: 1.0, instruments: [\default]
);
~score.showPage(1);                           // engrave + show page 1 (no sound, no cursor)
)
// ~score.nextPage;  // -> page 2
// ~score.prevPage;  // -> back
```

- [ ] **Step 2: Verify the example generates LilyPond without error**

Run (sclang; skips the boot/OSC by just exercising the `.ly` builder the example relies on):
```bash
sclang -e '(var s = MSScore(voices: ["c5_4 e5 g5 e5 d5_4 f5"], clefs: [\treble], notation: \lilypond, pageBreaks: [3], paginate: true); (s.ly.contains("\\pageBreak")).if({ "HASPB".postln }, { "NOPB".postln }); 0.exit;)'
```
Expected: prints `HASPB` (the example's `pageBreaks` reach the LilyPond source). If sclang is unavailable, load `example_lilypond_multipage.scd` in the IDE against a running MusicScene and confirm pages turn.

- [ ] **Step 3: Add the CHANGELOG entry**

In `CHANGELOG.md`, under `## [Unreleased]`, add (and, if cutting 0.20.0, rename the header to `## [0.20.0] — 2026-07-12`):

```markdown
### Added
- **True multi-page LilyPond in the app.** `MSScore(..., notation: \lilypond)` now paginates into
  auto-turning pages like the Verovio path — `pageHeight` fills pages by height and `pageBreaks` force
  page boundaries. `lily_render.py --paged` renders one cropped SVG per page (uniform width) and
  `MSNotationLilyPositions.finalize_paged` parses them into `_on_pages_done`, so `nextPage`/`prevPage`/
  `page(n)` and the follow cursor work across LilyPond pages. `paginate: false` still shows one cropped
  image.

### Changed
- LilyPond addressable rendering is no longer forced to a single image; `MSScore.pr_emitSetup` sends
  `paginate` for both engines. Requires msscore ≥ 0.7.0.
```

- [ ] **Step 4: Bump the MusicScene version (only if cutting 0.20.0)**

In `addons/musicscene/plugin.cfg`, change `version="0.19.0"` to `version="0.20.0"`.
In `addons/musicscene/core/OscDispatcher.gd` line 9, change `const MS_VERSION := "0.19.0"` to `const MS_VERSION := "0.20.0"`.

- [ ] **Step 5: Update README / TUTORIAL / ADVANCED**

Search each for LilyPond pagination wording that says "single cropped image" / "no auto page-turn" and update it to state LilyPond now paginates like Verovio. Run:
```bash
grep -rn -i "single cropped image\|no auto page-turn\|lilypond.*single" README.md TUTORIAL.md ADVANCED.md
```
For each hit, edit the sentence to say LilyPond paginates into auto-turning pages (use `paginate:`/`pageHeight:`/`pageBreaks:`), matching the CHANGELOG wording. If a doc lists engine capabilities in a table, flip LilyPond's "pagination" cell to supported. (If a file has no such wording, leave it.)

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md addons/musicscene/plugin.cfg addons/musicscene/core/OscDispatcher.gd README.md TUTORIAL.md ADVANCED.md examples/supercollider/example_lilypond_multipage.scd
git commit -m "docs+example: multi-page LilyPond; MusicScene 0.20.0

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] **Run the full pytest suite:** `py -m pytest tools/ -q` — all pass or skip (no failures).
- [ ] **Run the Godot self-tests:** the two new scripts plus the existing LilyPond ones print `fail=0`:
  - `res://tools/test_lily_paged.gd`
  - `res://tools/test_lily_paged_finish.gd`
  - `res://tools/test_lily_systems.gd`
  - `res://tools/test_lily_engraver_alias.gd`
  - `res://tools/test_lily_text2path.gd`
  - `res://tools/test_notation_lilypond.gd` (skips without LilyPond)
- [ ] **Manual smoke (real project):** copy `addons/musicscene` into the Godot test project, run `example_lilypond_multipage.scd`, confirm several pages that turn and a cursor that auto-turns across pages.
- [ ] **Left untouched:** `git status` shows `examples/supercollider/example_lilypond.scd` and `example_lyrics.scd` still only carry the user's edits (never staged by this work).
- [ ] Hand off to the user for push + tag across repos (msscore 0.7.0 → MusicScene 0.20.0), in dependency order. Do **not** push or tag.

---

## Self-Review notes

- **Spec coverage:** lily_render paged mode (Task 1) ✓; finalize_paged + `_page_cropped_svgs` (Task 2) ✓; `_submit_lily` paged branch + `_finish_lily_paged` + dispatch (Task 3) ✓; MSScore paginate + docs/schelp (Task 4) ✓; pageHeight→mm mapping (Task 1 `_render_paged`, `max(80, h*250/1200)`) ✓; cache strategy = fold paginate+pageHeight via existing `options` in `Cache.key` (Task 3 note) ✓; uniform page width (Task 1 `_crop_pages` common_w) ✓; fallback to single image (Task 1 `_render_paged` → `_render_single`; Task 3 `_finish_lily_paged` single degrade) ✓; example (Task 5, new file) ✓; tests incl. CI-safe numeric-sort + fixture parse ✓.
- **Type consistency:** `finalize_paged` returns `{ok, pages:[{texture, systems}], elements, page_count}`; `_finish_lily_paged` reads `res.pages/res.elements/res.page_count` and calls `obj._on_pages_done(pages, elements, page_count)` — matches the engine-agnostic Verovio contract. Job dict keys (`paged`, `stem_user`, `cropped_user`) are set in `_submit_lily` and read in `_process`/`_finish_lily_paged`. Wrapper arg `--paged <pageHeight>` is emitted in `_submit_lily` and parsed in `lily_render.main`.
- **No placeholders:** every code step shows complete code; the only deferred value is the empirically-tuned pageHeight factor, given a concrete starting formula.
