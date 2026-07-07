# Panola meter-aware note splitting engine (SP2a) — design

**Goal:** A standalone routine that takes a note's onset + duration in a measure of a given time
signature and splits it into **tied, spelled components that respect the meter** — so a duration that
hides a strong metrical boundary is broken and tied instead. It answers *"where should this duration be
broken into tied notes so the notation matches the meter?"*, on top of SP1's *"how is this duration
spelled?"*.

## Context

This is **sub-project 2a** of "music21-style complex-rhythm support" for Panola notation. SP1 gave
`PanolaDurationSpeller` (quarterLength → a `SpelledDuration`) and `PanolaRational` (exact rationals). SP2a
adds the metrical layer; **SP2b** (a separate, later spec) wires it into `PanolaMEI` (replacing the weak
`decompose`, emitting tied MEI + `<tuplet>`, reconciling with the existing explicit-`*m/d` tuplet path and
per-beat beaming).

The full algorithm is the reference pseudo code the user supplied ("Implement meter-aware note splitting
for difficult rhythms", Parts 1–12); this spec is its SuperCollider realization, decisions, and scope. It
is **notation-only** and exact by default (quantization is opt-in, never implicit).

**Where it lives.** The **Panola quark**, two new class files: `Classes/PanolaMeter.sc` (the metric
boundary hierarchy) and `Classes/PanolaMeterSplitter.sc` (the splitter). MEI-agnostic; consumes
`PanolaDurationSpeller` + `PanolaRational`. Whelk doc comments on both, regenerated via `gendoc.bat` (see
`panola-quark-whelk-docs`). No change to existing Panola/PanolaMEI code in SP2a.

## Public API

- `PanolaMeter(numerator, denominator, groups)` — build a meter; `groups` (Array of eighth-counts) is
  optional and only used for additive meters (e.g. `[2,2,3]` for 7/8). Exposes `measureLengthQL`
  (`PanolaRational`) and `boundaries` (the sorted, strength-ranked `MetricBoundary` list).
- `PanolaMeterSplitter.split(noteEvent, meter, options)` — the entry point (`notateTimedNote`). Returns an
  **Array of `SplitComponent` Events**, in time order, that tie together and sum exactly to the input
  duration. A convenience `*split` builds default options.

## Data structures (lightweight Events, matching the SP1 result style)

```
noteEvent = ( onsetQL: <PanolaRational>, durationQL: <PanolaRational>, isRest: false, tupletContext: nil )
tupletContext (optional) = ( startQL: <PanolaRational>, totalDurationQL: <PanolaRational>,
                             numberNotesActual: 3, numberNotesNormal: 2 )
meter     = a PanolaMeter
boundary  = ( offsetQL: <PanolaRational>, strength: 100, label: "measure-start" )   // higher = stronger
splitComp = ( startQL: <PanolaRational>, durationQL: <PanolaRational>, spelling: <SpelledDuration>,
              tieFromPrevious: false, tieToNext: true, isRest: false )
```

`spelling` is exactly a `PanolaDurationSpeller` result Event. All offsets/durations are `PanolaRational`.
Ties use `tieFromPrevious`/`tieToNext` (clearer than tieStart/tieStop): first piece
`tieToNext:true`; middle pieces both true; last `tieFromPrevious:true`; rests are split rhythmically but
carry **no** ties.

## Part 1 — the metric boundary hierarchy (`PanolaMeter`)

`buildMetricBoundaries` produces a strength-ranked boundary list (`measure-start`/`measure-end` = 100;
the 4/4 half-measure at offset 2.0 = 80; ordinary beats = 60; compound beats = 70; additive groups = 75;
subdivisions = 30–40), per the pseudo code:

- **Simple meter** (`isSimpleMeter`): beat length = `4/denominator`; a beat boundary per beat, strengths
  from `beatBoundaryStrength` (4/4 midpoint 80, else 60; 2/x → 70; 3/x → 60); plus subdivision boundaries
  (strength 30).
- **Compound meter** (`isCompoundMeter`: `numerator % 3 == 0 and numerator > 3 and denominator in {8,16}`):
  dotted beats of length `3·(4/denominator)`, strength 70; eighth sub-beats strength 40.
- **Additive meter** (numerator not simple/compound, or `groups` supplied): group boundaries from `groups`
  (strength 75) with interior subdivisions.

Strengths are integers; offsets are `PanolaRational` (exact). The list is sorted by offset and de-duped
(a boundary present at two strengths keeps the max). `PanolaMeter` caches its boundaries.

## Parts 3–6 — splitting (onset-strength rule, then a cost model for the rest)

The core metrical rule — which matches **every** Part 5 and Part 9 example — is **onset-strength
gating**: a note may span boundaries no stronger than the boundary at its own onset, but must break at any
interior boundary *stronger* than its onset. A half note at offset 0 (strength 100) may span the beat-1
boundary (60) and stays a half note; a note at offset 1.5 (a subdivision, strength 30) reaching past the
2.0 half-measure (80) must split there. This reconciles the pseudo code's cost model with its own Part 5
examples — a pure hidden-boundary penalty would wrongly split the `0→2` half note.

The splitter therefore:

1. **Onset strength** = the strength of the boundary **exactly at** `onsetQL` (a note at 1.5 in 4/4 is a
   subdivision → 30), or `0` if the onset falls between boundaries (then every stronger interior boundary
   splits). **Mandatory** split points = interior boundaries with
   `strength > onsetStrength` that are permitted by the `splitAt*` policy flag for their level, plus any
   `strength >= 90` (measure / tuplet-container edges). Splitting at these is required and already yields
   a correct, meter-respecting split.
2. The onset-strength rule already fixes every mandatory split, and every remaining *optional* boundary is
   **weaker** than the note's onset (a policy-allowed boundary stronger than the onset is already
   mandatory) — so a candidate/cost search over the optional boundaries would never choose to split there
   (it only adds ties with no readability gain). SP2a therefore **omits** the full candidate+cost model;
   dot-vs-tie readability is handled by the spelling engine plus the optimization pass (Part 11). *(The
   source pseudo code's Parts 5–6 cost model is deferred as an optional future refinement — it would
   matter only under advanced options that make sub-beat boundaries mandatory-eligible.)*
3. If no candidate is fully spellable, `fallbackSplitAggressively` then `splitAtSmallestGrid` (Part 8).

Defaults (Part 12): `splitAtMeasureBoundaries/BeatBoundaries/TupletBoundaries = true`,
`splitAtStrongSubBeatBoundaries = false`, `allowSyncopation = false`, `maxSplitPieces = 12`,
`greedyMinBoundaryStrength = 60`, `dotBoundaryThreshold = 80`, `tieCost = 10`, `dotCost = 2`,
`tupletCost = 20`, `hiddenBoundaryCostFactor = 1.0`, `syncopationPenalty = 40`, spelling options
exact/maxDots 4/maxComponents 16/allowLargeTuplets false/minNoteType 2048th.

## Part 7 — tuplet-contained notes (preserve tuplets as containers)

When `noteEvent.tupletContext` is set, `split` routes to `splitTupletContainedNote`: build the tuplet's
local grid (`buildTupletBoundaries`: `numberNotesActual+1` boundaries across `totalDurationQL`, edges
strength 90, interior 50), **merge** with the meter boundaries, choose split points on the merged set, and
spell each piece *inside the tuplet* (each fragment is a tuplet member, spelled with its tuplet, not
rewritten as a non-tuplet duration). This is what makes a triplet crossing a beat come out as two tied
triplet-eighths (Example 4) rather than an odd binary value. **Onset strength for a tuplet-contained note
is measured against the *meter* boundaries only** (not the merged tuplet+meter set): a mid-tuplet onset is
metrically weak (0), so every tuplet grid line it crosses splits it; measuring against the merged set
would read the onset's own grid strength (50) and block the split at the equally-strong next grid line.

## Part 8 — fallbacks

`fallbackSplitAggressively`: split at every boundary with `strength >= greedyMinBoundaryStrength`, spell,
tie; if any piece is still unspellable, `splitAtSmallestGrid` chops the span into `minNoteType`-sized
pieces from the onset (many ties, but never an impossible single duration). Both are exact.

## Part 11 — optimization pass

After splitting, `optimizeSpelling` applies local cleanups: `mergeAdjacentPiecesIfSafe` (merge two pieces
when the merged span hides no strong boundary and spells cleanly — undoes needless splits),
`avoidDotsAcrossStrongBoundaries` (a dotted value that hides a `strength >= dotBoundaryThreshold` boundary
is re-split), and `simplifyTupletSpellings`. Value is preserved exactly throughout.

## Quantization

`prepareInput` (Part 3/7): when `quantizeMode == \grid`, snap onset and end to `quantizeGrid` **only if**
within `quantizeTolerance`, then split the snapped event; otherwise pass the exact event through. Never
implicit. (Snapping reuses the same grid logic as SP1's speller quantize.)

## Options + defaults

An options Event holding the Part-12 defaults plus a nested `durationSpellingOptions` Event passed to
`PanolaDurationSpeller`. `*split(noteEvent, meter)` uses the defaults; callers override by key.

## Testing

Headless sclang (the `tools/` Panola harness). The Part 9 Examples become direct assertions:

- **Ex1** 4/4, onset 1.5, dur 1.0 → eighth + eighth (crosses the 2.0 midpoint) — two components, tied.
- **Ex2** 6/8, onset 1.0, dur 1.0 → eighth + eighth (crosses the 1.5 compound beat).
- **Ex3** 7/8 `[2,2,3]`, onset 0.5, dur 2.0 → eighth + quarter + eighth (crosses the 1.0 and 2.0 groups).
- **Ex4** triplet-eighth grid, onset 4/3, dur 2/3 (tupletContext 3:2 over 1.0–2.0) → two tied triplet
  eighths (each a `1/3`-QL component carrying the 3:2 tuplet), **not** a binary value.
- **Ex5** 4/4, onset 1.5, dur `0.6249852340957234`: exact → the crossed-2.0 split with the tail piece
  inexpressible/difficult (preserved, not snapped); quantize (grid 1/512, tol 2e-5) → eighth + 32nd.
- **Onset-strength rule (anti-over-split):** 4/4 onset 0.0 dur 2.0 → a single half note (spans only the
  weaker beat-1 boundary, 60 < onset 100); onset 0.0 dur 1.5 → a single dotted quarter (spans only the
  weaker beat-1 boundary; `dotBoundaryThreshold` 80 keeps it un-split); onset 1.0 dur 2.0 → quarter +
  quarter (must break at the 2.0 half-measure, 80 > onset 60).
- **Boundary hierarchy** unit tests: `PanolaMeter(4,4).boundaries`, `(6,8)`, `(3,4)`, `(7,8,[2,2,3])`
  produce the offsets/strengths in the pseudo code's tables.
- **Sum-exactness / ties:** every split's components sum exactly to the input `durationQL`; tie flags
  follow the first/middle/last rule; rests carry no ties.
- **Fallback:** a pathological duration exercises greedy → smallest-grid without crashing.

## Public API summary

New classes only. `PanolaMeter` (`*new(num, den, groups)`, `measureLengthQL`, `boundaries`) and
`PanolaMeterSplitter` (`*split(noteEvent, meter, options)` / `split`). No change to existing Panola classes.

## Scope

- **In (SP2a):** `PanolaMeter` boundary hierarchy (simple/compound/additive); `PanolaMeterSplitter` with
  the onset-strength split rule, tuplet-contained splitting, greedy/smallest-grid fallbacks, the
  optimization pass, exact/quantize; whelk docs + regenerated schelp (gendoc.bat); the full test suite.
- **Phasing (the plan, not the spec):** build a **correct** splitter first — boundaries → onset-strength
  split → spell → tie → tuplet-containers → fallback (Parts 1–4, 7, 8) — green against the Examples, then
  layer the **optimization pass** (Part 11). One spec, phased plan.
- **Out (SP2b / later):** `PanolaMEI` integration (replacing `decompose`, emitting tied MEI + `<tuplet>`
  from `SplitComponent`s, reconciling with the explicit-`*m/d` tuplet path and beaming); the full Parts
  5–6 candidate/cost model (subsumed here by the onset-strength rule + optimization pass); nested tuplets;
  cross-voice/context boundaries; any change to playback.
