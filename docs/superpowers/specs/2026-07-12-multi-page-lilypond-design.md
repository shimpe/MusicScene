# True Multi-Page LilyPond Rendering — Design

**Date:** 2026-07-12
**Status:** Approved (design)

## Goal

Make `MSScore notation: \lilypond` produce **turnable pages** in the MusicScene Godot
app — the same paged experience the Verovio path already gives — instead of the single
cropped image it produces today. Explicit `pageBreaks` and page-height-driven auto-fill
both create real pages; the addressable cursor follows across pages and auto-turns.

## Background

The app already has a full **paged path for Verovio** and, crucially, the page-turning /
cursor machinery on the notation object is **engine-agnostic**:

- `MSNotationObject3D._on_pages_done(pages, elements, page_count)` and its 2D twin store
  `pages` / `elements` / `page_count` and call `_show_page`.
- `_show_page(n)` swaps to `pages[n-1].texture` and uses `pages[n-1].systems`.
- `nextPage` / `prevPage` / `showPage` and the follow-cursor logic switch pages by each
  element's `page` field.

None of that is Verovio-specific. So the LilyPond feature only has to produce the same
`{pages, elements, page_count}` structure and call `_on_pages_done`. **No changes are
needed to the display/cursor/page-turn side.**

Today the LilyPond path is single-image only:

- `MSScore.pr_emitSetup` **forces `paginate` off** for LilyPond
  (`(isLy.not and: { paginate })`).
- `MSRenderQueue._submit_lily` runs `lily_render.py` once, `_finish_lily` calls
  `obj._on_elements_done(texture, elements, systems)` (one image).
- `lily_render.py` converts every `\pageBreak` to `\break` and renders one tall page,
  then crops the whole thing to a single cropped SVG.
- `MSNotationLilyPositions.finalize` returns `{ok, texture, elements, systems}`.

## Reference: the Verovio paged path (the template)

- `MSRenderQueue._submit_verovio`: when `options.paginate`, runs verovio
  `--paginate --page-height N` → `stem-1.svg`, `stem-2.svg`, … + a timemap; on completion
  calls `_finish_verovio_paged` → `obj._on_pages_done(res.pages, res.elements, res.page_count)`.
- `MSNotationVerovioPositions.finalize_paged(stem, timemap, options)`: for each page SVG,
  rasterises, parses note positions, `_build_systems`, **crops the raster vertically to its
  inked content** (`_crop_to_content`, keeps full width for uniform pages) and rescales the
  note/system `v`'s into the crop, tags each element with `page = pi + 1`. Returns
  `{ok, pages:[{texture, systems}], elements:[{index, when, u, v, sys, page}], page_count}`.
- The cache key already folds `paginate` + `page_height` (via `Cache.key(..., "vrv", key_opts)`),
  so changing either yields a fresh stem — stale page files are simply not reused.

## Architecture

Mirror the Verovio paged path for LilyPond. Four changed units; the display side is untouched.

### 1. `lily_render.py` — add a paged mode

New optional flag: `--paged <pageHeight>`.

- **Single mode (no flag): unchanged.** Keeps the existing `\pageBreak`→`\break`, one tall
  full page, whole-SVG crop, text→path behaviour.
- **Paged mode:** *Do not* strip `\pageBreak`. Inject a **finite** `\paper` block whose
  `paper-height` is derived from `pageHeight` (see *pageHeight mapping*), with
  `ragged-bottom`/`ragged-last-bottom` on and the same `system-system-spacing` used today.
  Render with `-dbackend=svg` (no `-dcrop`) so LilyPond emits one SVG **per page**
  (`stem-1.svg`, `stem-2.svg`, …), breaking pages at `\pageBreak` **and** when a page fills.
  Then, for each page SVG:
  1. Crop its viewBox to inked content (reuse `_content_bbox` / the crop logic).
  2. Outline `<text>`→`<path>` (reuse `_text_to_path`).
  3. Write `stem-1.cropped.svg`, `stem-2.cropped.svg`, ….
  Pages are cropped to a **uniform width** (the max content width across all pages,
  left-aligned) so the image does not shift horizontally when the user turns pages; the
  vertical crop is per-page.
- **Fallback:** if the paged render fails, fall back to the existing single-image path
  writing `stem.cropped.svg` (one page) so a render never comes back blank.
- Print how many pages were written (for logs / tests).

### 2. `MSNotationLilyPositions.finalize_paged(stem, options)` — new

Parallels `MSNotationVerovioPositions.finalize_paged`, minus the timemap (LilyPond
positions carry their own `data-when` / textedit links, as the single-image `finalize`
already parses).

- Enumerate `stem-1.cropped.svg`, `stem-2.cropped.svg`, … (numeric-sorted; reuse the same
  directory-walk idea as Verovio's `_page_svgs`).
- For each page: `SvgBackend.render` the cropped SVG, `_parse` its elements (same parser the
  single-image `finalize` uses), `_build_systems(page_elements)` (u-reset detection, per
  page), tag every element `page = n`.
- Because `lily_render.py` already cropped each page, **no raster re-crop/rescale is needed**
  here (unlike Verovio, whose pages are fixed-size). Elements' `v` are already in cropped
  space.
- Sort elements by `when`, reindex, return
  `{ok, pages:[{texture, systems}], elements:[{index, when, u, v, sys, page, line, char}], page_count}`.
- On no pages found / render error: `{ok: false, error: …}`.

The single-image `finalize` stays as-is for the non-paged path.

### 3. `MSRenderQueue._submit_lily` — add a paged branch + `_finish_lily_paged`

- Read `var paginate: bool = options.get("paginate", false)` and `page_height`.
- Fold `paginate` + `page_height` into the existing cache key (they must already be in
  `options`; if `_submit_lily` builds its own `key_opts`, add them — matching how
  `_submit_verovio` folds `engraver_cmd`). This satisfies the chosen cache strategy: a
  changed score / pageHeight / paginate flag yields a fresh stem, so stale page files are
  never reused.
- If `paginate`: cache-check `stem + "-1.cropped.svg"`; if present, call
  `_finish_lily_paged` and return. Otherwise build the argv as today plus
  `--paged <page_height>` (a plain positional value routed through
  `_text_to_path_python`-based invocation like the current call), launch, and on completion
  call `_finish_lily_paged`.
- If not `paginate`: existing single-image path unchanged.
- `_finish_lily_paged(obj, stem, options, pid)`:
  `var res := LilyPositions.finalize_paged(stem, options)`; on ok
  `obj._on_pages_done(res.pages, res.elements, res.page_count)`, else
  `obj._on_render_failed(res.error + _exit_note(pid))`.

Note the existing job-completion plumbing (`_jobs`, `_finish_*` dispatch): the paged job
records which finisher to call, exactly as the Verovio paged job does.

### 4. `MSScore.pr_emitSetup` — allow paginate for LilyPond

Change the forced-off line

```
snd.("/ms/scene/" ++ id, "paginate", (isLy.not and: { paginate }).if({ 1 }, { 0 }), pageHeight);
```

to send `paginate` (and `pageHeight`) for **both** engines:

```
snd.("/ms/scene/" ++ id, "paginate", paginate.if({ 1 }, { 0 }), pageHeight);
```

So `notation: \lilypond` with `paginate: true` (the MSScore default) → turnable pages;
`paginate: false` → the single cropped image. `pageBreaks` / `systemBreaks` already flow
into the Panola→LilyPond source (they emit `\pageBreak` / `\break`), and now the paged
render turns `\pageBreak` into a real page.

Update the `notation:` whelk doc comment (which currently implies LilyPond has no
pagination) to state that LilyPond now paginates like Verovio, and regenerate + parse-verify
the schelp.

## pageHeight mapping

Verovio's `pageHeight` is in Verovio SVG units (MSScore default `1200`). LilyPond needs a
`paper-height` in mm. Map `pageHeight` → mm via a factor tuned so the page count for a given
`pageHeight` roughly tracks Verovio's (smaller `pageHeight` = shorter pages = more pages).
Starting point: treat the default `1200` as an A4-ish content height (~250 mm) and scale
linearly (`mm ≈ pageHeight * 250/1200`), clamped to a sane minimum so a tiny value can't
produce a degenerate page. The exact factor is tuned empirically during implementation
against a multi-system score; `pageBreaks` force breaks on top of the auto-fill regardless.

## Data flow

```
MSScore notation:\lilypond, paginate:true, pageHeight, pageBreaks
  → OSC notationData "lilypond" <ly> + paginate 1 + pageHeight
  → MSRenderQueue._submit_lily (paginate branch)
      → lily_render.py --paged <pageHeight>
          → LilyPond multi-page SVG (stem-1.svg …) → per-page crop + text→path
          → stem-1.cropped.svg, stem-2.cropped.svg, …
      → _finish_lily_paged
          → MSNotationLilyPositions.finalize_paged
              → {pages:[{texture,systems}], elements:[…page], page_count}
          → obj._on_pages_done(pages, elements, page_count)
  → _show_page / nextPage / prevPage / follow-cursor auto-turn  (already engine-agnostic)
```

## Error handling

- **Paged render fails in `lily_render.py`:** fall back to a single cropped page (`stem.cropped.svg`)
  so the app still shows something. `finalize_paged` then finds no `stem-1.cropped.svg`; the
  paged branch should detect that and fall back to the single-image finish
  (`_finish_lily` on `stem.cropped.svg`) rather than erroring blank.
- **No fontTools:** text→path is best-effort (unchanged) — pages still render, text just
  stays unoutlined.
- **`finalize_paged` finds no pages:** return `{ok:false, error}` → `_on_render_failed`.
- **Non-paged path:** entirely unchanged, so single-image behaviour cannot regress.

## Testing

- **`tools/verovio/test_lily_render.py`** — add a paged test: a score with an explicit
  `\pageBreak` rendered with `--paged` writes `stem-1.cropped.svg` **and**
  `stem-2.cropped.svg`; each is a valid cropped SVG; text is outlined when fontTools is
  present; textedit links survive. Skips cleanly if LilyPond is absent.
- **Godot self-test (new, e.g. `tools/test_lily_paged.gd`)** — a pure-parse test over two
  hand-written `stem-1.cropped.svg` / `stem-2.cropped.svg` fixtures: `finalize_paged` returns
  `page_count == 2`, every element carries a `page`, page 1's elements precede page 2's in
  `when`, and each page has ≥1 system. No LilyPond/Python needed, so it runs in CI (like the
  existing `test_lily_systems.gd`).
- **MSScore** — extend `tools/msscore/test_lilypond.py` (or the paginate emit test) to assert
  `pr_emitSetup` now sends `paginate 1` for LilyPond when `paginate: true`.
- **Example** — update `examples/supercollider/example_lilypond.scd` so Part B uses real
  `pageBreaks` and `paginate: true` to demonstrate turnable pages (per the "illustrate every
  feature in a runnable example" rule). *(The user has uncommitted working-tree edits in this
  file; coordinate before touching it — do not clobber their edits.)*
- **Regression** — the existing single-image tests must still pass (non-paged path unchanged).

## Out of scope

- No changes to the page-turn UI, cursor, or `_on_pages_done` (already engine-agnostic).
- No change to Panola→LilyPond source generation (it already emits `\pageBreak`/`\break`).
- No Verovio changes.
