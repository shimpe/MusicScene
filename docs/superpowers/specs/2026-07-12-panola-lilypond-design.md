# Panola → LilyPond — Design

**Date:** 2026-07-12
**Status:** approved (pending written-spec review)

## Goal

Add a Panola → **LilyPond** conversion alongside the existing Panola → MEI conversion,
at **full feature parity** with `PanolaMEI`, and wire it end-to-end into MusicScene
including **addressable note positions** (highlight / cursor / click) through the LilyPond
engraver. The transform's output is a **complete, standalone `.ly`** that also renders
outside Godot with plain LilyPond (`lilypond score.ly` → PDF/PNG/SVG).

## Why this is mostly a SuperCollider-side job

The Godot side already renders the `lilypond`/`ly` notation format end-to-end and is
validated (self-tests `tools/test_lilypond.gd`, `tools/test_lilypos.gd`; sample
`scores/example.ly`):

- `notationData "ly" <text>` over OSC is accepted; `MSNotationBackendMusicXML._ext_for`
  writes it to a `.ly` file.
- `MSRenderQueue.submit_addressable` routes `ly`/`lilypond` to `_submit_lily`, which
  injects a moment-tagger via `MSNotationLilyPositions.wrap_source` (prepends a `\version`
  + a Scheme engraver + a top-level `\layout`, **stripping the source's own `\version`**),
  runs `lilypond -dbackend=svg -dcrop=#t -o <stem> <in.ly>`, and parses the point-and-click
  SVG into per-note `{index, when, line, char, u, v}` (keyed by musical moment in whole
  notes, deduped by source `line:char`).
- The `when` values are whole notes — the **same unit MSScore's follow cursor already
  sends** (`beat/4`), so the cursor/highlight follow the LilyPond render with **no
  cursor-logic change**.

The one missing piece is that **SuperCollider cannot emit LilyPond** — there is no
`PanolaLilypond` parallel to `PanolaMEI`. This project adds it.

## Architecture decision

**Standalone `PanolaLilypond`** (chosen over a shared-IR refactor or a new shared model).
`PanolaMEI` (~840 lines, its structural logic entangled with MEI string emission, its output
guarded by byte-identity tests from the 0.18.0 release) is **left untouched** → zero
regression risk to the released MEI path. `PanolaLilypond` reuses the already-standalone
helpers (`PanolaMeter`, `PanolaMeterSplitter`, `PanolaDurationSpeller`, `PanolaRational`) and
the pure lyric parser `PanolaMEI.pr_parseLyricLine`, and writes a fresh, LilyPond-idiomatic
walk. Because LilyPond auto-beams and auto-respells accidentals, the LilyPond walk is
**simpler** than the MEI walk (no explicit `<beam>`, no per-note accidental-in-key logic).

The structural walk is therefore **duplicated** between the two transforms. That duplication
is kept honest by **cross-consistency golden tests** (see Testing): the same Panola input,
run through both transforms, must encode the same measure/note/tie/tuplet structure.

## Components / files

- **`panola/Classes/PanolaLilypond.sc`** (NEW) — the pure transform.
  `*scoreAsLilypond(voices, changes, clefs, braces, pageBreaks, systemBreaks, lyrics)`
  → a standalone `.ly` String. Signature parallels `PanolaMEI.scoreAsMEI` exactly.
- **`panola/Classes/Panola.sc`** (MODIFY) — add instance `asLilypond(meter, key, clef)` and
  class `*scoreAsLilypond(voices, changes, clefs, braces, pageBreaks, systemBreaks, lyrics)`,
  parallel to the existing `asMEI` / `*scoreAsMEI`, delegating to `PanolaLilypond`.
- **`msscore/Classes/MSScore.sc`** (MODIFY) — add a `notation:` argument
  (`\verovio` default → sends `notationData "mei"`; `\lilypond` → sends `notationData "ly"`),
  a `ly` accessor (the LilyPond String), and thread the format+data through `pr_emitSetup`.
  MEI stays the default; the existing `notationData "mei"` behavior is byte-identical when
  `notation` is unset or `\verovio`.
- **Godot side** — no code changes. Verified end-to-end against `PanolaLilypond` output.

## The generated `.ly` (standalone-renderable)

Absolute octaves, `\language "english"`. A `global` spine centralizes meter / key / breaks.
Named voices + `\lyricsto` so lyrics (incl. melisma) align to notes reliably.

```lilypond
\version "2.24.0"
\language "english"
\header { tagline = ##f }
\paper { indent = 0\mm }

global = { \time 4/4 \key c \major s1 | s1 \break | ... \bar "|." }

\score { <<
  \new GrandStaff <<                       % a braces: group → GrandStaff (draws a brace)
    \new Staff << \global \new Voice = "v1" { \clef treble c''4 d'' e'' f'' | ... } >>
    \new Staff << \global \new Voice = "v2" { \clef bass ... } >>
  >>
  \new Lyrics \lyricsto "v1" \lyricmode { Twin -- kle _ lit -- tle ... }
>> }
```

- **`\version "2.24.0"`** is emitted so the file renders standalone. Godot's `wrap_source`
  strips it (any line beginning `\version`) and supplies its own, so including it does not
  break the addressable path. `2.24.0` matches the version the Godot tagger uses.
- `\language "english"` makes pitch spelling deterministic (`cs`/`cf`/`css`/`cff`).
- A `global` spine holds `\time` / `\key` / `\break` / `\pageBreak` over `s`/`\skip` spacers;
  each `\new Staff` references `\global` so meter/key/breaks apply to every staff from one
  source. Mid-piece `changes` become additional `\time`/`\key` in the spine at the right
  measure.
- Braced groups (`braces:`) → `\new GrandStaff` (brace); ungrouped staves → plain
  `\new Staff` siblings (a non-braced multi-group could use `\new StaffGroup`, a bracket).
- Lyrics use **named voices + `\new Lyrics \lyricsto "vN" \lyricmode { ... }`** (one per
  verse), not `\addlyrics`, so melisma aligns without depending on slurs.

## Panola → LilyPond mapping

| Feature | Panola | LilyPond |
|---|---|---|
| Pitch + accidental | `f#5`, `c-4`, `dx3`, `e--3` | `fs''`, `cf'`, `dss`, `eff` (nil→"", s→`s`, x→`ss`, f→`f`, ff→`ff`) |
| Octave | `cN` | apostrophes = N−3: `'`×k if k>0, `,`×(−k) if k<0, none if 0. c3→`c`, c4→`c'`, c5→`c''`, c2→`c,` |
| Duration | `_4`, `_8.`, `_1` | `4`, `8.`, `1` (MEI dur value maps 1:1; dots → `.`×dots) |
| Chord | `<c4 e4 g4>` | `<c' e' g'>4` (shared duration outside the brackets) |
| Rest | `r` | `r4` (a whole-bar pad rest is decomposed like MEI's `emptyRest`) |
| Tie across a barline | (meter split) | `~` after every continued fragment; the last fragment has none |
| Tuplet | `_8*2/3` | `\tuplet 3/2 { c8 d e }` (`num`/`numbase` = notes/normal). Degenerate ratios route to normal notes, as in MEI |
| Tuplet crossing a barline | | split into per-measure `\tuplet` brackets joined with `~`, using the same music21-style completion/split decisions as `PanolaMEI` |
| Dynamic | `@dyn^mf^` | `\mf` etc. Predefined LilyPond dynamics map directly; a non-standard mark (e.g. `sffz`, `rf`, `sfp`) falls back to `-\markup \dynamic "sffz"` |
| Articulation | `@art^staccato+accent^` | concatenated scripts, e.g. `-.->`. Named articulations map faithfully where LilyPond has one; combos concatenate; sticky `:on`/`:off` toggles resolved per-note exactly like `annotateExpression` |
| Slur | `@slur^start/end/endstart^` | `(` … `)`; `endstart` → `)(` on the same note. One open slur at a time |
| Hairpin | `@hairpin^cresc/dim/end^` | `\<` / `\>` / `\!`; messa di voce `endcresc`/`enddim` → `\!\>` / `\!\<`. One open hairpin at a time |
| Clef (initial + inline) | `clefs:`, `@clef^bass^` | `\clef treble/bass/alto/tenor`; inline `@clef` inserts the command before that note (mid-measure allowed) |
| Key | `\Cmajor`, `\FsharpMinor` | `\key c \major`, `\key fs \minor`. LilyPond auto-respells accidentals — **no per-note accid-in-key logic** |
| Meter (plain) | `"4/4"`, `"7/8"` | `\time 4/4`, `\time 7/8` |
| Meter (additive) | `"2+2+3/8"` | `\compoundMeter #'((2 8) (2 8) (3 8))` — displays the additive signature **and** groups the auto-beaming |
| Mid-piece meter/key | `changes:` | `\time` / `\key` inserted in the `global` spine at the change measure |
| System break | `systemBreaks:` | `\break` in the `global` spine at that measure |
| Page break | `pageBreaks:` | `\pageBreak` in the `global` spine at that measure |
| Beaming | (per-beat in MEI) | **not emitted** — LilyPond auto-beams per `\time` / `\compoundMeter` |

## Addressable + constraints

- Automatic: MSScore sends `notationData "ly"` and the existing `addressable 1`; `_submit_lily`
  does the rest. Highlight, click, and the follow cursor work with **no Godot change** and no
  MSScore cursor-logic change (matching `when` units).
- **Constraint — single image.** The LilyPond addressable render is one cropped image
  (`-dcrop=#t`); there is no auto page-turn like Verovio's paged path. So with
  `notation: \lilypond`, MSScore treats the score as a single page: `paginate` is forced off,
  and `showPage` / `nextPage` / `prevPage` are Verovio-only (documented). `systemBreaks` and
  `pageBreaks` still emit `\break` / `\pageBreak`, laying out multiple systems within the one
  cropped image.
- **Config.** There is no builtin default engraver for `lilypond`; the user must set
  `musicscene/notation/engraver/lilypond` to the LilyPond executable
  (e.g. `"C:/Program Files/lilypond-2.25.81/bin/lilypond.exe"`). Documented alongside the
  existing Verovio-venv note.

## Error handling — never throw on musical edge cases

Mirror `PanolaMEI`'s warn-and-recover discipline: an unclosed slur/hairpin at end-of-voice is
dropped with a warning; an unknown clef/articulation/dynamic warns and is skipped; a tuplet
fragment not expressible at the ratio falls back to the whole bracket in one bar with a
warning; lyric syllables past the end of a voice are dropped with a warning. The transform is
a pure String→String function and does not perform I/O.

## Testing

- **Python unit tests** (`tools/panola_lilypond/test_*.py`, sclang-driven, skip if sclang
  absent — same harness as `tools/panola_mei/`): assert the emitted LilyPond tokens per
  feature (pitch+octave spelling, durations/dots, ties, chords, tuplets incl. cross-barline,
  dynamics incl. the markup fallback, articulation combos + sticky toggles, slurs incl.
  `endstart`, hairpins incl. messa di voce, clef initial+inline, key/mode, meter incl.
  additive `\compoundMeter`, mid-piece `changes`, `\break`/`\pageBreak`, braces→GrandStaff,
  multi-staff, lyrics incl. melisma). Include a `nil`/empty-lyrics parity case.
- **Cross-consistency golden tests**: a corpus of Panola inputs run through **both**
  `scoreAsMEI` and `scoreAsLilypond`; assert the two encode the same structure — measure
  count, per-measure non-rest note count, tie topology, and the set of tuplet ratios. This is
  the safety net for the duplicated structural walk.
- **Godot headless self-test** `tools/test_notation_lilypond.gd` (prints `fail=0` / `FAIL:`
  like the siblings): take a `PanolaLilypond` output, run it through the configured LilyPond
  engraver + `MSNotationLilyPositions`, and assert note elements were parsed and the render has
  dark pixels — the real end-to-end addressable proof. **Skip if LilyPond is absent** (CI has
  no LilyPond); it runs locally where LilyPond is installed.
- **CI**: keep LilyPond out of CI (large install); the self-test skips when the engraver is
  absent. The Python unit + cross-consistency tests carry CI coverage. Optionally, a local
  compile-check (`lilypond` exits 0 on the generated `.ly`) confirms standalone-renderability.
- **Example** `examples/supercollider/example_lilypond.scd` (per the "illustrate every feature
  in a runnable example" rule): an MSScore score with `notation: \lilypond` (mirrors
  `example_lyrics.scd`), plus a no-Godot `Panola.scoreAsLilypond(...).postln` /
  write-to-`.ly`-file snippet showing standalone rendering.

## Implementation sequencing (staged in one branch, shipped as one release)

Build in dependency order, each stage tested before the next, all shipped together:

1. **Core** — score skeleton (`\version`/`\language`/`\header`/`\paper`, `global` spine,
   `\score`), pitches+octaves+accidentals, durations+dots, rests, chords, single `\time`/
   `\key`/`\clef`, multi-staff, braces→GrandStaff, meter-aware split + `~` ties. First
   cross-consistency tests.
2. **Tuplets** — `\tuplet`, degenerate-ratio routing, music21-style completion, cross-barline
   split with ties. Additive meter `\compoundMeter`.
3. **Expression** — dynamics (+ markup fallback), articulations (combos + sticky toggles),
   slurs (+ `endstart`), hairpins (+ messa di voce).
4. **Lyrics** — named voices + `\lyricsto`, syllable hyphens, melisma, multiple verses,
   XML-free (LilyPond) escaping of specials.
5. **Mid-piece changes & breaks** — `changes` → `global`-spine `\time`/`\key`; inline
   `@clef`; `systemBreaks`/`pageBreaks` → `\break`/`\pageBreak`.
6. **Integration** — `Panola.asLilypond`/`*scoreAsLilypond`; MSScore `notation:` arg + `ly`
   accessor + single-image handling; Godot self-test; example `.scd`.
7. **Docs & release** — whelk doc blocks on every new SC method, regenerate **and
   parse-verify** the schelp; update README / TUTORIAL / ADVANCED / CHANGELOG; bump the
   panola, msscore, and MusicScene versions consistently.

## Out of scope (YAGNI)

- Refactoring `PanolaMEI` onto a shared model (deferred; the standalone approach was chosen).
- `\relative` octave mode (absolute is deterministic and simpler to test).
- Auto page-turning for the LilyPond addressable path (Verovio-only; single cropped image).
- MusicXML / Guido / ABC emission from Panola (only LilyPond is in scope here).
- Non-Latin lyric shaping beyond what LilyPond + simple tokens cover.

## Validation already done

- Godot renders `lilypond`/`ly` end-to-end (`_submit_lily`), tags noteheads by musical moment,
  and parses point-and-click positions (`MSNotationLilyPositions`); `when` = whole notes,
  matching MSScore's cursor. Confirmed by reading the current code and the existing
  `test_lilypond.gd` / `test_lilypos.gd` self-tests and `scores/example.ly`.
- The engraver is invoked as the LilyPond exe directly (`-dbackend=svg -dcrop=#t`); the old
  `ly_to_score.py` referenced in project memory is stale.
