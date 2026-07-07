# Panola tuplet completion (SP2c v1) — design

**Goal:** Notate **incomplete tuplets** correctly by adopting music21's `splitElementsToCompleteTuplets`
model: when an explicit `*m/d` tuplet run does not fill its container, **split the following element**
(note or rest) so its leading part completes the tuplet — emitted as tied member(s) *inside* the
`<tuplet>` bracket — and let the remainder continue normally. This retires PanolaMEI's "incomplete tuplet"
warning + broken partial bracket, and the latent SP2b bug where a tuplet-length fragment loses its bracket.

## Context

Sub-project 2c of the complex-rhythm work, and the tuplet **reconciliation** deferred from SP2b. SP1 gave
`PanolaDurationSpeller`; SP2a gave `PanolaMeter` + `PanolaMeterSplitter` (which can split a note against a
tuplet grid and spell each fragment with the correct ratio); SP2b wired the splitter into `PanolaMEI`'s
non-tuplet path. SP2c builds the capability SP2b lacked — **emitting `<tuplet>` brackets from *split*
fragments**, not just atomic runs — and uses it to complete incomplete tuplets the way music21 does.

**Reference (music21).** `makeNotation` handles incomplete tuplets with `splitElementsToCompleteTuplets`
(*"Split notes or rests if doing so will complete any incomplete tuplets; the element being split must
have a duration that exceeds the remainder of the incomplete tuplet"*, `addTies=True`), then
`makeTupletBrackets` groups consecutive tuplet members into brackets. music21 does **not** use a
power-of-two container heuristic and does **not** pad with synthetic rests — it splits whatever follows and
ties. SP2c mirrors this. (See music21 `stream.makeNotation`.)

**Where it lives.** `PanolaMEI.sc` in the **Panola quark** (`scoreAsMEI` / `voiceToMeasures` / `meterPieces`
/ the measure-emission). No new classes. Whelk docs stay current; `HelpSource/` regenerated via
`gendoc.bat`.

## The three pieces

### Piece 1 — `meterPieces` preserves the tuplet descriptor
Today `meterPieces` (SP2b) flattens a spelling component to `[meidur, dots, beats]` and **discards**
`component[\tuplets]` — so a fragment that lands on a tuplet grid (e.g. a plain note pushed onto a
non-dyadic onset) is emitted as a plain note with a tuplet duration but no bracket (the latent SP2b bug).
Change the fragment to carry it: **`[meidur, dots, beats, tuplet]`**, where `tuplet` is `( num: actual,
numbase: normal )` or `nil`. The SP2a splitter already produces the right descriptor
(`spell(1/3)`→`eighth[3:2]`, `spell(1/5)`→`16th[5:4]`), so a grid-aligned fragment carries the matching
ratio.

### Piece 2 — emit `<tuplet>` brackets by grouping fragments
Add a fragment-emitting helper that, given an ordered list of fragments for a measure, wraps each maximal
run of consecutive fragments sharing the same `( num, numbase )` in `<tuplet num numbase> … </tuplet>`
(beamed inside via the existing `beamRun`), and emits `nil`-tuplet fragments plainly (the current
per-fragment `meiElement` path). This is music21's `makeTupletBrackets` step. It also fixes the Piece-1
bug: a tuplet fragment now renders inside a real bracket.

The grouping helper **becomes the `\normal`-path emission** — every `meterPieces` fragment flows through
it: `nil`-tuplet fragments render exactly as today (plain, beamed by `beamMeasure`), and tuplet fragments
(from a non-dyadic onset, or Piece 3's completion) are wrapped in a bracket. To bound risk, **complete
`*m/d` tuplet units keep their existing atomic path** (`groupEvents` → `tupletMEI`) untouched: those
already render correctly and every `test_tuplets` case must stay byte-for-identical.

### Piece 3 — complete an incomplete tuplet by splitting the follower
When `groupEvents` yields an **incomplete** `*m/d` unit (`complete: false`, `acc < container`):

1. `remainder = container − acc` (the beats needed to reach the nearest power-of-two container; the
   container choice is unchanged from `groupEvents`).
2. Take the **donor** = the next unit (a `\normal` note or rest). It must **exist** and its `beats` must
   **exceed** `remainder` (music21's `splitElementsToCompleteTuplets` precondition — completion only ever
   *splits an existing following element*; it never fabricates a rest). If there is no follower (a
   **trailing** incomplete tuplet), the follower is too short, or completion would cross a barline, fall
   back to the current warned partial bracket — exactly as music21 leaves a trailing incomplete tuplet.
3. Build a tuplet context `( startQL: unitStart, totalDurationQL: container, numberNotesActual: num,
   numberNotesNormal: numbase )` and split the donor against it with `PanolaMeterSplitter`: the fragments
   **inside** the container come back as tuplet-ratio fragments (matching the bracket), the fragments
   **past** the container boundary come back normally (or as their own tuplet fragments if the remainder
   is itself non-dyadic).
4. Emit the **bracket** = the unit's original members (their written values) **plus** the donor's
   inside-container fragments, via Piece 2. A donor **note** ties from its completing member out to its
   remainder (`tie="i"`…); a donor **rest** contributes a rest-member (no tie). Then emit the donor's
   remainder via Pieces 1–2 (a dyadic remainder → plain notes/rests; a non-dyadic remainder → its own
   bracket, exactly music21's behavior).
5. Advance position and consume the donor (reduced by `remainder`; removed if fully consumed).

When a **following rest** is the donor (`c5_8*2/3 d5 r_2`), splitting it puts a tuplet **rest** inside the
bracket (music21-faithful — an existing element is split). When a **following note** is the donor
(`c5_8*2/3 d5 c5_4`), its leading part becomes a tied triplet member and the non-dyadic remainder forms its
own bracket. A **trailing** incomplete tuplet with nothing after it (`c5_8*2/3 d5`) is **left partial +
warned** — SP2c never invents a rest to pad it.

## Phasing (the plan, not the spec)

- **Phase A — bracketed fragments (Pieces 1–2):** `meterPieces` carries the tuplet descriptor; the
  measure-emission groups consecutive same-ratio fragments into brackets. Independently testable: force a
  plain note onto a tuplet grid (via a non-dyadic onset) and assert it renders inside a `<tuplet>` instead
  of as a bare note. Fixes the SP2b tuplet-drop bug. Every existing test stays green.
- **Phase B — completion (Piece 3):** detect the incomplete unit, split the donor, emit the completed
  bracket + remainder. Uses Phase A's emission.

## The hard invariant

**Every existing `tools/panola_mei` test must stay green, and every `test_tuplets` case must render
byte-for-identically.** Complete tuplets, `with_rest` (a rest member that already fills a container),
`sixeighths` (→ two triplets), `mixed` (quarter+eighth triplet), `quintuplet`, `quarter3`, `then_plain`
(plain note after a complete triplet is outside the bracket) — all unchanged. SP2c is a **superset**: it
only changes input that currently warns/breaks (the incomplete cases). The SP1/SP2a/SP2b suites are
untouched.

## Testing

Via the `tools/panola_mei/` sclang → MEI → Verovio harness. New assertions:

- **Phase A:** a construct that pushes a plain note onto a tuplet-grid onset renders the fragment inside a
  `<tuplet>` (num/numbase correct), not as a bare mis-valued note.
- **`c5_8*2/3 d5`** (incomplete triplet, **nothing follows**) → left a **partial** 2-note `<tuplet>` + the
  incomplete-tuplet warning (music21 leaves a trailing incomplete tuplet as-is — no fabricated rest).
- **`c5_8*2/3 d5 r_2`** (a rest follows) → completes by **splitting the rest**: the bracket gains a tuplet
  **rest** member, the remainder continues (its own bracket if non-dyadic).
- **`c5_8*2/3 d5 c5_4`** (incomplete triplet then a note) → the quarter's leading third becomes a tied
  triplet-eighth inside the bracket; the remainder ties out (its own bracket if non-dyadic).
- **Regression:** all `test_tuplets` cases identical; `test_asmei` / `test_meter_notation` / SP1 / SP2a
  suites unchanged.

## Scope

- **In (SP2c v1):** Pieces 1–3 — tuplet descriptor preserved through `meterPieces`; bracket-grouping
  emission for split fragments; incomplete-tuplet completion by splitting the following note/rest
  (music21's `splitElementsToCompleteTuplets` + `makeTupletBrackets`), with ties; whelk docs + regenerated
  schelp; new + regression tests.
- **Out (later):** nested tuplets; `consolidateCompletedTuplets` (merging over-tupleted runs back to a
  single note — a readability nicety); tuplets whose bracket **crosses a barline** (still warned — the
  barline split would fragment the bracket, a separate concern); additive-meter `groups`; any playback
  change. Complete `*m/d` tuplets keep their existing atomic emission.
