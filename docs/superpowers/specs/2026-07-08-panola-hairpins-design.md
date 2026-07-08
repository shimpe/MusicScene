# Hairpins (crescendo / decrescendo) in Panola notation — Design

**Date:** 2026-07-08
**Component:** Panola quark (`PanolaMEI.sc`); MusicScene example + docs
**Status:** Approved (brainstorm)

## Goal

A `@hairpin` property in a Panola string renders an MEI `<hairpin>` — a spanning
crescendo/decrescendo mark:

```
c5_4@hairpin^cresc^ d5 e5 f5@hairpin^end^     // -> <hairpin form="cres" tstamp="1" tstamp2="0m+4" staff="1"/>
```

A hairpin is **structurally a slur** (spans a start point to an end point with `tstamp` /
`tstamp2`) but **semantically a dynamic** (expression). MEI:
`<hairpin form="cres|dim" tstamp tstamp2 staff/>`. The implementation therefore mirrors the
existing slur machinery in `PanolaMEI.sc`, adding a `form` (direction).

## Background: the two existing mechanisms it borrows from

- **`@slur` (spanning-mark model — the template).** `eventsOf` reads `e[\slur]` per note;
  `voiceToMeasures` keeps `openSlur` + a `slurs` list via `applySlur` (`start` / `end` /
  `endstart`), recording `(startMeasure, startTstamp, endMeasure, endTstamp)`. `applySlur` is
  invoked at **every** note-placement site (normal placement, tuplet-completion members and
  donor, bucket-split `pendSlur`, barline-crossing), and split remainders clear `\slur`. Output
  emits `<slur tstamp tstamp2 staff/>` in the **start** measure. `tstamp2` is `"Nm+beat"` where
  `N` = full measures after the start measure (`0m` = same measure).
- **`@dyn` (point-mark model).** `annotateExpression` emits `ev[\dynMark]` on change →
  `<dynam tstamp staff>mark</dynam>`. (Not the model here, but confirms hairpins live in the
  same expression family and are notation-only.)

## Input syntax

`@hairpin` mirrors `@slur`, with the direction carried on the start (and on the chain form,
which a bare `endstart` cannot express):

| Value | Meaning | MEI |
|-------|---------|-----|
| `cresc` / `crescendo` | open a crescendo | `form="cres"` |
| `dim` / `decresc` / `decrescendo` / `diminuendo` | open a diminuendo | `form="dim"` |
| `end` | close the open hairpin | — |
| `endcresc` | close the open hairpin **and** open a crescendo here | `form="cres"` |
| `enddim` | close the open hairpin **and** open a diminuendo here | `form="dim"` |

`endcresc` / `enddim` express *messa di voce* (`< >` or `> <`) at a shared boundary note —
the analogue of slur's `endstart`, but a hairpin's new span needs a direction, so it is baked
into the value rather than left as a bare `endstart`.

## Semantics & constraints (same discipline as slurs)

- **One open hairpin per voice.** Opening (`cresc`/`dim`/`endcresc`/`enddim`) while one is
  already open closes/records nothing extra for a plain open — it warns and drops the previous
  open (mirrors `applySlur`'s "slur start while a slur is open" behavior). `endcresc`/`enddim`
  with an open hairpin close it normally then open the new one.
- **`end` / `endcresc` / `enddim` with nothing open** → warn; `end` is then a no-op, while
  `endcresc`/`enddim` still open the new hairpin (mirrors slur `endstart`-with-none: "only
  opening a new one").
- **Unclosed hairpin at voice end** → warn + drop (mirrors the unclosed-slur warning).
- **Independent of `@dyn` and `@slur`.** A note may carry `@dyn`, `@slur`, and `@hairpin`
  together. A hairpin never auto-closes at a `@dyn` — closing is explicit only.
- **Notation only.** No playback effect (matches `@dyn` / `@art`); `@pdur` still drives
  loudness. `asPbind` already passes any word-valued property (incl. `hairpin`) through as a
  symbol, so a voice carrying `@hairpin` still plays.

## Implementation (a near-copy of the slur plumbing in `PanolaMEI.sc`)

1. **`eventsOf`** — add `e[\hairpin] = panola.customPropertyPattern("hairpin", "").asStream.all[i]`
   (next to the existing `slur` / `clef` extraction).
2. **`voiceToMeasures`** — add locals `openHairpin = nil, hairpins = [], applyHairpin`. A small
   value→form helper maps the vocabulary above (unknown value → warn). `applyHairpin.(val, m, ts)`:
   - `cresc`/`dim`: warn if `openHairpin.notNil` (drop it), then `openHairpin = ( measure:, tstamp:, form: )`.
   - `end`: if open, record `( startMeasure, startTstamp, endMeasure, endTstamp, form )` and clear; else warn.
   - `endcresc`/`enddim`: if open, record the closing span; (warn if none); then open a new one of that form.
   Call `applyHairpin.(ev[\hairpin] ? "", measure, tstamp)` at **every** site `applySlur` is
   called (normal, tuplet-completion members + donor, bucket-split — added to the `pendSlur`
   analogue `pendHairpin`, and barline-crossing). Clear `\hairpin` wherever `\slur` is cleared
   on split remainders. At voice end, warn on an unclosed `openHairpin`.
3. **Result event** — return `( measures:, dynams:, slurs:, hairpins: )` (add `hairpins`).
4. **Output** — mirror the `<slur>` emit block: for each hairpin whose `startMeasure == i+1`,
   emit `<hairpin form="<form>" tstamp="<t1>" tstamp2="<N>m+<t2>" staff="<s+1>"/>`.

Isolation: this is one new spanning-mark tracked identically to slurs; it touches only
`voiceToMeasures` (add a parallel tracker) and the output loop (add a parallel emit). No change
to duration/meter/tuplet logic beyond threading `applyHairpin` through the same call sites.

## Out of scope

- Playback dynamics (a hairpin does not ramp synth amplitude).
- Auto-close at the next `@dyn`; hairpin↔dynamic vertical alignment niceties.
- Multiple simultaneous overlapping hairpins in one voice (one-at-a-time, like slurs).
- MSScore API changes (none — it calls `Panola.scoreAsMEI`, inheriting hairpins for free).

## Testing

Add `mei.count("<hairpin ")` as `hairpins` in `tools/panola_mei/render_check.py`. New
`tools/panola_mei/test_hairpins.py` (modeled on `test_slurs.py` — sclang → MEI → Verovio,
assert on exact strings + `p["ok"]`):

1. **within** — `c5_4@hairpin^cresc^ d5 e5 f5@hairpin^end^ g5` → one `<hairpin form="cres" tstamp="1" tstamp2="0m+4" staff="1"/>`.
2. **dim + synonym** — `@hairpin^decrescendo^ … @hairpin^end^` → `form="dim"`.
3. **crossbar** — start bar 1, end bar 2 → `tstamp2="1m+…"`.
4. **messa di voce** — `@hairpin^cresc^ … @hairpin^enddim^ … @hairpin^end^` → two hairpins,
   `form="cres"` then `form="dim"`, with the shared boundary tstamp.
5. **coexist** — same notes carry `@dyn` and `@slur` and `@hairpin`; all three render.
6. **unmatched `end`** → zero hairpins (warned); **unclosed open** → zero hairpins (warned).
7. **twovoice** — a hairpin on staff 2 → `staff="2"`.

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q` (full suite green).

## SuperCollider example

Per the standing rule that every feature ships with a runnable example
([[illustrate-features-in-examples]]): extend
`examples/supercollider/example_panola_score.scd` (already the expression showcase — it uses
`@dyn`, `@slur`, `@art`) to add a crescendo and a diminuendo (a *messa di voce* over one
phrase reads clearly), with a one-line header note on `@hairpin`. Verify it renders the marks
by dumping the MEI via `Panola.scoreAsMEI` and grepping for `<hairpin form="cres"` and
`<hairpin form="dim"`.

## Docs

Update the `[general]` doc-comment in `PanolaMEI.sc` (mention `@hairpin` alongside the `@slur`
sentence) and the `scoreAsMEI` prose, then regenerate schelp via `gendoc.bat` (`Done.`, no
`ERROR`). Bring `CHANGELOG.md` a new entry when shipped, and mark hairpins done in
`docs/superpowers/BACKLOG.md`.

## Files

- `Classes/PanolaMEI.sc` — `eventsOf`, `voiceToMeasures` (tracker + call sites), output loop, `[general]` doc.
- `HelpSource/Classes/PanolaMEI.schelp` — regenerated.
- `tools/panola_mei/render_check.py` — `hairpins` count.
- `tools/panola_mei/test_hairpins.py` — new tests.
- `examples/supercollider/example_panola_score.scd` — hairpin showcase.
- `CHANGELOG.md`, `docs/superpowers/BACKLOG.md` — on ship.
