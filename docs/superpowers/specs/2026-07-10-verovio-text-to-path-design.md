# Verovio SVG text → path — Design

**Date:** 2026-07-10
**Status:** approved (pending written-spec review)

## Goal

Make Verovio text (lyrics `<verse>/<syl>`, and also tempo / directions / etc.)
**visible in the Godot notation preview**. Godot 4.7 rasterizes SVG with ThorVG,
which renders `<rect>`/`<path>` but produces **no glyphs for SVG `<text>`** — even
with a fully base64-embedded `@font-face` (verified: `rect` → 900 dark px, every
`<text>` variant → 0 px). `load_svg_from_string` exposes no font-registration hook
from GDScript, so text cannot be made to render as text. Noteheads/clefs/standard
dynamics survive because they are glyph **paths**.

Fix: post-process the Verovio SVG to replace each `<text>` with `<path>` glyph
outlines. ThorVG renders those (validated end-to-end: converted "Hi morn-" →
232 dark px in a headless Godot rasterization). The lyrics feature itself is
already correct — the MEI carries proper `<verse>/<syl>`; this only closes the
Godot **display** gap, which affects all Verovio text, not only lyrics.

## Decisions (from brainstorming)

1. Convert in **`verovio_render.py`** (Python wrapper MusicScene already invokes),
   behind an opt-in **`--text-to-path`** flag (default off → existing SVG output and
   tests byte-identical).
2. **All text**, **faithful weights**: bundle Tinos Regular + Bold + Italic and pick
   per the element's Verovio CSS class.
3. Font assets fetched during implementation (Apache-2.0 Tinos from Google Fonts/
   GitHub); if no network, pause and the user drops the three `.ttf` files in.

## 1. Trigger & flow

- New CLI flag `--text-to-path` (store_true) on `verovio_render.py`. Default **off**.
- When set, after Verovio produces each SVG string (both the single-page branch and
  each page of `--paginate`), the wrapper runs `svg_text_to_path(svg)` before writing
  the file. When unset, the SVG is written exactly as today (byte-identical).
- MusicScene's render command adds the flag. `MSNotationBackendMusicXML.gd` builds the
  command string at ~line 152 (`… verovio_render.py {input} {output} --page {page}`);
  append `--text-to-path`. The `--paginate` command path (if built elsewhere in the
  render queue) gets it too.

## 2. The converter — `svg_text_to_path(svg: str) -> str`

Lives in `verovio_render.py` (or a sibling module `svg_text_to_path.py` it imports —
implementer's choice, but it must be independently unit-testable). Steps:

1. Parse the SVG with `xml.etree.ElementTree`, registering the SVG namespace so output
   round-trips. Parse the `<style>` CSS text into a map `class → {weight, style}` by
   reading the `g.<class> {font-weight:bold}` / `{font-style:italic}` rules (so the
   mapping tracks Verovio rather than being hardcoded).
2. Walk the tree tracking the ancestor `<g class="…">` chain. For each `<text>`:
   - **Pen origin**: `x`,`y` from the `<text>`; a child `<tspan>`'s own `x`/`y`
     override. Verovio's outer `<text>` has `font-size="0px"` and the real size lives
     on the `<tspan>` — read the size from the tspan (fall back to the text, then a
     sane default).
   - **Weight/style**: resolve from the ancestor classes via the CSS map (bold:
     `tempo`,`reh`,`fing`,`ending`; italic: `dir`,`dynam`,`mNum`; else regular). Choose
     the Tinos face: Italic if italic, Bold if bold, else Regular (if both bold+italic,
     prefer Italic — no class needs both, so this is an unreached fallback).
   - **String**: the concatenated text of the `<text>`/`<tspan>` descendants.
   - **text-anchor**: default `start`. For `middle`/`end`, measure the run's advance
     width (sum of `hmtx` advances × scale) and shift the origin left by half / full.
     Lyrics carry no `text-anchor`, so they stay start-anchored at Verovio's computed x.
   - **Outlines**: for each character, look up the glyph (`cmap`), draw it with
     `fontTools.pens.svgPathPen.SVGPathPen`, wrap in
     `<path fill="#000000" transform="translate(penx penY) scale(s -s)" d="…"/>`
     where `s = font-size / unitsPerEm` and the `-s` flips SVG-y-down to font-y-up.
     Advance `penx` by `hmtx[glyph].advanceWidth × s`. A missing glyph advances by a
     default (½ em) and emits nothing.
   - Replace the `<text>` element in its parent with the emitted `<path>` element(s),
     preserving the surrounding `<g class="verse">` (or other) wrapper and its id.
3. Serialize back to a string.

`fill="#000000"` (explicit black) is used because it is validated to render in ThorVG
and matches the default-black noteheads; `currentColor` is avoided (ThorVG's spotty
`currentColor` support is exactly why the existing backend re-declares strokes).

The three Tinos faces are loaded once per process (`TTFont`, `getGlyphSet`,
`getBestCmap`, `hmtx`, `head.unitsPerEm`) and reused across all `<text>` in the SVG.

## 3. Bundled fonts

`addons/musicscene/tools/fonts/Tinos-Regular.ttf`, `-Bold.ttf`, `-Italic.ttf`
(Apache-2.0) plus a short `addons/musicscene/tools/fonts/LICENSE` recording the
source and license. Tinos is metric-compatible with Times New Roman, matching
Verovio's `font-family="Times, serif"` so the converted layout matches the intended
engraving. The converter resolves the font directory relative to its own file
(`__file__`), so it works regardless of CWD.

## 4. Error handling — never break a render

- `import fontTools` fails, or the fonts directory / a face is missing → `svg_text_to_path`
  logs one warning to stderr and returns the **original** SVG unchanged. The render still
  succeeds; text is simply not converted (invisible in ThorVG, as today).
- A `<text>` that fails to parse/convert (missing size, empty string) is left as-is; other
  `<text>` elements still convert.
- The wrapper's exit code and stdout (`verovio: wrote …`) are unchanged; add
  ` (text→path)` to the stdout line only when the flag is set and conversion ran.

## 5. Testing

- **Python unit** (`tools/panola_mei/test_text_to_path.py` or `tools/verovio/…`):
  feed a minimal SVG containing a `<style>` with the Verovio class rules, a
  `<g class="verse"><text …><tspan font-size="40">morn</tspan></text></g>`, and a
  `<g class="tempo"><text …><tspan font-size="30">Allegro</tspan></text></g>`. Assert:
  output contains `<path`, contains no `<text`, the verse run produced ≥1 path, and the
  tempo run selected the Bold face. Concrete bold check: render the **same** letter at the
  **same** size once inside a `verse` group (Regular) and once inside a `tempo` group
  (Bold) and assert the two emitted `<path d="…">` strings **differ** (Bold and Regular
  outlines are not byte-equal). Also a `fontTools`-absent path: monkeypatch the import to
  fail and assert the SVG is returned unchanged.
- **Godot headless self-test** (`tools/test_notation_lyrics.gd`, printing `fail=0` /
  `FAIL:` like the sibling `tools/test_*.gd`): build a lyric MEI (or check in a small
  fixture), render it through `verovio_render.py --text-to-path`, `load_svg_from_string`,
  and assert a threshold of dark pixels in the vertical band **below the staff** where the
  lyrics sit (and, as a control, that a no-`--text-to-path` render of the same MEI has
  ~none there). This is the real ThorVG proof.
- **Regression**: the existing `tools/panola_mei/` and `tools/msscore/` suites are run
  **without** the flag, so their SVGs are byte-identical — they must still pass.

## 6. CI

`.github/workflows/ci.yml`: add `pip install fonttools` next to the Verovio install, and
a self-test step running `tools/test_notation_lyrics.gd` (asserting `fail=0`, `grep`-style
like the other notation self-tests).

## 7. Files

- `addons/musicscene/tools/verovio_render.py` — `--text-to-path` flag + call the converter.
- `addons/musicscene/tools/svg_text_to_path.py` — the converter (new; imported by the wrapper).
- `addons/musicscene/tools/fonts/Tinos-{Regular,Bold,Italic}.ttf` + `LICENSE` (new).
- `addons/musicscene/notation/MSNotationBackendMusicXML.gd` — append `--text-to-path` to the command(s).
- `tools/…/test_text_to_path.py` — Python unit test (new).
- `tools/test_notation_lyrics.gd` — Godot headless self-test (new).
- `.github/workflows/ci.yml` — fonttools install + the new self-test.
- `CHANGELOG.md`, `README.md` (notation section) — note that the Godot preview now shows lyrics/text.

## Out of scope (YAGNI)

Bold-italic combined face (no Verovio class needs it), non-Latin script shaping beyond
what Tinos + simple cmap lookup covers (no bidi/ligatures/complex shaping — lyrics are
simple runs), colored/themed text (all black, matching noteheads), and converting text in
the on-disk SVG used for note-position parsing (that path reads ids, not text; leaving the
default flag off there keeps it byte-identical).

## Validation already done

- ThorVG renders `<rect>` (900 px) but not `<text>` — even with embedded `@font-face`
  (named / `format()` / inline-style / system-name all 0 px).
- `fontTools` 4.61.1 present; converting "Hi morn-" to `<path>` outlines → 232 dark px in
  headless Godot (`load_svg_from_string`).
- Verovio emits lyrics as `font-family="Times, serif"`, no `text-anchor`; other text classes
  are bold (`tempo/reh/fing/ending`) or italic (`dir/dynam/mNum`) per the SVG `<style>`.
