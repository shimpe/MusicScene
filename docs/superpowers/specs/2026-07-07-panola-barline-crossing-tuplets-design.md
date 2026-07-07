# Panola barline-crossing tuplets (SP2d v1) — design

**Goal:** Notate an explicit `*m/d` tuplet whose span **crosses a barline** as **two tied `<tuplet>`
brackets**, one per measure (a member that straddles the barline is split there into two tied sub-tuplet
notes) — replacing today's "emit the whole bracket in one bar + warn" behaviour, which overflows the bar
and ignores the barline.

## Context

The last deferred piece of the complex-rhythm work, building directly on SP2a (tuplet-aware duration
spelling) and SP2c (bracketing split fragments via `wrapTuplets`). Today `PanolaMEI.voiceToMeasures`
(`:279-283`) detects a tuplet that crosses a barline, warns (`"split tuplets unsupported"`), and emits the
whole `tupletMEI` bracket in the current measure — the barline is not respected. This sub-project splits
that bracket at the barline.

**Where it lives.** `PanolaMEI.sc` in the **Panola quark** (`voiceToMeasures`, the complete-`\tuplet`
branch). No new classes. Whelk docs stay current; `HelpSource/` regenerated via `gendoc.bat`.

## The mechanism

A tuplet's members sit at **known grid positions** — the grid is explicit (each member carries its real
`beats`), so there is no re-split to infer; we only need to cut the sequence at barlines and spell the
pieces. When a complete `\tuplet` unit's span (`pos` … `pos + unit[\beats]`) crosses one or more barlines:

1. **Walk the members**, tracking the real position `sub` (starting at `pos`). For each member with real
   duration `mb`:
   - If it fits in the current measure (`sub + mb ≤ nextBarline`), emit it as a **tuplet-ratio record** at
     its written value (`meidur`/`dots`), `tup = (num, numbase)`.
   - If it **straddles** the barline (`sub < nextBarline < sub + mb`), split it: `d1 = nextBarline − sub`,
     `d2 = mb − d1`. **Spell each** with `PanolaDurationSpeller` (`spell(d1)`, `spell(d2)`) — a fraction of
     a tuplet member spells as a finer tuplet note at the **same ratio** (a half of a `7:4` sixteenth →
     `32nd[7:4]`). Emit the `d1` fragment (tuplet-ratio record, `tie="i"`), cross into the next measure,
     emit the `d2` fragment (`tie="t"`). The two fragments carry the **same pitch** and are tied.
2. **Cross measures** exactly as the `\normal` path does: when `sub` reaches a barline, append a new
   measure and continue placing records there.
3. **Bracket per measure** with `wrapTuplets` (from SP2c): each measure's consecutive same-ratio records
   become one `<tuplet num numbase>` bracket, beamed inside. The result is two (or more) brackets of the
   same ratio, one per measure, with the straddling member's tie crossing the barline.
4. **Non-crossing complete tuplets keep the atomic `tupletMEI` path** untouched — every existing
   `test_tuplets` case renders byte-for-identically.

Ties here are **only** within a split (straddling) member — the tuplet's other members are distinct notes,
untied, exactly as in a normal bracket. `@dyn`/`@slur` on a member attach at that member's onset as today.

## The inexpressible fallback

For an **arbitrary** crossing point a straddling fragment can be a duration the speller cannot express at
the tuplet ratio (or at all): e.g. a septuplet placed so the barline cuts a member at a non-dyadic-of-the-
grid point. When `spell(d1)` or `spell(d2)` comes back `inexpressible` (or would need a ratio different
from the unit's, which would make a nested/foreign bracket), **fall back to the current behaviour**: emit
the whole bracket in the starting bar + the existing warning. So the feature is strictly additive — it
splits cleanly when it can, and never renders worse than today when it can't.

## Scope

- **In (SP2d v1):** split a complete `*m/d` tuplet that crosses **one or more** barlines into tied
  per-measure brackets, splitting a straddling member via the SP1 speller and bracketing with
  `wrapTuplets`; the inexpressible-fragment fallback (warn + whole); whelk docs + regenerated schelp; new +
  regression tests.
- **Out (later):** an **incomplete** tuplet that *also* crosses a barline (the SP2c completion + a barline
  split at once — rare; keeps the SP2c fallback); nested tuplets; `consolidateCompletedTuplets`; additive-
  meter `groups`; any playback change. Complete non-crossing tuplets keep their atomic emission.

## Testing

Via the `tools/panola_mei/` sclang → MEI → Verovio harness. New assertions:

- **Septuplet across a barline (clean, member-boundary-ish):** `c5_4 d5 e5 f5_8 g5_16*4/7 a5 b5 c6 d6 e6 f6`
  (a `7:4` septuplet starting on the "and" of beat 4) → **two** `<tuplet num="7" numbase="4">` brackets
  (one per bar), the straddling member split into two tied `32nd[7:4]`s (`tie="i"`/`tie="t"`), **no
  "crosses a barline" warning**, and it renders. Measure count = 2.
- **Triplet across a barline:** a quarter-triplet spanning a barline → two brackets, tied, renders.
- **Inexpressible fallback:** a crossing whose straddling fragment can't be spelled → still the single
  whole bracket + the warning (unchanged), and it renders (no crash).
- **Regression (the hard invariant):** every `test_tuplets` case, all complete non-crossing tuplets, and
  the `test_tuplet_completion` / `test_meter_notation` / `test_asmei` suites render **byte-for-identically**
  — SP2d only changes input that currently warns (crossing tuplets).
