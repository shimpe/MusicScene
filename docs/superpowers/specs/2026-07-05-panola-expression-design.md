# Panola per-note expression → MEI — design (phase 2.2)

**Goal:** Notate per-note **dynamics** and **articulation** from Panola strings — `@dyn^mf^` renders a
`<dynam>` mark, `@art[stacc:on]` / `@art^acc^` render note `artic` — so `Panola.scoreAsMEI` / `MSScore`
show expression instead of bare noteheads.

**Context.** Panola attaches per-note properties in three forms, all currently parsing a **float**:
`@name{v}` animated (tweened), `@name[v]` static (persists until changed), `@name^v^` one-shot (that note
only). This is the second v2 feature of the Panola↔MusicScene bridge (after tuplets,
`2026-07-05-panola-tuplets-design.md`). Slurs, animated string values, and hairpins are **out of scope**
(later features).

**Where it lives.** Entirely in the **Panola quark** (`Extensions/panola/Classes/`). Two coupled parts:

- **Part A — string property values** (`PanolaParser.sc`, `Panola.sc`): a general Panola enhancement so a
  property value may be a *word*, not only a number. Reusable well beyond notation.
- **Part B — expression → MEI** (`PanolaMEI.sc`): map the `dyn` and `art` properties to MEI. Depends on A.

The plan builds A then B. **Every edited Panola-quark class keeps its whelk-style doc comments current**
(see `panola-quark-whelk-docs`), and `HelpSource/` is regenerated with `gendoc` afterward.

## Part A — string property values

### Grammar (`PanolaParser.sc`)

Each property form (`{…}` / `[…]` / `^…^`) currently parses `ScpParserFactory.makeFloatParser` for the
value. Add a **word-value** alternative: `ScpChoice([makeFloatParser, wordValueParser])`, where a word
value is one or more of `[A-Za-z0-9:]` (letters/digits/colon — the colon supports `stacc:on`). Float is
tried first, so numbers are unchanged. A word in `{…}` (animation) is accepted syntactically but treated
as **static** downstream — a word can't be tweened.

### Downstream (`Panola.sc`)

- `customPropertyPattern(name, default)` returns string values unchanged (it already collects the parsed
  values via `pr_animatedPattern`; verify it does not coerce to number for a static/one-shot string).
- `asPbind` currently does `customPropertyPattern(prop, default) * scale` for every custom property — this
  throws on a string value. Fix: when a property's values are **non-numeric**, add its pattern to the
  Pbind **without** the `* scale` arithmetic (as a `Pseq` of the raw values, coerced to `Symbol`), so a
  voice carrying `@dyn`/`@art` still plays; numeric properties are unchanged. Detection: inspect the
  property's parsed values (a string value ⇒ treat the whole property as symbolic). String properties in
  the Pbind are harmless — a SynthDef without that key ignores it.

### Testing (Part A)

- `@art[stacc:on]`, `@dyn^mf^`, `@art^acc^` parse without error.
- `customPropertyPattern("art", "")` returns the string values (persisting for `[…]`, single for `^…^`).
- `asPbind` on a voice with `@dyn`/`@art` builds and **plays** without a String-arithmetic error;
  a numeric custom property still scales as before.

## Part B — dynamics + articulation → MEI (`PanolaMEI.sc`)

`eventsOf` additionally reads, per note: `dyn = customPropertyPattern("dyn", "")` and
`art = customPropertyPattern("art", "")` (both `.asStream.all`, zipped by index like the existing
name/dur/beats).

### Articulation → note `artic`

`PanolaMEI` maintains a **running set** of currently-on articulations while scanning a voice's events, and
interprets each note's `art` value (all it has is the per-note resolved value from `customPropertyPattern`,
which persists for `[…]` and appears once for `^…^`):

- **empty** → the note's articulation is the current set (unchanged);
- **contains `:`** (a `name:on` / `name:off` toggle) → on a **change** from the previous note's `art`
  value, apply it to the set (`:on` adds `name`, `:off` removes it); the note's articulation is the set.
  Static `[…]` persists the value, so a toggle fires exactly once; toggles layer independently, so
  `@art[acc:off]` leaves an earlier `stacc` on;
- a non-empty **bare name** (no colon, e.g. from one-shot `@art^acc^`) → the note additionally gets that
  name for **this note only**; the set is unchanged.

Each note's articulation = `set ∪ {bare name on this note}`. Emit `artic="<codes>"` (space-separated,
MEI order-independent) when non-empty; omit when empty. This rule handles one-shot single notes, layered
passages, and a clean turn-off (`name:off`) uniformly.

Name → MEI `artic` code mapping (friendly names and MEI codes both accepted; unknown ⇒ `warn` + skip):
`staccato→stacc`, `staccatissimo→stacciss`, `accent→acc`, `tenuto→ten`, `marcato→marc`, `spiccato→spicc`,
plus pass-through for already-valid codes (`stacc`, `acc`, `ten`, `marc`, …). Rests never take `artic`.

`artic` is emitted by the existing element builder (`meiElement`) on `<note>`/`<chord>` (and on each
member of a tuplet, since tuplet members go through `meiElement` too).

### Dynamics → measure-level `<dynam>`

Emit a `<dynam>` when the `dyn` value **changes to a non-empty value** from the previous note (so a
one-shot `@dyn^mf^` produces exactly one mark at its note). The mark is placed at the **measure level**
(sibling of `<staff>`), positioned by `@tstamp` (the note's 1-based beat within its measure) and `@staff`
(the voice's staff number). The value is passed through as the mark text: `<dynam tstamp="2" staff="1">mf
</dynam>` — Verovio renders standard marks (`ppp`…`fff`, `sf`, `sfz`, `fp`, `rf`, …) in the dynamics font.

Assembly: `voiceToMeasures` (or a sibling pass) collects, per voice, a list of
`(measureIndex, tstamp, value)` dynam markers alongside the note records. `scoreAsMEI` emits, after the
`<staff>` elements of each measure, one `<dynam tstamp staff>` per collected marker for that measure and
voice. Non-expression measures are byte-for-byte unchanged.

### Interaction with existing machinery

- **Meter/ties:** `artic` rides on the note; a barline-split note keeps `artic` on its (first) fragment
  only. `dyn` tstamp is the beat where the change occurs.
- **Tuplets:** `artic` on tuplet members works (they use `meiElement`); a `dyn` change inside a tuplet
  gets the tuplet member's beat position as `tstamp`.
- **Chords/rests:** `artic` on chords; rests carry no `artic`; a `dyn` change on a rest still emits at the
  rest's tstamp.

### Testing (Part B)

sclang → MEI → Verovio render, asserting (extend `render_check.py` to count `<dynam` and expose `artic`
presence):

- `c5_4@art^staccato^ d5 e5` → `artic="stacc"` on the first note only, renders;
- `c5_4@art[stacc:on] d5 e5 f5@art[stacc:off] g5` → `stacc` on the first four notes, none on the last;
- layered: `@art[acc:on]` then `@art[stacc:on]` then `@art[acc:off]` → `acc`, then `acc stacc`, then
  `stacc`;
- `c5_4@dyn^p^ d5 e5@dyn^f^ g5` → exactly **two** `<dynam>` (`p` then `f`) at the right `tstamp`s, renders;
- a one-shot dynamic yields one mark (no repeat on following notes);
- articulation + dynamics on a tuplet member renders;
- **regression:** every existing `test_asmei.py` / `test_tuplets.py` case (no expression) is byte-for-byte
  identical.

## Public API

No new public methods. `Panola.scoreAsMEI` / `aPanola.asMEI` / `MSScore` gain expression for free; the
Panola string-value grammar is generally available (any `@name` property may now take a word).

## Scope

- **In:** word property values (`[…]`/`^…^`, and `{…}` treated as static); `asPbind` robustness to string
  properties; dynamics (`@dyn^mark^` → `<dynam>` on change); articulation (`@art[name:on/off]` layered set
  + `@art^name^` one-shot → `artic`); friendly→MEI name mapping; whelk docs on the edited quark classes +
  regenerated `HelpSource/`.
- **Out (later):** slurs (`<slur>`, needs note `xml:id`s + region tracking), animated **string** values,
  hairpins/crescendo from animated `vol`, dynamics as a persisting `[…]` level, and non-Latin/spaced
  mark text.
