# Panola ↔ MusicScene Score Bridge — Design

**Status:** approved for planning · **Date:** 2026-07-05

## Goal

Make it *trivial* to write, play, and visualize a score with MusicScene: write the music once as
[Panola](https://github.com/shimpe/panola) string(s), and get **live notation + audio + a note-accurate
following cursor** with a couple of lines of SuperCollider. This replaces the hand-rolled MEI-string
building, measure-binning, and cursor math that made the generative examples
(`example_two_hands_patterns.scd`) verbose.

The insight: Panola already parses music into exactly the per-note data MEI needs (spelled pitch,
note-value duration, chords, beats). The only things MEI needs that Panola has *no* concept of —
**meter/barlines, key signature, clef** — are supplied by the bridge, not by Panola.

## Architecture

Two units, with an **MEI string as the sole contract** between them:

```
Panola string(s) + prefs ──▶ [Panola.asMEI]  ──MEI──▶ [MSScore] ──OSC──▶ MusicScene
   (Panola quark)              pure transform            (MusicScene client)   render + cursor
```

1. **`Panola.asMEI` (in the Panola quark)** — a pure transform: Panola note data + score prefs → an MEI
   document. No OSC, no MusicScene, no sound. Independently useful: write the MEI to a file and open it
   in any MEI viewer. This is the "Panola can render itself to notation" capability.
2. **`MSScore` (a SuperCollider class shipped in this repo)** — orchestration only: calls Panola for the
   MEI, sends it to MusicScene over OSC, plays the voices, and drives the cursor. Contains no music
   theory beyond what it needs to talk to MusicScene.

This split keeps Panola a pure music language and puts all notation-layout / OSC / cursor concerns on
the MusicScene side. The two pieces are independently testable through the MEI-string interface.

## Component 1 — `Panola.asMEI` (Panola quark)

### Interface

```supercollider
aPanola.asMEI(meter: "4/4", key: \Cmajor, clef: \treble)         // one voice -> single-staff MEI string
Panola.scoreAsMEI(voices, meter: "4/4", key: \Cmajor,            // many voices -> multi-staff MEI string
                  clefs: [\treble, \treble, \bass], braces: [[2, 3]])
```

- `voices`: an array of `Panola` instances (one per staff, top to bottom).
- `meter`: a time-signature string `"num/den"`.
- `key`: a symbol naming a key (`\Cmajor`, `\Aminor`, `\Gmajor`, `\Dminor`, `\CsharpMinor`, …).
- `clefs`: one clef symbol per staff (`\treble` → G/2, `\bass` → F/4, `\alto` → C/3, …).
- `braces`: a list of `[firstStaff, lastStaff]` (1-based) ranges to join with a brace; staves not in any
  brace render loose. `nil`/`[]` = no braces.
- Returns: a complete MEI document string ready for `notationData mei`.

### Note mapping (direct, from Panola's parse tree)

`asMEI` walks `parsed_notation.result` after `pr_resetDefaults`, resolving Panola's `'previous'` defaults
for octave / duration / dots exactly as the existing `notationnotePattern` / `durationPattern` methods
do, and reuses `pr_extractNotationNote` for the resolved spelling. Per event it yields a structured
record and emits MEI:

| Panola | MEI |
|---|---|
| notename `a–g` | `pname` |
| modifier `sharp` / `doublesharp` / `flat` / `doubleflat` / none | `accid` `s` / `x` / `f` / `ff` / (omitted) |
| octave `N` (Panola `c4` = MIDI 60) | `oct="N"` (same number — no offset) |
| `duration` (`1/2/4/8/16/…`) | `dur` (same value) |
| `durdots` | `dots` |
| chord (`<c e g>`, first note's duration) | `<chord><note/>…</chord>` |
| rest (`type=='rest'`) | `<rest dur=… dots=…/>` |
| `durationPattern` (beats, quarter = 1) | drives measure-binning + ties (below) |

### Meter engine (measure binning + auto-ties)

- Measure length in beats: `barBeats = numerator * (4 / denominator)` (so `4/4`→4, `3/4`→3, `6/8`→3).
- Walk each voice's events accumulating a running beat position. A note/chord/rest that fits in the
  current measure is emitted there. A note that **crosses a barline** is split at the barline and the
  fragments joined with MEI ties (`tie="i"` on the first, `tie="t"` on the last; middle fragments
  `tie="m"` if it spans multiple bars). Rests that cross a barline are simply split (no tie).
- **Duration decomposition:** a fragment's beat-length that is not a single note value is expressed as a
  sequence of tied standard note-values, chosen greedily from largest to smallest ({whole, half,
  quarter, eighth, sixteenth} plus single dots). Since a note only needs decomposition when a barline
  splits it (Panola notes are otherwise single note-values), this path is rarely hit.
- **Voice alignment:** all voices are binned with the same `barBeats`. Shorter voices are padded with
  whole-measure rests so every staff has the same measure count. (v1 assumes voices are meant to align;
  a large mismatch emits a warning.)

### Key signature & accidentals

- `key` → MEI `scoreDef key.sig` (`\Cmajor`/`\Aminor`→`"0"`, `\Gmajor`→`"1s"`, `\Dminor`→`"1f"`,
  `\CsharpMinor`→`"4s"`, …) via a small lookup.
- Accidentals are emitted **relative to the key**: a note whose spelling is already implied by the key
  signature omits `accid`; a note that differs emits `accid` (including `accid="n"` for a natural that
  contradicts the key). This produces clean notation without redundant accidentals, while honoring
  Panola's explicit spelling for chromatic notes.

### Multi-staff assembly

- `scoreDef` builds a `<staffGrp>`; each `braces` range becomes a nested `<staffGrp symbol="brace"
  bar.thru="true">` wrapping those `<staffDef>`s, preserving staff order; loose staves are direct
  children. Each `<measure>` contains one `<staff n="k"><layer>…</layer></staff>` per voice.

### Tuplets — v1 limitation

Panola supports `durmultiplier`/`durdivider` (triplets, etc.). Proper MEI tuplets need `<tuplet>`
grouping. **v1 handles plain durations + dots only and prints a warning if it encounters a tuplet**
(multiplier/divider ≠ 1). Tuplet support is deferred to v2.

## Component 2 — `MSScore` (MusicScene client, this repo)

### API

```supercollider
~score = MSScore(
    voices: [ "c5_4 e2 g4 | a2 g4 f", "<c4 e g>_4 <c e g> r <b3 d g>", "c2_2 g,2 | c2 e2" ],
    clefs: [\treble, \treble, \bass],
    meter: "4/4", key: \Cmajor, braces: [[2, 3]], tempo: 84,
    target: NetAddr("127.0.0.1", 7400), replyPort: 7401, id: "score", space: "2d"
);
~score.play;    // show + play + follow
~score.show;    // just display the notation (no audio)
~score.stop;    // stop clock, free synths, clear cursor
```

- `voices` accepts Panola **strings** (wrapped into `Panola` instances) or ready `Panola` instances.
- Sensible defaults: `id: "score"`, `tempo` from the first Panola / 84, `space` "2d", localhost ports.

### Data flow (`.play`)

1. Build MEI: `Panola.scoreAsMEI(panolas, meter, key, clefs, braces)`.
2. Display: OSC `new notation`, `background white`, `scale`, `pos`, `addressable 1`, `notationData mei …`.
3. Fetch positions: open `replyPort`, register an `OSCdef` for `/ms/reply` `elements`; after a short
   render delay send `elements`; retry a few times until a non-empty reply arrives. Build an ordered,
   de-duplicated `[(when, u)]` list (`when` = Verovio timemap onset in whole notes).
4. Start a `TempoClock` at `tempo`. Play the voices together: `Ppar(panolas.collect { |p, i|
   p.asPbind(instr[i], include_tempo: false) })` — **`include_tempo: false`** so no voice fights the
   shared clock; `MSScore` owns the tempo.
5. Fork the cursor routine on the same clock: for each `(when, u)` in time order, wait until `when * 4`
   beats, then send `cursor pos u 0.5`. Same clock + constant tempo ⇒ the cursor stays note-accurate in
   sync with playback with no per-note callbacks.

### Cursor fallback & error handling

- If no `elements` reply arrives within a timeout (Verovio missing, render failed), `MSScore` prints a
  warning and the cursor **degrades to a linear sweep** over `totalDuration` beats, so it still shows
  and roughly follows rather than failing.
- Panola parse errors surface as Panola's own errors. `.stop` always runs `s.freeAll` and stops the
  clock (consistent with the examples' cleanup fix).

### Voices, sound

- Each voice is played with a caller-selectable instrument (default `\default`, or a bundled
  `\pnote`/`\pad`). v1 ships one simple default voice and lets the user pass their own SynthDef name per
  staff; it does **not** invent a full instrument palette.

## Public API summary

Two entry points cover everything: `Panola.scoreAsMEI(...)` (pure, reusable, testable) and
`MSScore(...).play` (the one-call front door). That is the whole surface for v1.

## Testing

- **`asMEI` mapping (the logic that matters) — verifiable now.** Port the mapping (pitch/duration/chord/
  rest/meter/tie/decomposition/multi-staff/key) to a runnable oracle (Python), feed it representative
  Panola-equivalent inputs, and render every output through the bundled Verovio wrapper + rasterize in
  Godot (`MSNotationBackendSvg`) — the exact method used to validate the examples. Assertions: renders
  without error, correct staff count, expected measure count, ties present where a note crosses a
  barline, key signature glyphs present.
- **`MSScore` orchestration and `asMEI` as sclang — manual.** SuperCollider cannot be run in the
  authoring environment, so both SC pieces are written carefully and **verified interactively by the
  author** (same constraint as the existing examples). The MEI-level oracle de-risks the part that can
  be automated.
- A worked example (`example_panola_score.scd`) doubles as an acceptance test.

## Repos & files

- **Panola quark** (external, author-owned): `Classes/Panola.sc` gains `asMEI`, `*scoreAsMEI`, and the
  private meter/pitch/key helpers. This design provides that code for the author to add; the quark repo
  is not edited from MusicScene.
- **MusicScene** (this repo): a new `MSScore` SuperCollider class under `examples/supercollider/` (or a
  `Classes/` folder if we want it installable), plus `examples/supercollider/example_panola_score.scd`
  and the MEI oracle test under `tools/`. TUTORIAL/README/CHANGELOG note the new front door.

## Scope

- **v1:** pitch / rhythm / chords / rests / auto-ties / multi-staff / key signature (accidentals relative
  to key) / clef / meter / play / note-accurate follow / linear-sweep fallback.
- **v2:** per-note Panola properties → notation (dynamics, articulation, slurs), tuplets, cross-staff
  `staff` override, richer beaming/grouping, and a thin generative-loop wrapper (regenerate voices and
  re-`show` on a cycle) so the generative case becomes a few lines on top of `MSScore`.
