# Verovio SVG text → path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Verovio lyrics (and all Verovio `<text>`) visible in the Godot notation preview by converting SVG `<text>` to `<path>` glyph outlines, which Godot's ThorVG rasterizer renders (it does not render `<text>`).

**Architecture:** A new `--text-to-path` flag on the bundled `verovio_render.py` runs a self-contained `svg_text_to_path.py` post-process: it parses the Verovio `<style>` CSS for weight/italic classes, walks the SVG tree, and rewrites each `<text>` into filled `<path>` outlines using bundled Tinos faces (Times-metric), picking Regular/Bold/Italic from the element's ancestor CSS class. On any failure it returns the SVG unchanged so a render never breaks. The Godot builtin engraver command adds the flag.

**Tech Stack:** Python 3 + `fontTools` (installed 4.61.1), `xml.etree.ElementTree`; Godot 4.7 headless self-test; a bundled TTF trio; pytest via `py`.

**Spec:** `docs/superpowers/specs/2026-07-10-verovio-text-to-path-design.md`

---

## Repos, branches & conventions

- **All work is in the MusicScene repo** `D:\Projects\MusicScene`, on the EXISTING branch `feature/panola-lyrics` (already checked out; this feature builds on the lyrics work). Do NOT create a new branch, do NOT switch branches.
- Bash tool = Git Bash. Use `py` (not `python`). Godot console binary: `D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`. sclang: `C:\Program Files\SuperCollider-3.14.1\sclang.exe`.
- **Commit only when executing this plan** (that IS the confirmation). End commit messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do NOT push.
- Python test files live under `D:\Projects\MusicScene\tools\...`; run pytest from the repo root.
- Godot self-tests live under `D:\Projects\MusicScene\tools\*.gd` and print `fail=0` / `FAIL:` lines that CI greps.

---

## File structure

| File | Responsibility |
| --- | --- |
| `addons/musicscene/tools/fonts/Tinos-{Regular,Bold,Italic}.ttf` | bundled outlines for text→path (Times-metric, SIL OFL 1.1) |
| `addons/musicscene/tools/fonts/OFL.txt` | SIL Open Font License 1.1 text for the bundled fonts |
| `addons/musicscene/tools/svg_text_to_path.py` | pure converter: SVG string in → SVG string with `<text>` rewritten to `<path>` |
| `addons/musicscene/tools/verovio_render.py` | add `--text-to-path` flag; call the converter before writing each SVG |
| `addons/musicscene/notation/MSNotationBackendMusicXML.gd` | builtin engraver command gains `--text-to-path` |
| `tools/verovio/test_svg_text_to_path.py` | pytest for the converter |
| `tools/test_notation_lyrics.gd` | Godot headless self-test: lyrics render as dark pixels |
| `.github/workflows/ci.yml` | install fontTools + run the new self-test |
| `CHANGELOG.md`, `README.md` | note the Godot preview now shows text |

---

## Task 1: Bundle the Tinos fonts

**Files:**
- Create: `addons/musicscene/tools/fonts/Tinos-Regular.ttf`, `-Bold.ttf`, `-Italic.ttf` (extracted from the user's zip)
- Create: `addons/musicscene/tools/fonts/OFL.txt`

The user placed Tinos (Apache/OFL, Times-metric) at `C:\Users\Stefaan Himpe\Downloads\Tinos.zip`, containing `Tinos-Regular.ttf`, `-Bold.ttf`, `-Italic.ttf`, `-BoldItalic.ttf`, and `OFL.txt`.

- [ ] **Step 1: Extract the three faces + the license from the zip**

Run (Git Bash). `-j` flattens paths, `-o` overwrites:
```bash
mkdir -p "D:/Projects/MusicScene/addons/musicscene/tools/fonts"
unzip -j -o "C:/Users/Stefaan Himpe/Downloads/Tinos.zip" \
  "Tinos-Regular.ttf" "Tinos-Bold.ttf" "Tinos-Italic.ttf" "OFL.txt" \
  -d "D:/Projects/MusicScene/addons/musicscene/tools/fonts"
ls -1 "D:/Projects/MusicScene/addons/musicscene/tools/fonts"
```
Expected: `OFL.txt`, `Tinos-Bold.ttf`, `Tinos-Italic.ttf`, `Tinos-Regular.ttf` present. (We do NOT bundle `-BoldItalic.ttf`: no Verovio class is both bold and italic; the converter uses only R/B/I.)

- [ ] **Step 2: Verify they load and have Latin coverage**

Run:
```bash
cd "D:/Projects/MusicScene" && py -c "
from fontTools.ttLib import TTFont
import os
d='addons/musicscene/tools/fonts'
for f in ['Tinos-Regular.ttf','Tinos-Bold.ttf','Tinos-Italic.ttf']:
    t=TTFont(os.path.join(d,f)); cm=t.getBestCmap()
    assert all(ord(c) in cm for c in 'AbcMorningTempo,'), f
    print(f,'OK upm=',t['head'].unitsPerEm)
"
```
Expected: three `... OK upm=2048` lines, no assertion error.

- [ ] **Step 3: Add a short NOTICE alongside the OFL text**

`OFL.txt` (the full license) came from the zip. Add a one-line provenance note by creating `addons/musicscene/tools/fonts/README.txt`:
```
Tinos (Regular, Bold, Italic) — a Times-metric serif, licensed under the SIL Open
Font License 1.1 (see OFL.txt). Used by ../svg_text_to_path.py to outline Verovio
SVG <text> into <path> so renderers without SVG-text support (Godot's ThorVG) can
display lyrics and other engraved text. Matches Verovio's `Times, serif`.
```

- [ ] **Step 4: Commit**

```bash
git -C "D:/Projects/MusicScene" add addons/musicscene/tools/fonts/
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
feat(notation): bundle Tinos (R/B/I) for SVG text->path

Times-metric serif, SIL OFL 1.1 (OFL.txt). Used to outline Verovio <text> so
Godot's ThorVG (which renders <path> but not <text>) can display lyrics/text.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: The `svg_text_to_path.py` converter

**Files:**
- Create: `addons/musicscene/tools/svg_text_to_path.py`
- Test: `tools/verovio/test_svg_text_to_path.py`

- [ ] **Step 1: Write the failing test**

Create `tools/verovio/test_svg_text_to_path.py`:
```python
"""Tests for the Verovio SVG <text> -> <path> converter.
Run:  py -m pytest tools/verovio/test_svg_text_to_path.py -q
"""
import importlib.util, os, sys, re
import pytest

_MOD = os.path.join(os.path.dirname(__file__), "..", "..",
                    "addons", "musicscene", "tools", "svg_text_to_path.py")

def _load():
    spec = importlib.util.spec_from_file_location("svg_text_to_path", _MOD)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

# a minimal Verovio-shaped SVG: a <style> with the class rules, a note glyph via <use xlink:href>,
# a verse <text> (regular) and a tempo <text> (bold), each with the Verovio 0px-outer/real-tspan idiom.
SVG = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
  'width="400" height="200" viewBox="0 0 4000 2000">'
  '<style type="text/css">#x g.tempo {font-weight:bold;}#x g.dir {font-style:italic;}'
  'ellipse, path {stroke:currentColor}</style>'
  '<g class="note" id="note1"><use xlink:href="#glyph-x" x="100" y="100"/></g>'
  '<g class="verse"><text x="500" y="1500" font-size="0px"><tspan font-size="360">morn</tspan></text></g>'
  '<g class="tempo"><text x="500" y="200" font-size="0px"><tspan font-size="360">morn</tspan></text></g>'
  '</svg>'
)

def test_converts_text_to_path_and_preserves_notes():
    out = _load().svg_text_to_path(SVG)
    assert "<text" not in out                          # every <text> converted
    assert "<path" in out                              # ... into paths
    assert 'xlink:href="#glyph-x"' in out              # note glyph refs preserved (namespace round-trip)
    assert 'id="note1"' in out                         # note ids preserved (position parsing safe)
    assert "<style" in out                             # style block still present

def test_bold_class_uses_bold_face():
    # same letters at the same size, one in a verse (regular) group, one in a tempo (bold) group.
    # the two runs must emit DIFFERENT path outlines -> proves the bold face was selected.
    out = _load().svg_text_to_path(SVG)
    ds = re.findall(r'<path[^>]*\bd="([^"]+)"', out)
    assert len(ds) >= 2
    # the verse "morn" (4 glyphs regular) and tempo "morn" (4 glyphs bold) differ glyph-for-glyph
    assert ds[:4] != ds[4:8]

def test_missing_fonttools_returns_unchanged(monkeypatch):
    m = _load()
    monkeypatch.setattr(m, "_load_face", lambda style: None)  # simulate no font/fonttools
    out = m.svg_text_to_path(SVG)
    assert out == SVG                                   # unchanged, render never breaks

def test_no_text_is_noop():
    plain = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
             '<rect width="10" height="10"/></svg>')
    out = _load().svg_text_to_path(plain)
    assert "<rect" in out and "<text" not in out
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/verovio/test_svg_text_to_path.py -q`
Expected: FAIL — the module doesn't exist yet (import error). Create the empty `tools/verovio/__init__.py` if pytest complains about the package (mirror the existing `tools/panola_mei/` layout; if that dir has no `__init__.py`, none is needed here either).

- [ ] **Step 3: Write the converter**

Create `addons/musicscene/tools/svg_text_to_path.py`:
```python
"""Convert SVG <text> elements to <path> glyph outlines.

Verovio emits lyrics/tempo/directions as <text>/<tspan>. Godot's ThorVG rasteriser draws
<path> but NOT <text>, so that text is invisible. This rewrites each <text> into filled
<path> outlines using bundled Tinos faces (Times-metric, matching Verovio's
`Times, serif`), choosing Regular/Bold/Italic from the element's Verovio CSS class.

Robust by design: on any failure (fontTools missing, a face missing, an unparseable SVG)
the ORIGINAL svg string is returned, so a render never breaks. Note glyphs (<use
xlink:href>) and ids are preserved, so note-position parsing is unaffected.
"""
import os, re, sys
import xml.etree.ElementTree as ET

_SVG_NS = "http://www.w3.org/2000/svg"
_XLINK_NS = "http://www.w3.org/1999/xlink"
_FONT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
_FACES = {
    "regular": "Tinos-Regular.ttf",
    "bold": "Tinos-Bold.ttf",
    "italic": "Tinos-Italic.ttf",
}
_face_cache = {}


def _load_face(style):
    """Return {glyphset, cmap, hmtx, upm} for a style, or None if unavailable (cached)."""
    if style in _face_cache:
        return _face_cache[style]
    face = None
    try:
        from fontTools.ttLib import TTFont
        ft = TTFont(os.path.join(_FONT_DIR, _FACES[style]))
        face = {
            "glyphset": ft.getGlyphSet(),
            "cmap": ft.getBestCmap(),
            "hmtx": ft["hmtx"],
            "upm": ft["head"].unitsPerEm,
        }
    except Exception as e:
        sys.stderr.write("svg_text_to_path: cannot load %s: %s\n" % (style, e))
    _face_cache[style] = face
    return face


def _localname(tag):
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def _f(s):
    if s is None:
        return 0.0
    m = re.match(r"\s*(-?[0-9.]+)", str(s))
    return float(m.group(1)) if m else 0.0


def _fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def _parse_css(style_text):
    """(bold_classes, italic_classes) from Verovio's <style> CSS."""
    bold, italic = set(), set()
    for m in re.finditer(r"([^{}]+)\{([^}]*)\}", style_text or ""):
        decls = m.group(2).replace(" ", "")
        b = "font-weight:bold" in decls
        i = "font-style:italic" in decls
        if not (b or i):
            continue
        for cls in re.findall(r"g\.([A-Za-z0-9_-]+)", m.group(1)):
            if b:
                bold.add(cls)
            if i:
                italic.add(cls)
    return bold, italic


def _first_size(text_el):
    """The real font-size: a tspan's (Verovio puts 0px on the outer <text>), else the text's."""
    for el in list(text_el.findall("{%s}tspan" % _SVG_NS)) + [text_el]:
        n = _f(el.get("font-size"))
        if n > 0:
            return n
    return None


def _advance(s, face):
    w = 0.0
    for ch in s:
        g = face["cmap"].get(ord(ch))
        w += face["hmtx"][g][0] if g else face["upm"] * 0.5
    return w


def _text_to_paths(text_el, is_bold, is_italic):
    """List of <path> Elements for a <text>, or None to leave it unchanged."""
    style = "italic" if is_italic else ("bold" if is_bold else "regular")
    face = _load_face(style)
    if face is None:
        return None
    fs = _first_size(text_el)
    if not fs or fs <= 0:
        return None
    s = "".join(text_el.itertext())
    if s.strip() == "":
        return None
    x, y = _f(text_el.get("x")), _f(text_el.get("y"))
    tsp = text_el.find("{%s}tspan" % _SVG_NS)
    if tsp is not None:
        if tsp.get("x") is not None:
            x = _f(tsp.get("x"))
        if tsp.get("y") is not None:
            y = _f(tsp.get("y"))
    scale = fs / face["upm"]
    anchor = text_el.get("text-anchor") or "start"
    if anchor in ("middle", "end"):
        x -= _advance(s, face) * scale * (0.5 if anchor == "middle" else 1.0)
    from fontTools.pens.svgPathPen import SVGPathPen
    out, penx = [], x
    for ch in s:
        g = face["cmap"].get(ord(ch))
        if g is None:
            penx += fs * 0.5
            continue
        pen = SVGPathPen(face["glyphset"])
        face["glyphset"][g].draw(pen)
        d = pen.getCommands()
        if d:
            p = ET.Element("{%s}path" % _SVG_NS)
            p.set("fill", "#000000")
            p.set("transform", "translate(%s %s) scale(%s %s)" % (_fmt(penx), _fmt(y), _fmt(scale), _fmt(-scale)))
            p.set("d", d)
            out.append(p)
        penx += face["hmtx"][g][0] * scale
    return out or None


def _process(el, bold_classes, italic_classes, inh_b, inh_i):
    cls = (el.get("class") or "").split()
    b = inh_b or any(c in bold_classes for c in cls)
    i = inh_i or any(c in italic_classes for c in cls)
    new_kids, changed = [], False
    for child in list(el):
        if _localname(child.tag) == "text":
            ccls = (child.get("class") or "").split()
            paths = _text_to_paths(child,
                                   b or any(c in bold_classes for c in ccls),
                                   i or any(c in italic_classes for c in ccls))
            if paths:
                new_kids.extend(paths)
                changed = True
            else:
                new_kids.append(child)
        else:
            _process(child, bold_classes, italic_classes, b, i)
            new_kids.append(child)
    if changed:
        el[:] = new_kids


def svg_text_to_path(svg):
    """Rewrite <text> -> <path> outlines. Returns the original string on any failure."""
    if "<text" not in svg:
        return svg
    ET.register_namespace("", _SVG_NS)
    ET.register_namespace("xlink", _XLINK_NS)
    try:
        root = ET.fromstring(svg)
    except Exception as e:
        sys.stderr.write("svg_text_to_path: parse failed: %s\n" % e)
        return svg
    if _load_face("regular") is None:        # no fonttools/fonts -> leave unchanged
        return svg
    bold, italic = set(), set()
    for st in root.iter("{%s}style" % _SVG_NS):
        b, i = _parse_css(st.text)
        bold |= b
        italic |= i
    try:
        _process(root, bold, italic, False, False)
        body = ET.tostring(root, encoding="unicode")
    except Exception as e:
        sys.stderr.write("svg_text_to_path: convert failed: %s\n" % e)
        return svg
    decl = ""
    m = re.match(r"\s*(<\?xml[^>]*\?>)", svg)
    if m:
        decl = m.group(1)
    return decl + body
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `py -m pytest tools/verovio/test_svg_text_to_path.py -q`
Expected: PASS (4 tests). If `test_bold_class_uses_bold_face` seems fragile: "morn" in Tinos differs between Regular and Bold, and the assertion `ds[:4] != ds[4:8]` compares the whole 4-glyph run, so any single differing glyph passes it.

- [ ] **Step 5: Commit**

```bash
git -C "D:/Projects/MusicScene" add addons/musicscene/tools/svg_text_to_path.py tools/verovio/test_svg_text_to_path.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
feat(notation): svg_text_to_path — outline Verovio <text> to <path>

Parses the Verovio <style> for bold/italic classes, rewrites each <text> into
Tinos glyph <path>s (weight/style per class), preserves note <use>/ids,
and returns the SVG unchanged on any failure.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `--text-to-path` flag in `verovio_render.py`

**Files:**
- Modify: `addons/musicscene/tools/verovio_render.py`
- Test: `tools/verovio/test_svg_text_to_path.py` (append an end-to-end flag test)

- [ ] **Step 1: Write the failing test**

Append to `tools/verovio/test_svg_text_to_path.py`:
```python
import subprocess, tempfile, shutil, json
SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")
WRAP = os.path.join(os.path.dirname(__file__), "..", "..",
                    "addons", "musicscene", "tools", "verovio_render.py")

def _mei_with_lyrics(path):
    """Write a 2-note lyric MEI via sclang; skip if sclang absent."""
    script = ('(File.use("%s","w",{|f| f.write('
              'PanolaMEI.scoreAsMEI([Panola("c5_4 d5")], [( measure: 1, meter: "4/4", key: \\Cmajor )],'
              ' [\\treble], nil, nil, nil, [[ "morn-ing" ]]))}); 0.exit;)' % path.replace("\\", "/"))
    f = tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8")
    f.write(script); f.close()
    try:
        subprocess.run([SCLANG, f.name], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(f.name)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_flag_converts_text_but_default_does_not():
    d = tempfile.mkdtemp(prefix="v2p_")
    try:
        mei = os.path.join(d, "s.mei"); _mei_with_lyrics(mei)
        if not os.path.exists(mei):
            pytest.skip("sclang did not produce MEI")
        # default: SVG keeps <text>
        subprocess.run(["py", WRAP, mei, os.path.join(d, "plain.svg"), "--page", "1"],
                       capture_output=True, text=True)
        plain = open(os.path.join(d, "plain.svg"), encoding="utf-8").read()
        # with the flag: SVG has <path>, no <text>, and the "morn" glyphs
        r = subprocess.run(["py", WRAP, mei, os.path.join(d, "p.svg"), "--page", "1", "--text-to-path"],
                           capture_output=True, text=True)
        conv = open(os.path.join(d, "p.svg"), encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    assert "<text" in plain                      # default unchanged
    assert "<text" not in conv and "<path" in conv
    assert "(text→path)" in (r.stdout + r.stderr) or "text->path" in (r.stdout + r.stderr)
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/verovio/test_svg_text_to_path.py -k flag -q`
Expected: FAIL — `verovio_render.py` doesn't know `--text-to-path` (argparse error) or doesn't convert. (SKIP if sclang absent — then STOP and report BLOCKED.)

- [ ] **Step 3: Add the flag and the import**

In `verovio_render.py`, add the argument after the `--breaks` line (~line 47):
```python
    ap.add_argument("--text-to-path", action="store_true",
                    help="rewrite SVG <text> to <path> outlines (for renderers without SVG-text support)")
```

At the top of `main()` after `a = ap.parse_args()` (~line 53), add a lazy import + converter reference (import here so a missing module never breaks a plain render):
```python
    convert = None
    if a.text_to_path:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from svg_text_to_path import svg_text_to_path as convert
        except Exception as e:
            sys.stderr.write("verovio_render: --text-to-path unavailable: %s\n" % e)
            convert = None
```
(Note: `import os` is already imported at the top of the file; `sys` too.)

- [ ] **Step 4: Apply the converter where each SVG is written**

In the `--paginate` branch, change the page-writing loop (~line 85-87):
```python
        for pg in range(1, n + 1):
            with open("%s-%d.svg" % (stem, pg), "w", encoding="utf-8") as f:
                f.write(tk.renderToSVG(pg))
```
to:
```python
        for pg in range(1, n + 1):
            svg = tk.renderToSVG(pg)
            if convert is not None:
                svg = convert(svg)
            with open("%s-%d.svg" % (stem, pg), "w", encoding="utf-8") as f:
                f.write(svg)
```
And in the single-page branch (~line 92-94):
```python
    page = max(1, min(a.page, tk.getPageCount()))
    with open(a.output, "w", encoding="utf-8") as f:
        f.write(tk.renderToSVG(page))
```
to:
```python
    page = max(1, min(a.page, tk.getPageCount()))
    svg = tk.renderToSVG(page)
    if convert is not None:
        svg = convert(svg)
    with open(a.output, "w", encoding="utf-8") as f:
        f.write(svg)
```

- [ ] **Step 5: Report the conversion on stdout**

The two `print(...)` lines report what was written. Append a `(text→path)` marker when conversion ran. Change the paginate print (~line 89):
```python
        print("verovio: wrote %d page(s) %s-N.svg%s (breaks=%s)" % (n, stem, " + timemap" if a.timemap else "", breaks))
```
to:
```python
        print("verovio: wrote %d page(s) %s-N.svg%s (breaks=%s)%s" % (n, stem, " + timemap" if a.timemap else "", breaks, " (text→path)" if convert is not None else ""))
```
and the single-page print (~line 96):
```python
    print("verovio: wrote " + a.output + (" + timemap" if a.timemap else "") + (" (breaks=%s)" % breaks))
```
to:
```python
    print("verovio: wrote " + a.output + (" + timemap" if a.timemap else "") + (" (breaks=%s)" % breaks) + (" (text→path)" if convert is not None else ""))
```

- [ ] **Step 6: Run to verify it passes**

Run: `py -m pytest tools/verovio/test_svg_text_to_path.py -q`
Expected: PASS (all converter tests + the flag test).

- [ ] **Step 7: Regression — the existing suites don't pass the flag, so SVGs are unchanged**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass (they never pass `--text-to-path`).

- [ ] **Step 8: Commit**

```bash
git -C "D:/Projects/MusicScene" add addons/musicscene/tools/verovio_render.py tools/verovio/test_svg_text_to_path.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
feat(notation): verovio_render --text-to-path flag

Off by default (SVG byte-identical for existing consumers). When set, each
rendered page's <text> is outlined to <path> via svg_text_to_path.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Godot integration + headless self-test

**Files:**
- Modify: `addons/musicscene/notation/MSNotationBackendMusicXML.gd` (builtin engraver command)
- Create: `tools/test_notation_lyrics.gd`

- [ ] **Step 1: Add `--text-to-path` to the builtin Verovio command**

In `MSNotationBackendMusicXML.gd`, `_builtin_default` (~line 149-153) currently returns:
```
		return "%s \"res://addons/musicscene/tools/verovio_render.py\" {input} {output} --page {page}" % py
```
Change it to append the flag:
```
		return "%s \"res://addons/musicscene/tools/verovio_render.py\" {input} {output} --page {page} --text-to-path" % py
```
(This makes the bundled engraver outline text by default. The addressable/positions render in `MSRenderQueue.gd` uses this same command and appends `--timemap`/`--paginate`; text→path leaves note `<use>`/ids/geometry and the MEI-derived timemap untouched, so note addressing is unaffected — verified by the self-test below.)

- [ ] **Step 2: Write the Godot headless self-test**

Create `tools/test_notation_lyrics.gd`:
```gdscript
extends SceneTree
## Headless self-test: a lyric score rendered with --text-to-path shows real dark pixels
## where the lyrics sit (Godot's ThorVG renders <path> glyphs, not <text>). Prints `fail=0`
## on success (CI greps for it), `FAIL:` on any failure.

const BackendSvg := preload("res://addons/musicscene/notation/MSNotationBackendSvg.gd")

func _dark(img: Image, x0: int, y0: int, x1: int, y1: int) -> int:
	var n := 0
	for x in range(x0, x1):
		for y in range(y0, y1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var p := img.get_pixel(x, y)
				if p.a > 0.5 and p.r < 0.5 and p.g < 0.5 and p.b < 0.5:
					n += 1
	return n

func _rasterize(svg_text: String) -> Image:
	var svg := BackendSvg.flatten_nested_viewbox(svg_text)   # same transform production applies
	var img := Image.new()
	if img.load_svg_from_string(svg, 3.0) != OK:
		return null
	return img

func _init() -> void:
	var fails := 0
	var tmp := OS.get_environment("TEMP")
	if tmp == "":
		tmp = "user://"
	var mei := tmp.path_join("mslyr_test.mei")
	# a minimal lyric MEI (single voice, two syllables) — no sclang needed
	var mei_str := '<?xml version="1.0" encoding="UTF-8"?><mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score><scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp><staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef><section><measure n="1"><staff n="1"><layer n="1"><note dur="4" oct="5" pname="c"><verse n="1"><syl>morn</syl></verse></note><note dur="4" oct="5" pname="d"><verse n="1"><syl>ing</syl></verse></note></layer></staff></measure></section></score></mdiv></body></music></mei>'
	var f := FileAccess.open(mei, FileAccess.WRITE)
	if f == null:
		print("FAIL: cannot write temp MEI"); quit()
		return
	f.store_string(mei_str); f.close()

	var py := "py" if OS.get_name() == "Windows" else "python3"
	var wrap := ProjectSettings.globalize_path("res://addons/musicscene/tools/verovio_render.py")
	var svg_conv := tmp.path_join("mslyr_conv.svg")
	var svg_plain := tmp.path_join("mslyr_plain.svg")
	var out := []
	OS.execute(py, [wrap, mei, svg_conv, "--page", "1", "--text-to-path"], out, true)
	OS.execute(py, [wrap, mei, svg_plain, "--page", "1"], out, true)

	if not FileAccess.file_exists(svg_conv) or not FileAccess.file_exists(svg_plain):
		print("FAIL: verovio wrapper produced no SVG (is verovio installed?)"); print("fail=1"); quit()
		return

	var conv := FileAccess.get_file_as_string(svg_conv)
	var plain := FileAccess.get_file_as_string(svg_plain)
	# structural: converted has paths, no text; plain still has text
	if conv.contains("<text"): fails += 1; print("FAIL: converted SVG still has <text>")
	if not conv.contains("<path"): fails += 1; print("FAIL: converted SVG has no <path>")
	if not plain.contains("<text"): fails += 1; print("FAIL: plain SVG unexpectedly has no <text>")

	# rendered: the converted SVG must produce dark pixels in the lyric band (below the staff);
	# the plain one must not (ThorVG drops its <text>).
	var img_conv := _rasterize(conv)
	var img_plain := _rasterize(plain)
	if img_conv == null or img_plain == null:
		fails += 1; print("FAIL: rasterisation failed")
	else:
		# lyric band = lower third of the image, full width
		var h := img_conv.get_height(); var w := img_conv.get_width()
		var band_conv := _dark(img_conv, 0, int(h * 0.6), w, h)
		var band_plain := _dark(img_plain, 0, int(h * 0.6), w, h)
		print("lyric_band_conv=", band_conv, " lyric_band_plain=", band_plain, " size=", img_conv.get_size())
		if band_conv < 20: fails += 1; print("FAIL: no lyric pixels in the converted render")
		if band_conv <= band_plain: fails += 1; print("FAIL: converted render not darker than plain in the lyric band")

	print("fail=", fails)
	quit()
```

- [ ] **Step 3: Run the self-test**

Run:
```bash
"D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --path "D:/Projects/MusicScene" --headless --script "res://tools/test_notation_lyrics.gd" 2>&1 | grep -E "lyric_band|fail=|FAIL:"
```
Expected: a `lyric_band_conv=<N>` with N ≥ 20 and greater than `lyric_band_plain`, and `fail=0` with no `FAIL:` lines. (If verovio isn't importable by the `py` launcher Godot uses, the test prints `fail=1` with a clear message — then confirm `py -c "import verovio"` works and that `py` is the launcher.)

- [ ] **Step 4: Confirm the whole project still boots clean (no parse errors)**

Run:
```bash
"D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --path "D:/Projects/MusicScene" --headless --quit 2>&1 | grep -iE "SCRIPT ERROR|Parse Error" || echo "no parse errors"
```
Expected: `no parse errors`.

- [ ] **Step 5: Commit**

```bash
git -C "D:/Projects/MusicScene" add addons/musicscene/notation/MSNotationBackendMusicXML.gd tools/test_notation_lyrics.gd
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
feat(notation): bundled Verovio engraver outlines text; self-test

The builtin MEI/ABC command now passes --text-to-path so lyrics/tempo/etc. show
in Godot's ThorVG preview. tools/test_notation_lyrics.gd proves the lyric band
renders dark pixels (converted) vs none (plain).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: CI + docs + finish

**Files:**
- Modify: `.github/workflows/ci.yml`, `CHANGELOG.md`, `README.md`

- [ ] **Step 1: CI — install fontTools and run the self-test**

In `.github/workflows/ci.yml`, the "Install Verovio" step (~line 21-22) is:
```yaml
      - name: Install Verovio
        run: python3 -m pip install verovio
```
Change it to also install fontTools:
```yaml
      - name: Install Verovio + fontTools (notation self-tests)
        run: python3 -m pip install verovio fonttools
```
Then, after the existing "Self-tests — incremental notation (no flicker)" step (~line 138-141), add a new step:
```yaml
      - name: Self-tests — lyrics text→path render
        run: |
          ./godot --headless --path . --script res://tools/test_notation_lyrics.gd 2>&1 | tee lyrics.log
          grep -q "fail=0" lyrics.log && ! grep -q "FAIL:" lyrics.log
```

- [ ] **Step 2: CHANGELOG entry**

In `CHANGELOG.md`, add under the current unreleased `### Added` (or `### Fixed`) section:
```
- **Lyrics (and all Verovio text) now render in the Godot notation preview.** Godot's ThorVG
  SVG rasteriser draws paths but not `<text>`, so lyrics/tempo/directions were invisible. The
  bundled `verovio_render.py` gained a `--text-to-path` flag (on by default for the built-in
  Verovio engraver) that outlines every `<text>` to `<path>` glyphs via bundled Tinos
  (Times-metric serif; bold/italic chosen per Verovio's CSS class). Note ids/geometry and the
  timemap are untouched, so note addressing/following are unaffected.
```

- [ ] **Step 3: README note**

In `README.md`, near the notation/MSScore section (search for the lyrics paragraph added earlier, `**Lyrics.**`), append a sentence to that paragraph:
```
 The Godot preview renders this text by outlining Verovio's SVG `<text>` to vector paths
(Godot's ThorVG rasteriser doesn't draw SVG text) — bundled with a Times-metric serif.
```

- [ ] **Step 4: Full green — Python suites + Godot self-test**

Run:
```bash
cd "D:/Projects/MusicScene" && py -m pytest tools/verovio/ tools/panola_mei/ tools/msscore/ -q
"D:/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe" --path "D:/Projects/MusicScene" --headless --script "res://tools/test_notation_lyrics.gd" 2>&1 | grep -E "fail=|FAIL:"
```
Expected: pytest all pass; self-test `fail=0`, no `FAIL:`.

- [ ] **Step 5: Commit docs (incl. spec + plan)**

```bash
git -C "D:/Projects/MusicScene" add .github/workflows/ci.yml CHANGELOG.md README.md docs/superpowers/specs/2026-07-10-verovio-text-to-path-design.md docs/superpowers/plans/2026-07-11-verovio-text-to-path.md
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs+ci: text→path in CHANGELOG/README, CI runs the lyrics render self-test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Finish**

Report completion. The branch `feature/panola-lyrics` now carries both the lyrics feature and its Godot display fix. Do NOT push or merge — the user handles that (and the panola/msscore quark repos). Mention the user should re-run their `.scd` example to see lyrics in Godot.

---

## Self-review

**Spec coverage:**
- §1 `--text-to-path` flag, default off, applied both branches, MusicScene command adds it → Task 3 + Task 4 Step 1. ✓
- §2 converter (CSS class map, pen origin from tspan, weight/style, anchor, outlines, replace text, xlink/id preserved) → Task 2 code + tests. ✓
- §3 bundled Tinos R/B/I + OFL.txt, resolved via `__file__` → Task 1 + `_FONT_DIR`. ✓
- §4 error handling (fonttools/face missing, parse fail, empty string → unchanged) → `_load_face`/`svg_text_to_path` guards + `test_missing_fonttools_returns_unchanged`. ✓
- §5 Python unit (paths, no text, bold-differs, unchanged-on-missing) + Godot self-test (dark pixels, plain control) + regression suites unflagged → Tasks 2/3/4. ✓
- §6 CI fonttools + self-test → Task 5 Step 1. ✓
- §7 all listed files touched. ✓

**Placeholder scan:** No TBD/TODO/"similar to". All code shown; commands concrete with expected output. Font choice is concrete (Tinos, from the user's zip, no download).

**Type/name consistency:** `svg_text_to_path(svg)` is the public fn used by the wrapper (Task 3) and tests (Task 2). `_load_face(style)` is the monkeypatch point named in `test_missing_fonttools_returns_unchanged`. `_FACES` keys `regular/bold/italic` match `_load_face` calls and the bundled filenames from Task 1. The flag is `--text-to-path` (argparse → `a.text_to_path`) consistently across wrapper, GDScript command, tests, and CI. The self-test uses `BackendSvg.flatten_nested_viewbox`, an existing static (confirmed in MSNotationBackendSvg.gd).

**Deviation noted:** spec §1 framed the positions/on-disk SVG as staying byte-identical; because the display and addressable renders share the one built-in command, adding `--text-to-path` there converts text in that SVG too. This is safe (note `<use>`/ids/geometry and the MEI timemap are untouched) and is asserted by the self-test's structural + note-preservation checks; the Python `test_converts_text_to_path_and_preserves_notes` locks the id/xlink preservation.
