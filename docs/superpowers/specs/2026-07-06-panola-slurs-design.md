# Panola slurs → MEI — design (phase 2.3)

**Goal:** Notate **slurs** (phrase arcs) from Panola strings — `@slur^start^` … `@slur^end^` renders an
MEI `<slur>` — so `Panola.scoreAsMEI` / `MSScore` show slurs over the notes.

**Context.** This is the next notation feature after per-note dynamics/articulation
(`2026-07-05-panola-expression-design.md`). A slur differs from those: it is a **span** across two
endpoint notes (both included in the arc), not a per-note mark. It is **notation only** — playback is
unchanged; Panola's `@pdur` still controls per-note legato/staccato. Slurs reuse the word-valued property
grammar and the measure-level marker machinery already built for `<dynam>` (no parser change, no
`xml:id`s).

**Where it lives.** Entirely in the **Panola quark**, in `PanolaMEI.sc` (plus the two-line reader in
`eventsOf`). No changes to `PanolaParser.sc` / `Panola.sc` — `@slur` is an ordinary word-valued property.
Whelk doc comments on the edited class stay current and `HelpSource/` is regenerated (see
`panola-quark-whelk-docs`).

## Syntax

Three one-shot markers (each a word value on a single note; a note carries at most one `@slur`):

- `@slur^start^` — open a slur at this note;
- `@slur^end^` — close the open slur at this note;
- `@slur^endstart^` — close the open slur at this note **and** open a new one at the same note (chained
  phrase slurs that share a note).

```
c5_4@slur^start^ d5 e5@slur^endstart^ f5 g5@slur^end^ a5
   |------ slur ------||------ slur ------|
```

## Semantics — pairing

There is at most **one open slur at a time** (no nesting). `PanolaMEI` keeps a single `openStart` (a
`(measure, beat)` position, or `nil`) while scanning a voice's notes in order:

- `start` → set `openStart` to this note's position;
- `end` → emit a slur marker from `openStart` to this note, then clear `openStart`;
- `endstart` → emit a slur marker from `openStart` to this note, then set `openStart` to this note.

**Error handling (always `warn` + recover, never crash):**

- `start` while a slur is already open → warn ("previous slur not closed"), drop the old open, and start
  fresh at this note;
- `end` with nothing open → warn ("no slur to close"), drop;
- `endstart` with nothing open → warn, then open a new slur at this note (nothing to close);
- a slur still open when the voice ends → warn ("unclosed slur"), drop it;
- an unknown `@slur` value (not `start`/`end`/`endstart`) → warn, ignore.

## MEI mapping

Each slur becomes a **measure-level** element (sibling of `<staff>`, like `<dynam>`), emitted in the
**start note's** measure and positioned by timestamps — no note `xml:id`s:

```
<slur tstamp="<startBeat>" tstamp2="<Δm>m+<endBeat>" staff="<s>"/>
```

- `startBeat` = the start note's 1-based beat within its measure (`pos + 1`);
- `endBeat` = the end note's 1-based beat within its measure;
- `Δm` = `endMeasure − startMeasure` (0 within a bar; ≥1 across barlines / systems — Verovio resolves it);
- `staff` = the voice's 1-based staff number.

Example (4/4): `c5_4@slur^start^ d5 e5 f5@slur^end^ g5` (start beat 1 of bar 1, end beat 4 of bar 1) →
`<slur tstamp="1" tstamp2="0m+4" staff="1"/>`. A slur crossing into the next bar
(`… f5 | g5@slur^end^`) → `tstamp2="1m+<endBeat>"`.

## Architecture (reuses the `<dynam>` machinery)

- `eventsOf` also reads `slurs = panola.customPropertyPattern("slur", "").asStream.all` and attaches
  `e[\slur] = slurs[i].asString` per event (alongside the existing `dyn`/`art`).
- `voiceToMeasures` already tracks each note's `(measure, beatPos)` and collects `dynam` markers; add one
  `openStart` accumulator. When a note is placed (at its onset, before any barline split), read
  `ev[\slur]` and apply the pairing rules above, appending to a `slurs` list a record
  `(startMeasure, startTstamp, endMeasure, endTstamp)`. The method now returns
  `( measures:, dynams:, slurs: )`.
- `scoreAsMEI` emits, after each measure's `<staff>` elements (and next to the `<dynam>` emission), one
  `<slur tstamp tstamp2 staff>` per collected slur whose **start** measure is the current measure,
  computing `Δm` from the record and the staff number from the voice index.

### Interaction with existing machinery

- **Ties / barlines:** the slur marker is recorded at the note's onset, so a barline-split (tied)
  endpoint anchors to its first fragment; the `tie` attribute on the note is untouched.
- **Chords:** a slur endpoint on a chord works — `tstamp` hits the chord's beat and Verovio attaches the
  arc to the chord.
- **Tuplets:** each tuplet member gets its **real sub-tuplet beat offset** (accumulated member
  durations), so a slur (or dynamic) endpoint on a tuplet member is placed on the right note — a slur
  that starts and ends inside one tuplet renders correctly rather than collapsing to a zero-length arc.
  Fractional tstamps are rounded to 4 decimals. *(Initially this design snapped tuplet members to the
  tuplet onset; that made a within-tuplet slur invisible, so it was fixed during implementation.)*
- **Non-expression scores** are byte-for-byte unchanged (no `@slur` ⇒ empty `slurs` list ⇒ no `<slur>`).

## Testing

sclang → MEI → Verovio render (extend `render_check.py` to count `<slur`), asserting:

- within a bar: `c5_4@slur^start^ d5 e5 f5@slur^end^ g5` → one `<slur tstamp="1" tstamp2="0m+4"
  staff="1"/>`, renders;
- across a barline: a start in bar 1 and an `^end^` in bar 2 → `tstamp2="1m+…"`, one `<slur>`, renders;
- chained: `c5_4@slur^start^ d5 e5@slur^endstart^ f5 g5@slur^end^ a5` → **two** `<slur>`s, the first
  ending and the second starting at the same beat;
- an unmatched `^end^` (nothing open) → no `<slur>`, no error in the MEI, still renders;
- a two-voice score with a slur on one staff → `<slur staff="2"/>` on the right staff;
- **regression:** every existing `test_asmei.py` / `test_tuplets.py` / `test_expression.py` case is
  unchanged.

## Public API

No new public methods. `Panola.scoreAsMEI` / `aPanola.asMEI` / `MSScore` gain slurs for free; `@slur` is an
ordinary word-valued Panola property.

## Scope

- **In:** `@slur^start^` / `@slur^end^` / `@slur^endstart^` → measure-level `<slur tstamp tstamp2 staff>`;
  a single open slur at a time; chained slurs via `endstart`; cross-barline / cross-system via `Δm`;
  warn-and-recover error handling; whelk docs on `PanolaMEI.sc` + regenerated `HelpSource/`.
- **Out (later / not planned):** nested or overlapping slurs, any playback effect (legato), and slur
  direction/placement control (Verovio decides the arc side).
