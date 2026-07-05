# Panola tuplets → MEI — design (phase 2.1)

**Goal:** Render Panola tuplets (triplets, quintuplets, …) as proper MEI `<tuplet>` groups (bracket +
number), so `Panola.scoreAsMEI` / `MSScore` notate them instead of silently approximating them as the
nearest plain note value.

**Context.** Panola marks tuplets with a per-note duration multiplier/divider that is *remembered until a
new duration is specified*: `c4_8*2/3 e g` = an eighth-note triplet (three notes, each written value 8,
`mult=2`, `div=3`, actual duration `0.333` beat). `Panola.notationdurationPattern` exposes this as
`_8.0 .*2/3` (value `8.0`, space-separated `.` per dot, `*mult/div`); `durationPattern` gives the actual
beats. This is the first v2 feature of the Panola↔MusicScene bridge; the v1 design is
`2026-07-05-panola-musicscene-score-design.md`.

**Where it lives.** Entirely in `PanolaMEI.sc` (the Panola quark). No changes to `MSScore` or the
MusicScene addon — a tuplet is just more MEI. Verovio already renders `<tuplet>`.

## Current behaviour (the gap)

`PanolaMEI` is **beats-driven**: every note's engraved value comes from `decompose(beats)` (greedy
largest-first into standard note values), and `parseDur`'s written value is currently **dead code**
(computed, never used). For a triplet eighth (`0.333` beat) `decompose` yields a **sixteenth** (`0.25`,
dropping the remainder) — no `<tuplet>`, wrong value. Tuplets are the first real consumer of the *written*
value, so they need a dedicated path.

## Design

### 1. Parsing

Rewrite `parseDur(s)` to return `(writtenValue, dots, mult, div)`:

- Strip the leading `_`, split off the `*mult/div` tail (`mult=div=1` when absent).
- `writtenValue` = integer part of the value token (`"8.0".asFloat.asInteger` → `8`).
- `dots` = number of space-separated `.` tokens after the value (`_4.0 . .` → 2).
- `mult`, `div` = the two integers after `*`.

This replaces the existing dead `parseDur`. `eventsOf` attaches `mult`, `div`, `writtenValue`,
`writtenDots` to each event alongside the existing `beats`.

### 2. Two engraving paths (dispatched per event)

- **Normal notes** (`mult == 1 and div == 1`): **unchanged** — the existing beats-driven `decompose` +
  barline split/tie + per-beat beaming. Every current behaviour and test stays valid.
- **Tuplet notes** (`mult/div ≠ 1`): grouped and emitted via the tuplet path below, using the **written**
  value + dots (never `decompose`d).

### 3. Grouping — duration-based (fills a clean container)

Scan a voice's events. A maximal run of consecutive events sharing the same `(mult, div) ≠ (1,1)` is split
into tuplet groups by **accumulated actual duration**: start a group, accumulate each note's actual beats,
and **close the group when the accumulated actual duration equals a clean container** — a normal power-of-2
note value in beats (`0.25, 0.5, 1.0, 2.0, 4.0`). Then start the next group within the same run.

This is duration-based, not count-based, so it is correct for mixed note values inside one tuplet:

| Panola | actual beats | groups |
|---|---|---|
| `c_8*2/3 e g` | .333×3 = 1.0 | one triplet (3 notes) |
| `c_8*2/3 e g d e f` | 1.0 + 1.0 | two triplets |
| `c_4*2/3 d_8*2/3` | .667 + .333 = 1.0 | **one triplet, 2 notes** |
| `c_4*2/3 d q` (three `*2/3` quarters) | .667+1.333+2.0 → closes at 2.0 | one bracket, 3 notes |
| `c_16*4/5 …` (five) | .2×5 = 1.0 | one quintuplet |

`num = div`, `numbase = mult` (e.g. `*2/3` → `<tuplet num="3" numbase="2">`, i.e. 3-in-the-time-of-2).

### 4. Emission

A closed group is emitted as `<tuplet num="{div}" numbase="{mult}"> … </tuplet>` wrapping each member as a
plain `<note>`/`<chord>`/`<rest>` at its **written** value + dots (via the same element builder, but with
the written value instead of a decomposed one). Beamable members (written value ≥ 8, not rests) are
wrapped in a `<beam>` **inside** the `<tuplet>` so the beam is drawn across the tuplet.

### 5. Meter engine — tuplet groups are atomic

The measure-binning engine treats a whole tuplet group as one indivisible unit: it is placed in the
measure where it starts (binned by its **total actual beats**), and is **never** `decompose`d or
split-and-tied across a barline. Because groups close on clean containers aligned to the beat grid, in
normal use they sit within a bar. If a group still would cross a barline, it is kept in the starting bar
and a **warning** is posted (`("PanolaMEI: tuplet crosses a barline; keeping it in bar N — split tuplets
are not supported").warn`). Non-tuplet notes continue to split-and-tie exactly as before.

### 6. Edge cases

- **Incomplete run:** a same-ratio run that ends (ratio change or end of voice) before the accumulated
  actual fills a container → emit what accumulated as a partial tuplet (`num` = number of notes in the
  fragment, `numbase = mult`) and `warn`.
- **Nested tuplets** (a ratio change mid-run that is itself a tuplet ratio): out of scope — treat each
  `(mult,div)` run independently; `warn` if a run cannot be grouped into containers.
- **Dotted / compound-meter containers** (a tuplet filling a dotted-note container, e.g. in 6/8): out of
  scope for v1; only power-of-2 containers close a group. A tuplet that never hits a power-of-2 container
  falls through to the incomplete-run handling (partial + warn).
- **Rests inside a tuplet:** a `r` carrying a tuplet ratio is a valid member (`<rest>` inside `<tuplet>`).

## Public API

No new public surface. `Panola.scoreAsMEI` / `aPanola.asMEI` / `MSScore` gain tuplet rendering for free.

## Testing

Runnable now (no SuperCollider runtime gap): a sclang script generates MEI from representative Panola
strings; each is rendered through the bundled `verovio_render.py` and asserted via the existing
`tools/panola_mei/render_check.py` (extended to count `<tuplet>` groups in the MEI and tuplet-number
glyphs in the SVG). Cases:

- eighth-note triplet → 1 `<tuplet num="3" numbase="2">`, 3 notes, renders;
- six `*2/3` eighths → **2** tuplets of 3;
- **mixed** `c_4*2/3 d_8*2/3` → **1** tuplet of 2 notes;
- quarter-note triplet (three `*2/3` quarters) → 1 tuplet spanning 2 beats;
- quintuplet (`*4/5` sixteenths) → 1 `num="5" numbase="4"`;
- tuplet-then-plain (`c_8*2/3 e g c_4`) → 1 tuplet then a plain quarter (no tuplet on the quarter);
- dotted values render;
- **regression:** the existing `test_asmei.py` cases (no tuplets) produce byte-for-byte identical MEI.

## Scope

- **In (v1 of tuplets):** simple and mixed-value tuplets whose group fills a power-of-2 container within a
  bar; triplets/quintuplets/sextuplets/…; tuplets of notes, chords, and rests; beaming inside the tuplet;
  warnings for barline-crossing / incomplete / nested cases.
- **Out (later):** split tuplets across a barline, nested tuplets, dotted/compound-meter containers,
  tuplet ratio numbers shown as `x:y` vs a single number (use Verovio's default), tuplet brackets vs
  slurs styling.
