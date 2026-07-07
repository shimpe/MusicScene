# Panola MEI meter-aware notation (SP2b v1) — design

**Goal:** Wire `PanolaMeterSplitter` into `PanolaMEI` so **non-tuplet** notes are engraved with robust,
meter-aware splitting — replacing the weak 8-entry `decompose` — so a duration that hides a strong
metrical boundary is broken and tied per the meter. This is the stage that makes SP1/SP2a actually change
the notation.

## Context

Sub-project 2b of the complex-rhythm work. SP1 gave `PanolaDurationSpeller` (quarterLength → spelling);
SP2a gave `PanolaMeter` + `PanolaMeterSplitter` (note → meter-aware tied `SplitComponent`s). SP2b consumes
them inside `PanolaMEI`. **Scope is the `\normal` (non-tuplet) path only**; the explicit-`*m/d` tuplet path
(`groupEvents` → atomic `tupletMEI`) is unchanged — reconciling PanolaMEI's multi-note tuplet *brackets*
with SP2a's per-note tuplet-context splitting is a separate later effort (SP2c).

**Where it lives.** `PanolaMEI.sc` in the **Panola quark** (`scoreAsMEI` / its inner `voiceToMeasures`).
No new classes. Whelk doc comments on the edited `scoreAsMEI` stay current and `HelpSource/` is regenerated
via `gendoc.bat` (see `panola-quark-whelk-docs`).

## The integration

### 1. Meter → `PanolaMeter`
`scoreAsMEI` already has the `meter` String (e.g. `"4/4"`). Parse it to `numerator`/`denominator` and build
`PanolaMeter(numerator, denominator)`, threaded into `voiceToMeasures` (currently `{ |events, bb, k| }` →
add the meter). Additive meters (5/8, 7/8) carry no `groups` in the Panola meter string, so they use
`PanolaMeter`'s simple fallback (every denominator-unit a beat) — correct if not idiomatic; acceptable for
v1.

### 2. Replace `decompose` in the `\normal` path
Keep PanolaMEI's existing **barline split** (`voiceToMeasures` already walks a note across measures with
`take = (bb - pos).min(remaining)`; the splitter is single-measure by contract). For each per-measure
chunk, replace `var pieces = decompose.(take)` with a helper that runs the splitter and flattens its
result:

```
pr_meterPieces(onsetBeats, durBeats, isRest, meter):
    comps = PanolaMeterSplitter.split(( onsetQL: PanolaRational.fromFloat(onsetBeats),
                                        durationQL: PanolaRational.fromFloat(durBeats), isRest: isRest ), meter)
    for each SplitComponent c, for each spelling component x in c.spelling.components:
        emit a fragment ( meidur: x.meidur, dots: x.dots, beats: x.ql.asFloat )
    (if any c.spelling is inexpressible -> warn once and fall back to decompose(c.durationQL.asFloat)
     for that chunk piece -- should not happen for dyadic non-tuplet input)
```

Each fragment feeds the **existing** per-piece emission unchanged: `meiElement.(ev, meidur, dots, tie, k)`
(PanolaMEI's `durAttrs` builds `dur="<meidur>"`, valid for numeric tokens **and** `breve`/`long`/`maxima`),
and `subpos` advances by the fragment's `beats` (the spelling component's exact `ql`, so no `durToBeats`
recomputation is needed and large note types work). Non-tuplet (dyadic) durations always spell as
binary/dotted values with **no inferred tuplet**, so nothing new appears in the note stream.

`decompose` is **retained**, not deleted: it stays as the inexpressible fallback (above) and for
`emptyRest`; only the one `\normal`-path call site (`var pieces = decompose.(take)`) switches to
`pr_meterPieces`. The emitted record keeps a **numeric** `md` (`meidur.asInteger`) for `beamMeasure` while
`meiElement` receives the `meidur` token — so the beam grouping and the `dur=` attribute both stay correct.

### 3. Ties stay the current i/m/t rule
A note split into N total fragments (barline chunks × splitter components × spelling components) ties
`i, m…m, t` — exactly PanolaMEI's current `firstFrag` / `isFirst` / `isLast` logic applied over the
flattened fragment list. The splitter's per-`SplitComponent` `tieFromPrevious`/`tieToNext` flags are *not*
threaded — every fragment of one note is tied, which the existing rule already expresses. A note that
stays a single fragment gets no tie (unchanged).

### 4. Float ↔ rational bridge
PanolaMEI works in Float beats; the splitter in `PanolaRational`. Convert `pos`/`take` with
`PanolaRational.fromFloat` (exact for dyadic non-tuplet beats). `beatPos`/`subpos` tracking stays Float
(from each fragment's `ql.asFloat`). The beam decision (`rec[\md] >= 8`) uses `meidur.asInteger` (numeric
tokens → their value; `breve`/`long`/`maxima` → `0`, so they correctly never beam), while the emitted
`dur=` attribute uses the `meidur` token verbatim.

### 5. Unchanged
- The explicit-`*m/d` **tuplet path** (`groupEvents` → `tupletMEI`, atomic, warn on barline-cross).
- **Beaming** (`beamMeasure` groups runs of `md >= 8` per beat-group) — operates on the emitted
  `md`/`beatPos` records, which the new fragments still provide.
- **`@dyn`/`@art`/`@slur`** attachment (recorded at the note onset `pos`, independent of how the note is
  split).
- Rest handling: whole-measure rests (`emptyRest`) may optionally route through the splitter too, for
  consistency; a plain rest note splits rhythmically the same way (no ties on rests).

## Testing

Via the `tools/panola_mei/` sclang → MEI → Verovio harness (`render_check.py` counts notes / ties / tuplets
/ beams). New assertions for the meter-aware behavior:

- A half note starting mid-measure in 4/4 (`c5_4 c5_2 c5_4` — the middle half note spans beats 2–3, hiding
  the 4/4 midpoint) now engraves as tied notes across the midpoint rather than one half note.
- A note crossing a beat (e.g. an eighth-plus-quarter syncopation) splits at the beat and ties.
- A note that legitimately spans only weaker boundaries (a half note on beat 1, a dotted quarter within a
  beat) stays a single note (anti-over-split — the onset-strength rule).
- Barline-crossing notes still auto-tie (regression), now additionally beat-split within each measure.
- Tuplets (`*m/d`) render exactly as before (unchanged path).
- `<tuplet>`/dynamics/articulation/slur tests are unaffected.

**Regression caveat.** For *simple, non-crossing* durations the splitter reproduces the old `decompose`
output, so most existing `tools/panola_mei` tests are unchanged. But for notes that **cross a beat/barline**
the splitter legitimately splits *differently (better, meter-aware)* than the old greedy `decompose`, so a
few existing expected-MEI assertions may need updating to the improved output. Each such change must be
individually verified as a correct meter-aware improvement (not a regression) — the plan calls this out and
shows the before/after for every changed assertion.

## Scope

- **In (SP2b v1):** build `PanolaMeter` from the score meter; route the `\normal` (non-tuplet) path through
  `PanolaMeterSplitter` (replace `decompose`), flattening spellings to the existing fragment emission;
  keep ties/beaming/dyn-art-slur; float↔rational bridge; inexpressible fallback; whelk docs + regenerated
  schelp; new + updated `panola_mei` tests.
- **Out (SP2c / later):** routing explicit-`*m/d` tuplets through the splitter (barline-crossing tuplets,
  beat-splitting inside a bracket, reconciling multi-note brackets with per-note tuplet contexts); additive
  `groups` from the meter string; nested tuplets; any playback change.
