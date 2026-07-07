# Panola duration spelling engine (SP1) — design

**Goal:** A standalone, music21-style routine that maps a single numeric duration in **quarterLength**
units to a valid **notation spelling** — one or more components, each a note value + dots + optional
tuplet — using exact rational arithmetic. Pure function of a quarterLength; no score/meter context.

## Context

This is **sub-project 1** of "music21-style complex-rhythm support" for Panola notation. Panola already
produces an exact quarterLength per note (base value + dots + `*m/d` tuplet ratio); the current MEI
generator notates a duration with a limited 8-entry greedy `decompose` (whole→16th + three dotted values)
that floors at the 16th and silently drops any remainder it cannot match. This sub-project replaces that
core with a robust spelling engine.

- **SP1 (this spec):** the spelling engine — `quarterLength → SpelledDuration | Inexpressible`. MEI-agnostic,
  exhaustively unit-testable in isolation.
- **SP2 (separate, later):** meter-based splitting + `PanolaMEI` integration — split a note's duration at
  barlines/beats per the meter, call SP1 to spell each piece, emit tied MEI notes/tuplets, and reconcile
  with the existing explicit-`*m/d` tuplet path and per-beat beaming.

**Notation-only.** Playback (`asPbind`) keeps using the raw numeric beats and is untouched.

**Where it lives.** The **Panola quark**, two new class files: `Classes/PanolaRational.sc` and
`Classes/PanolaDurationSpeller.sc`. Whelk doc comments on both, `HelpSource/` regenerated via gendoc (see
`panola-quark-whelk-docs`). No change to existing Panola/PanolaMEI code in SP1.

## PanolaRational — exact rational arithmetic

SuperCollider has no rational type, and the algorithm must not treat notation as floating point, so SP1
introduces a minimal exact rational.

- **Representation:** `num` (Integer), `den` (Integer > 0), always reduced by `gcd`, sign carried in `num`.
  `*new(num, den)` reduces and normalizes the sign; `den == 0` throws (callers never produce it).
- **Constructors:** `*new(num, den)`, `*fromInteger(n)` (= `n/1`), `*fromFloat(x, maxDenom = 65536)`.
- **`*fromFloat`** implements `limit_denominator` via the continued-fraction / Stern-Brocot method (the
  classic CPython `Fraction.limit_denominator` algorithm), so `0.3333333` → `1/3`, `0.4` → `2/5`, etc.
  (SuperCollider has no reliable `asFraction`, so this is implemented, with a small unit test against
  known values.)
- **Operators / methods:** `+ - * /` (rational-exact), `== < <= > >=`, `reciprocal`, `negate`, `isNegative`,
  `asFloat`, `asString` (`"num/den"`), `abs`, `floorDiv`/`frac` as needed by quantization.
- All spelling arithmetic and all comparisons in the engine are on `PanolaRational`, never on floats.

## PanolaDurationSpeller — the engine

- Constructed with an **options** Event (defaults below): `PanolaDurationSpeller.new(options)`.
- **`spell(ql)`** — `ql` may be a `PanolaRational`, an Integer, a decimal String (parsed as an exact
  decimal fraction), or a Float (normalized to a rational via a limit-denominator continued fraction,
  capped at `maxDenominator`). Returns a **spelling Event** (below).
- Class-method convenience **`*spell(ql, options)`** builds a speller with defaults (merged with any given
  options) and calls `spell`.

### Note-type table

Note-type name → base quarterLength (as `PanolaRational`) and → MEI `dur` convenience token:

| type | quarterLength | mei dur |
|---|---|---|
| `duplexMaxima` | 64 | *(none — see below)* |
| `maxima` | 32 | `maxima` |
| `longa` | 16 | `long` |
| `breve` | 8 | `breve` |
| `whole` | 4 | `1` |
| `half` | 2 | `2` |
| `quarter` | 1 | `4` |
| `eighth` | 1/2 | `8` |
| `16th` | 1/4 | `16` |
| `32nd` | 1/8 | `32` |
| `64th` | 1/16 | `64` |
| `128th` | 1/32 | `128` |
| `256th` | 1/64 | `256` |
| `512th` | 1/128 | `512` |
| `1024th` | 1/256 | `1024` |
| `2048th` | 1/512 | `2048` |

Note-type names that begin with a digit are not valid `\symbol` literals in SuperCollider, so they use the
quoted-symbol form (`'16th'`, `'32nd'`, … `'2048th'`); the letter-leading ones (`\eighth`, `\quarter`, …)
use the bare form. Tests and the result schema follow this.

The engine is a pure notation model; the `meidur` token is a convenience so SP2's MEI emission is a lookup.
`duplexMaxima` (64) is included for spelling completeness but has no single MEI `dur` token (MEI's largest
is `maxima`); its `meidur` is `nil` and SP2 would tie two maximas if ever needed — an SP1 non-concern.

### Options + defaults

```
( mode: \exact,            // \exact | \quantize
  grid: PanolaRational(1, 512),
  tolerance: 1e-5,          // Float, used only in \quantize mode
  maxDots: 4,
  maxComponents: 16,
  maxTupletActual: 13,
  maxTupletNormal: 13,
  allowLargeTuplets: false,
  maxLargeTupletActual: 1024,
  maxLargeTupletNormal: 1024,
  minNoteType: \2048th,
  maxDenominator: 65536 )
```

### Algorithm (music21-style, ordered)

`spell(ql)`:

1. **Normalize** `ql` to a `PanolaRational` (`normalizeToRational`): Rational→as-is; Integer→n/1; decimal
   String→exact decimal fraction; Float→`PanolaRational.fromFloat(x, maxDenominator)` (the exact dyadic
   fraction with its denominator limited to `maxDenominator`, so e.g. `0.3333333`→`1/3`).
2. **Guards:** `ql` NaN/∞/negative → `inexpressible` with the matching reason. `ql == 0` → empty spelling
   (`components: []`), used for grace/zero durations.
3. **Quantize** (only if `mode == \quantize`): `ql = quantizeToGrid(ql, grid, tolerance)` — snap to the
   nearest grid multiple **only if** within `tolerance`, else leave `ql` unchanged. Never implicit.
4. **trySimpleDuration** — exact match to a note-type base value → single component, `dots 0`.
5. **tryDottedDuration** — for each note-type, `dots` in `1..maxDots`, `dottedValue(base, dots)` (general
   formula `total = base + Σ base/2^i`) == `ql` → single dotted component.
6. **splitIntoComponents** — greedy: repeatedly take `findLargestAssignableAtMost(remaining)` (largest
   simple-or-dotted value ≤ remaining, searching all note-types and `dots 0..maxDots`), subtract, append.
   Fails (returns none) if a step finds nothing or `components > maxComponents`. Multiple components =
   tied notes. **Tried before the tuplet step:** a *dyadic* duration (denominator a power of two, e.g.
   `0.625`, `1.25`) decomposes into tied ordinary notes; only non-dyadic values (`1/3`, `1/5`, …), which
   cannot be split into binary/dotted notes, fall through to the tuplet step. *(This orders split before
   tuplet — a deliberate refinement of the source pseudo code's stated order, so the Expected-examples
   hold: `0.625` → eighth+32nd, not an 8:5 tuplet.)*
7. **tryTupletDuration** — for each note-type base and `actual` in `2..maxTupletActual`, `normal` in
   `1..maxTupletNormal` (`actual != normal`), `base * normal / actual == ql` → candidate single component
   with one tuplet descriptor. Rank candidates (below) and return the best.
8. **tryLargeTupletFallback** (only if `allowLargeTuplets`) — represent the whole `ql` as one large tuplet:
   for each note-type base, `ratio = ql / base`; `normal, actual = ratio.num, ratio.den`; accept if
   `actual ≤ maxLargeTupletActual and normal ≤ maxLargeTupletNormal`. Correct-but-ugly; exact mode only.
9. Otherwise **inexpressible** (reason: cannot decompose exactly / below min note type / tuplet beyond max).

### Tuplet candidate ranking (`chooseBestTupletCandidate`)

Prefer, in order: (1) common ratios `3:2, 5:4, 6:4, 7:4, 7:8, 5:2, 9:8, …` (an ordered list; earlier wins);
(2) smaller `actual`, then smaller `normal`; (3) larger (more readable) base note value; (4) fewer dots
(SP1 tuplet candidates carry `dots 0`); (5) no nested tuplets (SP1 never nests). Ties broken by the note
type closest to `ql`.

### exact vs quantize

- **`\exact`** (default): preserve the input value exactly. If no exact spelling exists → `inexpressible`
  (or a precise large tuplet when `allowLargeTuplets`). Never snaps.
- **`\quantize`**: snap to `grid` within `tolerance` first (step 3), then spell the snapped value. The
  caller must opt in; the engine never quantizes implicitly and never hides a residue.

### Inexpressible

`( inexpressible: true, ql: <PanolaRational>, reason: <String> )`, reasons include:
`"negative duration"`, `"NaN or infinite duration"`, `"smaller than minimum supported note value"`,
`"requires tuplet ratio exceeding configured maximum"`, `"cannot decompose exactly into assignable
components"`.

## Result schema

```
spelling  = ( inexpressible: false, ql: <PanolaRational>, inferred: true, components: [ component, … ] )
component = ( type: \eighth, meidur: "8", dots: 1, ql: <PanolaRational>, tuplets: [ tuplet, … ] )
tuplet    = ( actual: 3, normal: 2, actualType: \eighth, normalType: \eighth )
```

- `components` sum exactly to `ql` (asserted in tests).
- **`inferred`** (`expressionIsInferred`): `true` when the spelling was derived from a bare quarterLength
  (SP1's only entry point today, so effectively always `true`); the field exists so SP2/callers can later
  re-spell inferred durations to fit meter/beams without disturbing explicitly-authored spellings.
- `tuplets` is `[]` for ordinary/dotted components.

## Testing

Headless sclang (the existing `tools/` Panola harness pattern: build in sclang, print markers, assert in
pytest). Coverage:

- **Expected-examples table (exact):** `1.0`→`quarter`; `0.75`→dotted `eighth`; `1/3`→`eighth` with a
  `3:2` tuplet; `1.25`→`quarter` + `16th` (two tied components); `0.625`→`eighth` + `32nd`. Assert on
  component `type`/`dots`/`tuplets` and that the components sum to the input.
- **Quantize pair:** `0.6249852340957234` in `\exact` → `inexpressible` (with `allowLargeTuplets false`);
  the same value in `\quantize` (`grid 1/512`, `tolerance 2e-5`) → `eighth` + `32nd`.
- **`PanolaRational`:** reduction (`4/8 == 1/2`), arithmetic (`1/3 + 1/6 == 1/2`), comparisons, and
  `fromFloat` (`0.3333333 → 1/3`, `0.4 → 2/5`, `0.1 → 1/10`).
- **Edge cases:** negative / NaN / ∞ → `inexpressible` with the right reason; value below `2048th` →
  `inexpressible`; `allowLargeTuplets` on vs off changes a non-decomposable value from a large tuplet to
  `inexpressible`; `maxComponents` overflow → `inexpressible`; `0` → empty components.

## Public API

New classes only; no changes to existing Panola classes. `PanolaRational` (arithmetic value type) and
`PanolaDurationSpeller` (`*new(options)`, `spell(ql)`, `*spell(ql, options)`), returning the spelling Event.

## Scope

- **In (SP1):** `PanolaRational`; `PanolaDurationSpeller` implementing the ordered algorithm (simple →
  dotted → tuplet → multi-component split → large-tuplet fallback → inexpressible) with exact/quantize
  modes, the note-type table (`2048th … duplexMaxima`), tuplet ranking, and the option set; whelk docs +
  regenerated HelpSource; the full test suite above.
- **Out (SP2 / later):** meter-based splitting (barlines, beat/beam boundaries); `PanolaMEI` integration
  (replacing `decompose`, emitting tied MEI + `<tuplet>` from spellings); reconciliation with the existing
  explicit-`*m/d` tuplet path and per-beat beaming; nested tuplets; aesthetic rewrite across a measure; any
  playback change.
