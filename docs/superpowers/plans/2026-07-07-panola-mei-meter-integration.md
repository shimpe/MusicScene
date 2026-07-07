# Panola MEI meter-aware notation (SP2b v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `PanolaMeterSplitter` into `PanolaMEI`'s `\normal` (non-tuplet) note path so notes are engraved with robust, meter-aware splitting instead of the weak greedy `decompose`, per `docs/superpowers/specs/2026-07-07-panola-mei-meter-integration-design.md`.

**Architecture:** In `PanolaMEI.sc`'s `scoreAsMEI`, build a `PanolaMeter` from the score meter string and thread it into the inner `voiceToMeasures`. Keep the existing per-measure (barline) split; for each per-measure chunk, replace `decompose.(take)` with a new local helper `meterPieces` that runs `PanolaMeterSplitter.split` and flattens the `SplitComponent` spellings into the same `[dur, dots, beats]` fragments the emit loop already consumes. Ties, beaming, `emptyRest`, dynamics/articulation/slurs, and the explicit-`*m/d` tuplet path are unchanged; `decompose` is retained as the inexpressible fallback and for `emptyRest`.

**Tech Stack:** SuperCollider (sclang); Python pytest driving sclang → MEI → Verovio (`tools/panola_mei/` harness, `render_props`); whelk → schelp via the quark's `gendoc.bat`.

---

## Repositories & branches

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (git branch **master**; bash path `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola`). `PanolaMEI.sc` + regenerated HelpSource commit here.
- **MusicScene repo** — `D:\Projects\MusicScene` (git branch **feature/panola-duration-spelling**). The pytest tests commit here.

sclang path: `C:\Program Files\SuperCollider-3.14.1\sclang.exe`. Editing `PanolaMEI.sc` recompiles the class library on the next sclang run; a syntax error surfaces as the MEI generation failing (the test's `_dump_mei` sees `ERROR` in stdout, or the file isn't written). A runtime error aborts the script so `0.exit` never runs → 120s pytest timeout; run the temp `.scd` by hand to see it. Stuck sclang: PowerShell `Get-Process sclang | Stop-Process -Force`. `PanolaMEI.sc` is tab-indented.

## File structure

- **Modify** `…/panola/Classes/PanolaMEI.sc` — `scoreAsMEI`: build `PanolaMeter`, add `meterPieces`, thread the meter through `voiceToMeasures`, switch the `\normal`-path call site (Task 1); whelk doc update (Task 3).
- **Create** `D:\Projects\MusicScene\tools\panola_mei\test_meter_notation.py` — new meter-aware notation tests (Tasks 1–2).
- **Modify** `D:\Projects\MusicScene\tools\panola_mei\test_asmei.py` — reconcile `test_written_values_correct_for_all_plain_durations` to on-downbeat isolation (Task 1).
- **Regenerate** `…/panola/HelpSource/Classes/PanolaMEI.schelp` via `gendoc.bat` (Task 3).

## The exact PanolaMEI edits (shared reference for Task 1)

**(a) `voiceToMeasures` signature** (`PanolaMEI.sc:151`): `var voiceToMeasures = { |events, bb, k|` → `var voiceToMeasures = { |events, bb, k, pmeter|`.

**(b) The `meterPieces` helper** — add immediately after `durToBeats` (`PanolaMEI.sc:82`), so it can see `decompose`/`durToBeats`:

```supercollider
		// meter-aware replacement for decompose on a single per-measure chunk: run the splitter and
		// flatten its SplitComponent spellings to [durToken, dots, beatsFloat] fragments. Falls back to
		// decompose for any (unexpected, for dyadic input) inexpressible piece. onsetBeats/durBeats are
		// Float quarterLength within the current measure.
		var meterPieces = { |onsetBeats, durBeats, isRest, pmeter|
			var comps = PanolaMeterSplitter.split(
				( onsetQL: PanolaRational.fromFloat(onsetBeats),
				  durationQL: PanolaRational.fromFloat(durBeats), isRest: isRest ), pmeter);
			var out = [];
			comps.do({ |c|
				var sp = c[\spelling];
				if (sp[\inexpressible]) {
					("PanolaMEI: inexpressible piece " ++ c[\durationQL].asString ++ " — using decompose").warn;
					decompose.(c[\durationQL].asFloat).do({ |pc| out = out.add([pc[0], pc[1], durToBeats.(pc[0], pc[1])]) });
				} {
					sp[\components].do({ |x| out = out.add([x[\meidur], x[\dots], x[\ql].asFloat]) });
				};
			});
			out;
		};
```

**(c) The `\normal`-path emit loop** (`PanolaMEI.sc:200-214`) — three edits inside the existing `while`: swap the pieces source, make the record `md` numeric, advance `subpos` by the fragment's exact beats. Replace:

```supercollider
						while { remaining > eps } {
							var take = (bb - pos).min(remaining), crosses = remaining > ((bb - pos) + eps);
							var lastFrag = crosses.not, pieces = decompose.(take), subpos = pos;
							pieces.do({ |pc, c|
								var isFirst = firstFrag and: { c == 0 }, isLast = lastFrag and: { c == (pieces.size - 1) }, tie = nil;
								if (ev[\rest].not and: { (isFirst and: { isLast }).not }) {
									tie = isFirst.if({"i"},{ isLast.if({"t"},{"m"}) });
								};
								measures[measures.size-1] = measures[measures.size-1].add(
									( str: meiElement.(ev, pc[0], pc[1], tie, k), md: pc[0], rest: ev[\rest], beatPos: subpos ));
								subpos = subpos + durToBeats.(pc[0], pc[1]);
							});
							pos = pos + take; remaining = remaining - take; firstFrag = false;
							if ((bb - pos) < eps) { measures = measures.add([]); pos = 0.0 };
						};
```

with:

```supercollider
						while { remaining > eps } {
							var take = (bb - pos).min(remaining), crosses = remaining > ((bb - pos) + eps);
							var lastFrag = crosses.not, pieces = meterPieces.(pos, take, ev[\rest], pmeter), subpos = pos;
							pieces.do({ |pc, c|
								var isFirst = firstFrag and: { c == 0 }, isLast = lastFrag and: { c == (pieces.size - 1) }, tie = nil;
								if (ev[\rest].not and: { (isFirst and: { isLast }).not }) {
									tie = isFirst.if({"i"},{ isLast.if({"t"},{"m"}) });
								};
								measures[measures.size-1] = measures[measures.size-1].add(
									( str: meiElement.(ev, pc[0], pc[1], tie, k), md: pc[0].asInteger, rest: ev[\rest], beatPos: subpos ));
								subpos = subpos + pc[2];
							});
							pos = pos + take; remaining = remaining - take; firstFrag = false;
							if ((bb - pos) < eps) { measures = measures.add([]); pos = 0.0 };
						};
```

(`pc[0]` is now the MEI dur token — `"8"`, or `"breve"`/`"long"`/`"maxima"` for notes longer than a whole in wide meters — passed verbatim to `meiElement`; `pc[0].asInteger` gives the numeric value for `beamMeasure` (0 for `breve`/`long`/`maxima`, which correctly never beam); `pc[2]` is the fragment's exact beat length, so no `durToBeats` recomputation.)

**(d) Build the meter and pass it** — in `scoreAsMEI`'s body, `mp = meter.split($/)` is already computed (`PanolaMEI.sc:321`). Add `pmeter` to the body's `var` line (`PanolaMEI.sc:318`: `var bb, perVoice, nm, mp, groupBeats, body = "";` → add `pmeter`), build it right after `mp`, and pass it into the `voiceToMeasures` call (`PanolaMEI.sc:323`):

```supercollider
		pmeter = PanolaMeter(mp[0].asInteger, mp[1].asInteger);
		perVoice = voices.collect({ |p| voiceToMeasures.(annotateExpression.(eventsOf.(p)), bb, key, pmeter) });
```

`emptyRest` still calls `decompose` (unchanged) and the explicit-`*m/d` tuplet unit path is untouched.

---

### Task 1: Integrate the meter-splitter into the `\normal` path + reconcile the suite

**Files:**
- Create/Test: `D:\Projects\MusicScene\tools\panola_mei\test_meter_notation.py`
- Modify: `…/panola/Classes/PanolaMEI.sc` (edits (a)–(d) above)
- Modify: `D:\Projects\MusicScene\tools\panola_mei\test_asmei.py` (reconcile one test)

- [ ] **Step 1: Write the failing test** — create `test_meter_notation.py`:

```python
"""SP2b meter-aware notation tests: PanolaMeterSplitter wired into PanolaMEI's non-tuplet path.
Generates MEI via sclang, asserts on the MEI XML (note/tie counts) and that it renders.
Run:  py -m pytest tools/panola_mei/test_meter_notation.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    """Run sclang, return the MEI string produced by `expr` (a scoreAsMEI/asMEI call)."""
    d = tempfile.mkdtemp(prefix="panola_meter_")
    try:
        path = (d.replace("\\", "/") + "/s.mei")
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd")
        open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


def _notes(mei):   # count <note ...> elements (not <notedef> etc.)
    return len(re.findall(r"<note[ />]", mei))


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_mid_measure_half_note_splits_at_the_4_4_midpoint():
    # c5_4 c5_2 c5_4 in 4/4: the middle half note starts on beat 2 and spans the 2.0 half-measure
    # boundary, so it must split into two tied quarters (quarter + quarter~) rather than one half note.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 c5_2 c5_4")], "4/4", \\Cmajor, [\\treble], nil)')
    assert _notes(mei) == 4, mei              # q + (q~q) + q  (was 3: q + half + q)
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_meter_notation.py -q`
Expected: FAIL — with the current greedy `decompose` (which ignores onset), the middle `c5_2` stays a single half note → `_notes == 3` and no ties.

- [ ] **Step 3: Implement the integration** — apply edits (a), (b), (c), (d) from the shared reference above to `PanolaMEI.sc`.

- [ ] **Step 4: Run the new test**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_meter_notation.py -q`
Expected: PASS (1 passed) — the middle half note is now `quarter + quarter~` (4 notes, tied).

- [ ] **Step 5: Run the full `panola_mei` suite and reconcile the one legitimate change**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q`
Expected: `test_asmei.py::test_written_values_correct_for_all_plain_durations` **FAILS**; everything else passes. Why it fails (verified): that test strings `c5_1 c5_2 c5_4 c5_8 c5_16 c5_4.` in `16/4`; the cumulative onset puts the final dotted quarter at beat **7.75** (off-beat), so the splitter correctly splits it at beats 8 and 9 into `16th + quarter~ + 16th~` — the old greedy `decompose` wrote a single dotted quarter that *hid two beat boundaries*. This is the feature working. Reconcile the test to preserve its **intent** (a plain duration writes the right value+dots) by placing each duration on a **downbeat** (onset 0), where the meter rule never splits it. Replace the body of `test_written_values_correct_for_all_plain_durations` in `test_asmei.py` with:

```python
def test_written_values_correct_for_all_plain_durations():
    """Each plain duration, placed on a downbeat (onset 0) so the meter rule never splits it,
    must still write the correct value + dots. (A syncopated duration is split by design — see
    tools/panola_mei/test_meter_notation.py.)"""
    import re
    if not os.path.exists(SCLANG):
        pytest.skip("sclang not installed")
    # one bar per duration, each note first-in-bar (onset 0). 16/4 so a whole note is well within a bar.
    cases = [("c5_1", "1", "0"), ("c5_2", "2", "0"), ("c5_4", "4", "0"),
             ("c5_8", "8", "0"), ("c5_16", "16", "0"), ("c5_4.", "4", "1")]
    outdir = tempfile.mkdtemp(prefix="panola_dur_")
    try:
        got = []
        for src, _, _ in cases:
            scd = ('( File.use("%s/d.mei","w",{|f| f.write('
                   'Panola("%s").asMEI("16/4", \\Cmajor, \\treble)) }); "DONE".postln; 0.exit; )'
                   % (outdir.replace("\\", "/"), src))
            p = os.path.join(outdir, "s.scd"); open(p, "w").write(scd)
            subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
            mei = open(os.path.join(outdir, "d.mei"), encoding="utf-8").read()
            m = re.search(r'<note dur="(\w+)"( dots="(\d+)")?', mei)
            got.append((m.group(1), (m.group(3) or "0")))
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    assert got == [("1", "0"), ("2", "0"), ("4", "0"), ("8", "0"), ("16", "0"), ("4", "1")], got
```

- [ ] **Step 6: Run the full suite to verify green**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q`
Expected: PASS — `test_meter_notation` (1), `test_asmei` (2, incl. the reconciled one), `test_tuplets`, `test_expression`, `test_slurs` all pass. (The `test_asmei` cases `ties`/`beams`/`waltz`/`single`/`grand`/`chords`/`rests`/`gmajor` are unaffected: their notes sit on beats or split identically — a whole note tied across a barline still yields two tied halves; eighths on beats still beam 4-per-bar.)

- [ ] **Step 7: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): meter-aware note splitting in PanolaMEI (non-tuplet path)

Replace the greedy decompose in the \\normal path with PanolaMeterSplitter:
build PanolaMeter from the score meter, split each per-measure chunk at the
metrical boundaries stronger than the note's onset, spell + tie. Explicit
*m/d tuplets, ties, beaming, emptyRest unchanged; decompose kept as fallback.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_mei/test_meter_notation.py tools/panola_mei/test_asmei.py
git commit -m "test(panola_mei): meter-aware split of a mid-measure half note; on-downbeat plain-value test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Additional meter-aware notation tests

**Files:**
- Modify/Test: `D:\Projects\MusicScene\tools\panola_mei\test_meter_notation.py`

- [ ] **Step 1: Add the tests** — append to `test_meter_notation.py`:

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_offbeat_quarter_splits_into_tied_eighths():
    # c5_8 c5_4 c5_8 in 2/4: the quarter starts on the off-beat (0.5) and spans beat 1.0, so it
    # splits into two tied eighths -> eighth + (eighth~eighth) + eighth = 4 notes.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8 c5_4 c5_8")], "2/4", \\Cmajor, [\\treble], nil)')
    assert _notes(mei) == 4, mei
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_half_notes_on_strong_beats_are_not_over_split():
    # c5_2 c5_2 in 4/4: each half note starts on a boundary at least as strong as any it spans
    # (onset 0 -> 100, onset 2 -> 80), so neither is split -> 2 plain half notes, no ties.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_2 c5_2")], "4/4", \\Cmajor, [\\treble], nil)')
    assert _notes(mei) == 2, mei
    assert 'tie="i"' not in mei and 'tie="t"' not in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dotted_quarter_on_downbeat_stays_whole():
    # c5_4. c5_8 in 4/4: the dotted quarter is on beat 1 (onset 0) and spans only the weaker beat-1
    # boundary, so it stays a single dotted quarter (dur="4" dots="1"), not split.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4. c5_8")], "4/4", \\Cmajor, [\\treble], nil)')
    assert re.search(r'<note dur="4" dots="1"', mei), mei
    assert 'tie="i"' not in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_explicit_tuplet_path_unchanged():
    # a triplet (c5_4*2/3 = 3 quarters in the space of 2) still renders through the unchanged atomic
    # tuplet path -> one <tuplet num="3" numbase="2"> with three written quarters.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert '<tuplet num="3" numbase="2">' in mei, mei
    assert mei.count('<note dur="4"') == 3, mei
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_meter_notation.py -q`
Expected: PASS (5 passed — the Task-1 test plus these four).

- [ ] **Step 3: Commit**

```bash
cd /d/Projects/MusicScene
git add tools/panola_mei/test_meter_notation.py
git commit -m "test(panola_mei): syncopation split, anti-over-split, on-beat dotted quarter, tuplet unchanged

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Whelk docs refresh + regenerate schelp

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (doc comment only)
- Regenerate: `…/panola/HelpSource/Classes/PanolaMEI.schelp`

- [ ] **Step 1: Update the whelk doc.** `PanolaMEI` is documented by the `[general]`/`[classmethod.*]` whelk blocks already in `PanolaMEI.sc`. Update the prose that describes duration handling so it reflects the meter-aware splitting (mentioning `link::Classes/PanolaMeterSplitter::` and `link::Classes/PanolaMeter::`, e.g. "durations are split meter-aware at metrical boundaries via PanolaMeterSplitter and tied; explicit `*m/d` tuplets are emitted atomically"). Do NOT invent new `[method.*]` blocks for the inner closures (`meterPieces` etc. are locals inside `scoreAsMEI`, not methods). Keep it whelk-safe: `strong::`/`teletype::`/`link::` only, never `## … || …`; balanced `/* */`. Study the existing blocks in `PanolaMEI.sc` and a sibling like `PanolaDurationSpeller.sc`.

- [ ] **Step 2: Regenerate all schelp**

```powershell
& "C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\gendoc.bat"
```
Expected: `Removing old help files...` / `Generating help files...` / `Done.` with no `ERROR`.

- [ ] **Step 3: Verify compile + render still green**

```bash
ls "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMEI.schelp"
cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q
```
Expected: schelp present; `tools/panola_mei` all pass (a doc-comment edit must not change MEI output or break compilation). The other 7 class schelp should reproduce byte-for-byte (only `PanolaMEI.schelp` changes).

- [ ] **Step 4: Commit** (Panola quark)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "docs(panola): PanolaMEI whelk doc notes meter-aware splitting; regen schelp (gendoc)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q` → all green (5 meter-notation + the reconciled `test_asmei` pair + `test_tuplets`/`test_expression`/`test_slurs`).
- [ ] Full regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration tools/panola_mei tools/msscore/test_midi_routing.py -q` → SP1 duration-speller, SP2a meter-splitter, and msscore suites unaffected.
- [ ] Spot-render one meter-aware case by eye (optional): dump the `c5_4 c5_2 c5_4` MEI and confirm Verovio shows a quarter, two tied quarters, and a quarter across one 4/4 bar.

## Notes for the implementer

- **Float↔rational bridge:** `pos`/`take` are dyadic (non-tuplet Panola beats), so `PanolaRational.fromFloat` is exact. If `PanolaRational.fromFloat(0.0)` misbehaves, guard onset 0 → `PanolaRational(0, 1)` (it should already produce that).
- **`decompose` stays.** Only the one `\normal`-path call site changes; `emptyRest` and the inexpressible fallback still use it. Don't delete it.
- **`meidur` token vs numeric.** `meiElement` gets the token (`pc[0]`); the record's `md` must be numeric (`pc[0].asInteger`) for `beamMeasure`. A `nil` `meidur` (only `duplexMaxima`, 64 beats — unreachable in real meters) is out of scope.
- **Regression discipline.** The *only* existing test that should change is `test_written_values_correct_for_all_plain_durations`, and only because its cumulative onset made a note syncopated. If any *other* existing `panola_mei` assertion changes, STOP and investigate — it may be a real regression, not an improvement. Show the before/after MEI for anything you change.
- **Explicit tuplets unchanged.** Do not route `\tuplet` units through the splitter (that's SP2c). `test_explicit_tuplet_path_unchanged` guards this.
- **Whelk docs (Task 3)** must be whelk-safe (`strong::`/`teletype::`/`link::`, balanced `/* */`, no `## … || …`) — a malformed block breaks class-library compilation and the whole suite fails.
