# Forced page & system breaks (Panola / MSScore) — Design

**Date:** 2026-07-08
**Component:** Panola quark (`PanolaMEI.sc`), MSScore quark (`MSScore.sc`), `verovio_render.py`
**Status:** Approved (brainstorm)

## Goal

Let the author force where pages and systems (lines) break, instead of only auto-pagination:

```
MSScore(voices: [...], paginate: true,
        pageBreaks:   [5, 9],   // a new PAGE starts at bars 5 and 9
        systemBreaks: [3, 7]);  // a new SYSTEM (line) starts at bars 3 and 7
```

## Background: the Verovio constraint (empirically established)

Verovio's `breaks` modes are all-or-nothing — no mode combines auto-pagination with a single
forced page break. Measured behavior (a break inserted before measure 3, `--paginate`):

| MEI contains | `breaks` mode that honors it | Effect |
|---|---|---|
| `<pb/>` (page break) | `encoded` | breaks pages **only** at the marks; auto page-fill **off** (a segment longer than a page overflows). Also honors `<sb/>`. |
| only `<sb/>` (system break) | `line` | forces the line break **and keeps auto page-fill** (systems flow onto pages by `pageHeight`). |
| neither | `auto` | today's behavior (auto pages + auto systems). |

`auto` and `smart` **ignore** encoded breaks entirely. So: **page breaks ⇒ manual pagination
(auto-fill off); system breaks ⇒ manual line breaks with auto-fill retained.**

The MEI is self-describing, so the render mode can be chosen from the MEI content — no new OSC
option and **no Godot/GDScript change** are needed.

## Input

Two new **MSScore** args, each a list of 1-based measure numbers (measure 1 is implicit and
ignored; out-of-range numbers are ignored):

- `pageBreaks: [5, 9]` → a `<pb/>` before those measures → **manual pagination**. `pageHeight`
  still sets the page *size*; you control every page boundary, so place enough breaks (a segment
  taller than the page overflows). Use with `paginate: true` (a non-paginated single-page render
  would show only up to the first break).
- `systemBreaks: [3, 7]` → a `<sb/>` before those measures → **manual line breaks**, with
  **auto pagination retained**. `pageHeight` still controls how many systems fit per page.

If a measure is in both lists, `pageBreaks` wins for that measure (a page break already starts a
new system).

## Implementation (three localized pieces)

### 1. Panola `PanolaMEI.scoreAsMEI`

Signature gains two trailing args:

```
*scoreAsMEI { | voices, changes, clefs = nil, braces = nil, pageBreaks = nil, systemBreaks = nil |
```

In the measure-emitting loop (`nm.do({ |i| ... })`), immediately **before** the
`body = body ++ "<measure n=\"" ++ (i+1) ++ "\">"` line (after the existing mid-section
`<scoreDef>` block), emit the break for measure `i+1` when `i > 0`:

```supercollider
if (i > 0) {
    if ((pageBreaks ? []).includes(i + 1)) { body = body ++ "<pb/>" }
    { if ((systemBreaks ? []).includes(i + 1)) { body = body ++ "<sb/>" } };
};
```

(`<pb/>` supersedes `<sb/>` on the same measure.) A `nil` list is treated as empty, so a score
with no breaks is byte-identical to today.

### 2. MSScore

- New instance vars `<pageBreaks`, `<systemBreaks` with whelk docs.
- `*new` / `init` gain trailing `pageBreaks` / `systemBreaks` args (appended after `changes`, so
  no existing positional arg shifts); assigned in `init`.
- `mei` method passes them through:
  `^Panola.scoreAsMEI(voices, changes ? [( measure: 1, meter: meter, key: key )], clefs, braces, pageBreaks, systemBreaks)`
- Defaults `nil` → byte-identical to today.

### 3. `verovio_render.py` — pick the breaks mode from the MEI

Change `--breaks` default from `"auto"` to `"detect"`, and resolve it before `setOptions` (used
by both the paginate and single-page paths):

```python
breaks = a.breaks
if breaks == "detect":
    try:
        src = open(a.input, encoding="utf-8", errors="ignore").read()
    except OSError:
        src = ""
    breaks = "encoded" if "<pb" in src else ("line" if "<sb" in src else "auto")
```

Use `breaks` (not `a.breaks`) in both `setOptions` calls, and append the resolved mode to the
stdout line (`... (breaks=encoded)`) so tests can assert it. An explicit `--breaks <mode>` still
overrides. No caller changes needed — MusicScene already invokes the wrapper without `--breaks`,
so it gets `detect`.

## Data flow / isolation

Panola emits the break milestones into the MEI; MSScore just forwards two lists; the wrapper
reads the MEI it is handed and self-selects the mode. Each piece has one responsibility and is
testable alone. The addressable per-page pipeline is unaffected — `encoded`/`line` still emit
per-page SVGs, so page tagging, the follow cursor, and `showPage(n)` keep working (verified).

## Out of scope

- Auto-fill *plus* forced page breaks (impossible in Verovio).
- Mid-measure breaks (`<pb>`/`<sb>` are measure-level).
- A MusicXML forced-break path; MusicXML uses different markup, and Panola emits MEI.

## Testing

New `tools/panola_mei/test_page_breaks.py` (sclang → MEI, and the Verovio wrapper):

1. **Emission** — `Panola.scoreAsMEI([Panola("... 6 bars ...")], nil, [\treble], nil, [3], [5])`
   → the MEI string contains `<pb/>` immediately before `<measure n="3"` and `<sb/>` before
   `<measure n="5"`; a call with `nil`/`nil` lists emits neither (byte-identical guard).
2. **Wrapper detect** — run `verovio_render.py --paginate` on
   (a) an MEI with `<pb/>` before m3 → stdout says `breaks=encoded`, 2 pages, page 1 = the 2
   measures before the break; (b) an MEI with only `<sb/>` before m3 → `breaks=line`, still
   auto-paginates; (c) an MEI with neither → `breaks=auto`.
3. **MSScore pass-through** — an `MSScore(..., pageBreaks:[3]).mei` string contains `<pb/>` before
   measure 3 (add to `tools/msscore/`).

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q` (full suite green; scores without breaks
stay byte-identical).

## Docs & example

- whelk docs: the two new args in `PanolaMEI.scoreAsMEI` and `MSScore`, plus a paragraph in each
  `[general]` block covering the manual-pagination tradeoff; regenerate both schelps.
- `CHANGELOG.md` entry.
- SuperCollider example (`examples/supercollider/example_forced_breaks.scd`): a score with
  `paginate: true`, a `pageBreaks` forcing a new page and a `systemBreaks` forcing a new line at
  musical boundaries, viewable with `showPage`. Verify it renders the expected page/system layout.

## Files

- `Classes/PanolaMEI.sc` — signature + break emission + docs.
- `Classes/MSScore.sc` — args + `mei` + docs.
- `HelpSource/Classes/PanolaMEI.schelp`, `HelpSource/Classes/MSScore.schelp` — regenerated.
- `addons/musicscene/tools/verovio_render.py` — `detect` breaks resolution.
- `tools/panola_mei/test_page_breaks.py`, `tools/msscore/` — tests.
- `examples/supercollider/example_forced_breaks.scd` — new example.
- `CHANGELOG.md`.
