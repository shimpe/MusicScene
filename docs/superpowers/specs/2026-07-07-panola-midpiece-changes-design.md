# Panola mid-piece meter / key / clef changes (SP2f) — design

**Goal:** Let a score change its **meter** and **key** at measure boundaries, and its **clef** anywhere
(mid-measure), instead of one fixed meter/key/clef for the whole piece. Meter+key are given as a
score-level `changes` list; clef changes are inline per-note in the Panola stream.

## Context

The last big complex-rhythm/notation piece. Today `PanolaMEI.scoreAsMEI(voices, meter, key, clefs, braces)`
takes one constant `meter`, one `key`, and a fixed `clefs` per staff, and emits a single top `<scoreDef>`.
The SP2e work already made the meter a self-contained **descriptor** consumed per-measure, precisely so
per-measure lookup would be a clean addition — this realizes it, and extends it to key and (inline) clef.

**Where it lives.** `PanolaMEI.sc` (Panola quark): `scoreAsMEI` (new signature + per-measure descriptors),
`voiceToMeasures` (variable bar lengths + per-measure key), `eventsOf`/`meiElement` (inline `@clef`), and
the `<scoreDef>` emission. Also `Panola.asMEI` (convenience) and `MSScore` (its meter/key/clefs surface).
Whelk docs + `gendoc.bat`.

## The API

`scoreAsMEI(voices, changes, clefs, braces)`:

- **`changes`** — an Array of change Events applied at the **start** of their (1-based) measure; any field
  omitted inherits the current value. The first entry (measure 1) supplies the initial meter+key.
  ```
  changes = [ ( measure: 1, meter: "4/4", key: \Cmajor ),
              ( measure: 5, meter: "3/4" ),          // meter change; key carries over
              ( measure: 9, key: \Gmajor ) ]         // key change; meter carries over
  ```
- **`clefs`** — the **initial** clef per staff (`[\treble, \bass]`), as today. Mid-piece clef changes are
  inline (below), not in `changes`.
- **`braces`** — unchanged.

The old `meter`/`key` scalar args are removed. `changes` compiles once into per-measure lookups
`meterFor(i)` (the SP2e descriptor: `count/num/den/groups/bb/groupStarts/pmeter`) and `keyFor(i)` (a key
Symbol), by carrying each field forward from the last change at-or-before measure `i`. If no entry names
measure 1, the initial meter/key default to `"4/4"`/`\Cmajor`.

**Inline clef** — a note tagged **`@clef^bass^`** (or `\treble`/`\alto`/`\tenor`) switches that voice's staff
to the named clef **at that note**, mid-measure allowed. It uses Panola's existing custom-property channel:
`eventsOf` reads `customPropertyPattern("clef", "")` into `e[\clef]`, and the note's emission prepends an
inline `<clef shape="…" line="…"/>` (from `clefMap`) before the `<note>`. The initial clef is still the
`clefs` arg; `@clef` changes it from there. `@clef` on a note that gets split into tied fragments attaches
to the first fragment.

## Mechanisms

### Meter change (the hard one) — variable bar lengths
`voiceToMeasures` currently splits notes at barlines with a constant `bb` and one `pmeter`. It is reworked
to consult the **current measure's** descriptor: the barline-split loop uses `meterFor(measures.size)[\bb]`
for `take = (bb - pos).min(remaining)`, and `meterPieces`/splitting uses that descriptor's `pmeter`; when a
measure fills and a new one begins, the next measure's `bb` is looked up. So from bar 5 a `3/4` is 3
quarter-beats, split and beamed per `3/4`. `beamMeasure` already takes `groupStarts` per measure (SP2e), so
it receives `meterFor(i)[\groupStarts]`.

### Key change — per-measure key
`meiElement` spells accidentals via `accidInKey(pname, accid, k)`, so each measure's notes must be emitted
with `keyFor(i)`, not one global key. `voiceToMeasures` threads the per-measure key into `meiElement`. The
key signature change is emitted as a mid-`<section>` `<scoreDef key.sig="…"/>` before the change measure.

### Clef change — inline element
At a note carrying `@clef`, emit `<clef shape line/>` immediately before the `<note>` in that staff's layer.
No layout impact (durations/beaming/measures are unchanged); it is a display element in the note stream.

## MEI emission

The top `<scoreDef>` carries measure-1's meter/key + the staffGrp with the initial `clefs`. For each later
measure `i` whose meter or key differs from `i-1`, emit a `<scoreDef>` (with the changed `meter.count`/
`meter.unit` and/or `key.sig`) **inside `<section>` just before that `<measure>`**. Inline `<clef>` elements
live inside the measure's staff/layer at the tagged note.

## Migration (the API break)

- `PanolaMEI.scoreAsMEI` — new `(voices, changes, clefs, braces)` signature.
- `Panola.asMEI(meter, key, clef)` — routed through a one-entry `changes` (`[(measure:1, meter:, key:)]`).
- `MSScore` — its `meter:`/`key:` args become a `changes` surface (keep a simple constant form + allow the
  list); `clefs:` stays. Thread through to `scoreAsMEI`.
- Every `tools/panola_mei` test and `examples/*.scd` — updated to the new call form.

## Phasing (the plan)

- **Phase A — `changes` structure + key change + migration.** Introduce `changes`, `meterFor`/`keyFor`, and
  the mid-`section` `<scoreDef>` emission for the **key change**. `voiceToMeasures` still uses the measure-1
  meter for a constant `bb` (a meter *change* in the list has no layout effect yet — that's Phase B), while
  `keyFor(i)` is per-measure. Migrate all callers. Delivers key changes.
- **Phase B — meter change.** Rework `voiceToMeasures` for variable `bb`/`pmeter` per measure.
- **Phase C — inline clef.** `@clef` custom property → inline `<clef>` (independent of `changes`).

## The hard invariant

A `changes` list with a **single measure-1 entry** and no `@clef` reproduces today's output
**byte-for-identically** for every existing case (once the call is migrated to the new form): one top
`<scoreDef>`, no mid-section scoreDefs, no inline clefs, the same per-measure `meterFor`/`keyFor` = the
constant values.

## Testing

Via `tools/panola_mei/`:
- **Key change:** `changes` with a `key` change at bar 3 → a mid-`section` `<scoreDef key.sig="1s"/>` before
  measure 3, and accidentals from bar 3 spelled in the new key; renders.
- **Meter change:** `4/4` then `3/4` at bar 3 → bar 3+ are 3 quarter-beats (note that would overflow a 4/4
  bar now fits a 4/4 then a 3/4), a mid-section meter `<scoreDef>`, correct barlines; renders.
- **Clef change (mid-measure):** a voice with `@clef^bass^` mid-bar → an inline `<clef shape="F" line="4"/>`
  before that note; renders.
- **Combined:** meter+key change at the same bar → one mid-section `<scoreDef>` with both.
- **Regression / invariant:** every existing `panola_mei` case, migrated to a single measure-1 `changes`
  entry, is byte-identical; the full suite green.

## Scope

- **In (SP2f):** measure-boundary meter+key changes via `changes`; mid-measure clef via inline `@clef`; the
  API migration; whelk docs + regenerated schelp; tests.
- **Out (later):** mid-measure meter or key changes; adding/removing staves or voices mid-piece; per-voice
  (rather than score-level) meter/key; transposing on a key change (accidentals stay as authored, respelled
  only for display); any playback change.
