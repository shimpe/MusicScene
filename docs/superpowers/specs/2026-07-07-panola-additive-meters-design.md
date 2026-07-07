# Panola additive-meter grouping (SP2e v1) — design

**Goal:** Let the `meter` string carry an **additive numerator** (`"2+2+3/8"`, `"3+2/8"`, `"2+3+2/16"`) so
irregular meters engrave with their grouping — meter-aware note **splitting** at group boundaries, **beaming**
per group, and an additive **meter signature** (`2+2+3`). A plain `"7/8"` stays ungrouped as today.

## Context

The last of the deferred complex-rhythm pieces. `PanolaMeter` already models additive meters — its
`pr_additive` builds group boundaries at strength 75, tested in SP2a for `PanolaMeter(7, 8, [2,2,3])` — but
`PanolaMEI.scoreAsMEI` builds `PanolaMeter(mp[0].asInteger, mp[1].asInteger)` with **no groups**, because the
meter string never carried them. So today an additive meter falls back to "every denominator-unit a beat"
(no grouping in splitting or beaming) and the signature just shows the sum.

**Where it lives.** `PanolaMEI.sc` in the **Panola quark** (`scoreAsMEI`: the meter setup + `barBeats` +
`beamMeasure` + the `<scoreDef>` meter signature). No new classes — `PanolaMeter` already does the work.
Whelk docs stay current; `HelpSource/` regenerated via `gendoc.bat`.

## The three pieces

### 1. Parse the meter → `(count, num, den, groups)`
A helper `parseMeter.(meter)` splits on `/`, then parses the numerator:
- Contains `+` (additive): `"2+2+3/8"` → `count: "2+2+3"`, `num: 7` (the sum), `den: 8`, `groups: [2,2,3]`.
- Plain: `"7/8"` → `count: "7"`, `num: 7`, `den: 8`, `groups: nil`.

`num` (the sum) feeds `barBeats` — today's `barBeats` does `p[0].asInteger * (4/den)`, which reads `"2+2+3"`
as `2`; it uses `parseMeter`'s `num` instead. `groups` feeds `PanolaMeter(num, den, groups)` — a `nil` groups
takes `PanolaMeter`'s existing simple/compound path (unchanged), a real `[2,2,3]` takes its additive path.

### 2. Beam per group — `groupBeats` → `groupStarts`
`beamMeasure` currently groups beamable runs by `(beatPos / groupBeats).floor`, a *uniform* width. Generalize
to an explicit list of **group-start positions** (cumulative quarterLength), and a note's group is the
interval its `beatPos` falls into (`groupStarts.count { |s| s <= beatPos } - 1`). Compute `groupStarts` once:
- Additive `[2,2,3]/8`: each group of `k` units = `k * (4/den)` beats → starts `[0, 1, 2]` (bar = 3.5 beats).
- Compound `/8` with `num % 3 == 0` (`6/8`, `9/8`, `12/8`): groups of 3 → starts `[0, 1.5, …]` (matches today's
  `groupBeats = 1.5`).
- Everything else: one group per beat → starts `[0, 1, 2, …]` (matches today's `groupBeats = 1.0`).

So `beamMeasure(records, groupStarts)` beams `2 + 2 + 3` for the additive bar and is byte-identical to the old
uniform behaviour for simple/compound meters.

### 3. Additive meter signature
The `<scoreDef>` emits `meter.count="<count>"` — the `parseMeter` `count` string, so additive meters get
`meter.count="2+2+3"` (a valid MEI additive count that Verovio renders as `2+2+3`), while plain meters still
emit `meter.count="7"` / `"4"`. `meter.unit` is unchanged (`den`).

## The hard invariant

**Every existing meter renders byte-for-identically.** `parseMeter("4/4")` → `count "4"`, `num 4`,
`groups nil` → the same `PanolaMeter(4,4)`, `groupStarts [0,1,2,3]` (≡ old `groupBeats 1.0`), and
`meter.count="4"`. `6/8` → `groupStarts [0,1.5]` (≡ old `1.5`), `meter.count="6"`. `7/8` (no `+`) →
ungrouped, exactly as today. Additive grouping only changes a meter string that contains `+`. Every
`test_asmei` / `test_meter_notation` / `test_tuplets` / … case must be unchanged.

## Testing

Via the `tools/panola_mei/` sclang → MEI → Verovio harness. New assertions for `"2+2+3/8"`:

- **Signature:** `<scoreDef … meter.count="2+2+3" meter.unit="8" …>` and it renders.
- **Splitting at a group boundary:** a note that starts inside one group and reaches into the next splits and
  ties at the group boundary (e.g. a quarter starting on the last eighth of group 1 crosses into group 2 →
  eighth ~ eighth), because the group boundary (strength 75) exceeds the onset strength.
- **A note within a group stays whole** (anti-over-split): a note spanning only weaker interior subdivisions
  of its group is not split.
- **Beaming groups 2+2+3:** a bar of seven eighths beams as three beams (2, 2, 3), not uniformly.
- **Bar length:** `barBeats("2+2+3/8") == 3.5`; the bar holds 3.5 quarter-beats.
- **Regression (the hard invariant):** `4/4`, `3/4`, `6/8`, and bare `7/8` render byte-for-identically to
  before; the full `panola_mei` suite is green.

## Forward compatibility — do not foreclose mid-piece meter changes

Mid-piece meter changes are out of scope for v1, but the implementation **must not preclude them**. The
binding constraint: `parseMeter` returns a **self-contained meter descriptor** — `( count, num, den, groups,
bb, groupStarts, pmeter )` — and every meter-dependent step consumes *that descriptor*, not loose globals
derived from a single "the meter". Concretely:

- The per-measure render loop (`nm.do { |i| … }`) and the note-layout / `beamMeasure` calls take a meter
  descriptor **as a parameter**, so today they all receive the one score-wide descriptor, but a future
  change is just: parse a **list** of descriptors and pick `descriptorForMeasure(i)` — no rewrite of
  `barBeats`, splitting, or beaming.
- Do not assume `bb` / `groupStarts` / `pmeter` are constant for the whole piece; hold them inside the
  descriptor.
- Do not assume the meter signature is emitted **only** in the top `<scoreDef>`; keep the signature string a
  property of the descriptor, so a later meter change can emit a mid-`<section>` `<scoreDef>`/`<meterSig>`
  without restructuring.

This is good encapsulation regardless, and it reduces a future mid-piece-meter feature to a localized
addition.

## Scope

- **In (SP2e v1):** parse an additive `"a+b+…/d"` meter; thread the sum into `barBeats` and the groups into
  `PanolaMeter` (splitting); beam per group (`groupStarts`); emit the additive `meter.count`; whelk docs +
  regenerated schelp; new + regression tests. **One meter per score, but structured per the Forward-
  compatibility section so mid-piece changes remain a clean future addition.**
- **Out (later):** a meter change **mid-piece** (deferred, but must not be precluded — see above); nested /
  hierarchical groupings; a bare `5/8`/`7/8` **inferring** a default grouping (must be written explicitly);
  denominators other than a power of two; any playback change (playback uses the raw beats).
