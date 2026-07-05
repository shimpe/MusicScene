# Panola slurs → MEI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render slurs (`@slur^start^` … `@slur^end^`, plus `@slur^endstart^`) from Panola strings as MEI `<slur>` arcs.

**Architecture:** All in the Panola quark's `PanolaMEI.sc`. `@slur` is an ordinary word-valued property (no parser change). `eventsOf` reads it; `voiceToMeasures` keeps one `openStart` and pairs `start`/`end`/`endstart` into slur markers `(startMeasure, startTstamp, endMeasure, endTstamp)`, returning them alongside the existing `dynams`; `scoreAsMEI` emits a measure-level `<slur tstamp tstamp2="Δm+beat" staff>` per marker in its start measure — reusing the `<dynam>` machinery, no `xml:id`s. Notation only.

**Tech stack:** SuperCollider (Panola quark `PanolaMEI.sc`), MEI + Verovio (`addons/musicscene/tools/verovio_render.py`), Python pytest (`tools/panola_mei/`). Full TDD via headless sclang.

**Spec:** `docs/superpowers/specs/2026-07-06-panola-slurs-design.md`

**Two repos.**
- MusicScene (`D:\Projects\MusicScene`, branch `feature/panola-slurs`): the Python tests + docs.
- Panola quark (`C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola`, own git repo): the `.sc` sources — commit there.
- MSScore quark (`C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore`, own git repo): help text — commit there.

**Conventions.**
- sclang: `"C:\Program Files\SuperCollider-3.14.1\sclang.exe" <script.scd>`; editing a `.sc` recompiles the class library on the next run, so a syntax error surfaces immediately.
- **whelk docs:** after editing a quark class keep its `[general]`/`[classmethod]` comments current, then run `gendoc.bat` (whelk: `D:\Projects\python\whelk\whelk.py` via its `.venv`) and eyeball the `.schelp`. Avoid `## … || …` definitionlist syntax in a description — whelk eats those lines; use plain `strong::`-labelled paragraphs.

---

## File structure

| File | Repo | Change |
|---|---|---|
| `tools/panola_mei/render_check.py` | MusicScene | count `<slur` |
| `tools/panola_mei/test_slurs.py` | MusicScene | new pytest (within-bar, cross-barline, chained, unmatched, two-voice) |
| `Classes/PanolaMEI.sc` | Panola | read `slur`; pair in `voiceToMeasures`; emit `<slur>`; whelk docs |
| `Classes/MSScore.sc` | MSScore | add slurs to the expression help section |
| `CHANGELOG.md` | MusicScene | document the feature |

**Event dict** gains `slur` (String). **`voiceToMeasures` return** gains `slurs:` — a list of records `(startMeasure, startTstamp, endMeasure, endTstamp)`.

---

## Task 1: harness counts `<slur`

**Files:** Modify `tools/panola_mei/render_check.py`; Test `tools/panola_mei/test_slurs.py` (new).

- [ ] **Step 1: Write the failing test** (`tools/panola_mei/test_slurs.py`):

```python
"""Slur tests for Panola.scoreAsMEI (PanolaMEI). sclang -> MEI -> Verovio render + assert.
Run:  py -m pytest tools/panola_mei/test_slurs.py -q   (skips if sclang absent)
"""
import os, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

MINIMAL = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<note dur="4" oct="5" pname="c"/><note dur="4" oct="5" pname="d"/>'
  '<note dur="4" oct="5" pname="e"/><note dur="4" oct="5" pname="f"/></layer></staff>'
  '<slur tstamp="1" tstamp2="0m+4" staff="1"/></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_slur():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["slurs"] == 1
```

- [ ] **Step 2: Run to verify it fails.** Run: `py -m pytest tools/panola_mei/test_slurs.py -q`. Expected: FAIL — `KeyError: 'slurs'`.

- [ ] **Step 3: Add the count** — in `tools/panola_mei/render_check.py`, add to the returned dict (next to the `dynam`/`artics` line):

```python
        "slurs": mei.count("<slur "),
```

- [ ] **Step 4: Run to verify it passes.** Same command → PASS.

- [ ] **Step 5: Commit** (MusicScene repo)

```bash
git add tools/panola_mei/render_check.py tools/panola_mei/test_slurs.py
git commit -m "test(panola-mei): count <slur> in the render harness"
```

## Task 2: slur → MEI

**Files:** Modify `Classes/PanolaMEI.sc`; Test `tools/panola_mei/test_slurs.py`.

- [ ] **Step 1: Write the failing test** — append to `tools/panola_mei/test_slurs.py`:

```python
from tools.panola_mei.test_expression import _dump, SCLANG

CASES = {
  "within":    r'Panola.scoreAsMEI([Panola("c5_4@slur^start^ d5 e5 f5@slur^end^ g5")], "4/4", \Cmajor, [\treble], nil)',
  "crossbar":  r'Panola.scoreAsMEI([Panola("c5_4@slur^start^ d5 e5 f5 g5@slur^end^ a5 b5 c6")], "4/4", \Cmajor, [\treble], nil)',
  "chained":   r'Panola.scoreAsMEI([Panola("c5_4@slur^start^ d5 e5@slur^endstart^ f5 g5@slur^end^ a5")], "4/4", \Cmajor, [\treble], nil)',
  "unmatched": r'Panola.scoreAsMEI([Panola("c5_4 d5@slur^end^ e5 f5")], "4/4", \Cmajor, [\treble], nil)',
  "twovoice":  r'Panola.scoreAsMEI([Panola("c5_4 d5 e5 f5"), Panola("c3_4@slur^start^ e3 g3 c4@slur^end^")], "4/4", \Cmajor, [\treble, \bass], nil)',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_slurs():
    outdir = tempfile.mkdtemp(prefix="panola_slur_")
    try:
        _dump(outdir, CASES)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in CASES}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert props["within"]["slurs"] == 1
    assert '<slur tstamp="1" tstamp2="0m+4" staff="1"/>' in meis["within"]
    assert props["crossbar"]["slurs"] == 1
    assert '<slur tstamp="1" tstamp2="1m+1" staff="1"/>' in meis["crossbar"]
    assert props["chained"]["slurs"] == 2
    assert '<slur tstamp="1" tstamp2="0m+3" staff="1"/>' in meis["chained"]
    assert '<slur tstamp="3" tstamp2="1m+1" staff="1"/>' in meis["chained"]
    assert props["unmatched"]["slurs"] == 0
    assert props["twovoice"]["slurs"] == 1 and 'staff="2"' in meis["twovoice"]
```

- [ ] **Step 2: Run to verify it fails.** Run: `py -m pytest tools/panola_mei/test_slurs.py::test_slurs -q`. Expected: FAIL — no `<slur>` yet (`within slurs == 0`).

- [ ] **Step 3: Read `slur` in `eventsOf`.** In `Classes/PanolaMEI.sc`, extend `eventsOf` (add the `slurs` fetch and the `e[\slur]` assignment):

```supercollider
		var eventsOf = { |panola|
			var names = panola.notationnotePattern.asStream.all;
			var durs = panola.notationdurationPattern.asStream.all;
			var beats = panola.durationPattern.asStream.all;
			var dyns = panola.customPropertyPattern("dyn", "").asStream.all;
			var arts = panola.customPropertyPattern("art", "").asStream.all;
			var slurs = panola.customPropertyPattern("slur", "").asStream.all;
			names.collect({ |nm, i|
				var e = parseName.(nm), d = parseDur.(durs[i]);
				e[\meidur] = d[0]; e[\dots] = d[1]; e[\mult] = d[2]; e[\div] = d[3]; e[\beats] = beats[i];
				e[\dyn] = dyns[i].asString; e[\art] = arts[i].asString; e[\slur] = slurs[i].asString;
				e;
			});
		};
```

- [ ] **Step 4: Add the `openSlur`/`slurs` accumulators + `applySlur` in `voiceToMeasures`.** In `Classes/PanolaMEI.sc`, change the `voiceToMeasures` first `var` line to add `openSlur`, `slurs`, `applySlur`:

```supercollider
			var measures = [[]], pos = 0.0, eps = 1e-6, dynams = [], openSlur = nil, slurs = [], applySlur;
```

  Then, immediately **before** the `groupEvents.(events).do({ |unit|` line, insert the pairing helper:

```supercollider
			// pair @slur^start/end/endstart^ into slur markers. one open slur at a time (no nesting);
			// endstart closes the open slur and opens a new one at the same note. m/ts = 1-based measure
			// and beat of the marker note. warn + recover on any mismatch.
			applySlur = { |slurVal, m, ts|
				case
				{ slurVal == "start" } {
					if (openSlur.notNil) { "PanolaMEI: slur start while a slur is open; the previous one is dropped".warn };
					openSlur = ( measure: m, tstamp: ts );
				}
				{ slurVal == "end" } {
					if (openSlur.notNil) {
						slurs = slurs.add(( startMeasure: openSlur[\measure], startTstamp: openSlur[\tstamp], endMeasure: m, endTstamp: ts ));
						openSlur = nil;
					} { "PanolaMEI: slur end with no open slur; ignored".warn };
				}
				{ slurVal == "endstart" } {
					if (openSlur.notNil) {
						slurs = slurs.add(( startMeasure: openSlur[\measure], startTstamp: openSlur[\tstamp], endMeasure: m, endTstamp: ts ));
					} { "PanolaMEI: slur endstart with no open slur; only opening a new one".warn };
					openSlur = ( measure: m, tstamp: ts );
				}
				{ true } { if (slurVal != "") { ("PanolaMEI: unknown slur value '" ++ slurVal ++ "'").warn } };
			};
```

- [ ] **Step 5: Call `applySlur` at each note's onset.** In the **tuplet** branch, immediately after the existing `unit[\members].do({ |mev| if (mev[\dynMark]...` line, add (tuplet-member slur endpoints snap to the tuplet's onset beat):

```supercollider
						unit[\members].do({ |mev| if ((mev[\slur] ? "") != "") { applySlur.(mev[\slur], measures.size, pos + 1) } });
```

  In the **normal** branch, immediately after the existing `if (ev[\dynMark].notNil) { dynams = ... };` line, add:

```supercollider
						if ((ev[\slur] ? "") != "") { applySlur.(ev[\slur], measures.size, pos + 1) };
```

- [ ] **Step 6: Warn on an unclosed slur + return `slurs`.** In `voiceToMeasures`, change the tail (the `if (measures[...].size == 0) …;` line and the return) to:

```supercollider
			if (measures[measures.size-1].size == 0) { measures = measures.copyRange(0, measures.size - 2) };
			if (openSlur.notNil) { "PanolaMEI: unclosed slur at the end of a voice; dropped".warn };
			( measures: measures, dynams: dynams, slurs: slurs );
```

- [ ] **Step 7: Emit `<slur>` in `scoreAsMEI`.** In `Classes/PanolaMEI.sc`, inside the `nm.do({ |i| … })` measure loop, immediately after the `perVoice.do` block that emits `<dynam>` (and before `body = body ++ "</measure>";`), add:

```supercollider
			perVoice.do({ |v, s|
				v[\slurs].select({ |sl| sl[\startMeasure] == (i+1) }).do({ |sl|
					var t1 = sl[\startTstamp], t2 = sl[\endTstamp], dm = sl[\endMeasure] - sl[\startMeasure];
					var t1s = (t1.frac < 1e-6).if({ t1.asInteger.asString }, { t1.asString });
					var t2s = (t2.frac < 1e-6).if({ t2.asInteger.asString }, { t2.asString });
					body = body ++ "<slur tstamp=\"" ++ t1s ++ "\" tstamp2=\"" ++ dm ++ "m+" ++ t2s ++ "\" staff=\"" ++ (s+1) ++ "\"/>";
				});
			});
```

- [ ] **Step 8: Run to verify it passes.** Run: `py -m pytest tools/panola_mei/test_slurs.py::test_slurs -q`. Expected: PASS (within 1, crossbar `1m+1`, chained 2, unmatched 0 + warns but no ERROR, twovoice `staff="2"`). If `chained` fails, confirm `endstart` both emits `openSlur→here` and re-opens at `here`.

- [ ] **Step 9: Commit** (Panola repo)

```bash
git -C "<panola>" add Classes/PanolaMEI.sc
git -C "<panola>" commit -m "feat: slurs (@slur^start/end/endstart^) -> measure-level <slur>"
```

## Task 3: whelk docs on PanolaMEI + regenerate

**Files:** Modify `Classes/PanolaMEI.sc` (Panola repo); regenerate `HelpSource/`.

- [ ] **Step 1: Mention slurs in the `[general]` block.** In `Classes/PanolaMEI.sc`, extend the `description` sentence about per-note properties. Change:

```
and per-note teletype::@dyn:: / teletype::@art:: properties become dynamics and articulation.
```

to:

```
and per-note teletype::@dyn:: / teletype::@art:: properties become dynamics and articulation, while
teletype::@slur^start^:: ... teletype::@slur^end^:: spans become slurs.
```

- [ ] **Step 2: Mention slurs in the `[classmethod.scoreAsMEI]` description.** Change:

```
including ties across barlines, per-beat beaming, tuplets, and per-note dynamics/articulation.
```

to:

```
including ties across barlines, per-beat beaming, tuplets, per-note dynamics/articulation, and slurs.
```

- [ ] **Step 3: Regenerate + eyeball.** Run `gendoc.bat` (Panola repo). Expected: `… PanolaMEI.sc => … PanolaMEI.schelp`, no error. Confirm the DESCRIPTION mentions `@slur` and the `scoreAsMEI` METHOD text mentions slurs.

- [ ] **Step 4: Commit** (Panola repo)

```bash
git -C "<panola>" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "<panola>" commit -m "docs: mention slurs in PanolaMEI help + regenerate HelpSource"
```

## Task 4: document slurs in MSScore help

**Files:** Modify `Classes/MSScore.sc` (MSScore repo); regenerate `HelpSource/`.

- [ ] **Step 1: Add a Slurs paragraph** to the "Per-note expression" section of the `[general]` block in `Classes/MSScore.sc`, immediately after the `strong::Articulation::` paragraph (its last line is the `teletype::c5_4@art[stacc:on] …::` example):

```
strong::Slurs:: - teletype::@slur^start^:: opens a slur and teletype::@slur^end^:: closes it (both notes
are under the arc); teletype::@slur^endstart^:: closes the open slur and opens the next at the same note
(chained phrases). One slur at a time. Example:
teletype::c5_4@slur^start^ d5 e5@slur^endstart^ f5 g5@slur^end^ a5::.
```

- [ ] **Step 2: Regenerate + eyeball.** Run whelk on `MSScore.sc` (`gendoc` in the msscore repo, or the whelk `.venv` directly). Confirm the generated `MSScore.schelp` has the `strong::Slurs::` paragraph intact (no eaten lines).

- [ ] **Step 3: Commit** (MSScore repo)

```bash
git -C "<msscore>" add Classes/MSScore.sc HelpSource/Classes/MSScore.schelp
git -C "<msscore>" commit -m "docs: document slurs in the expression help section"
```

## Task 5: full regression + CHANGELOG

**Files:** `tools/panola_mei/`, `CHANGELOG.md` (MusicScene).

- [ ] **Step 1: Run the whole suite** — Run: `py -m pytest tools/panola_mei/ -q`
Expected: PASS (all of `test_asmei.py` + `test_tuplets.py` + `test_expression.py` + `test_slurs.py`). The existing non-slur cases prove plain / tuplet / expression MEI is unchanged.

- [ ] **Step 2: CHANGELOG entry** — under `## [Unreleased]` → `### Added` in `CHANGELOG.md`, above the expression entry:

```markdown
- **Slurs in Panola notation.** `Panola.scoreAsMEI` / `MSScore` now render slurs: `@slur^start^` opens a
  slur and `@slur^end^` closes it (both notes under the arc), and `@slur^endstart^` closes one and opens
  the next at the same note (chained phrases). One slur at a time; they cross barlines/systems. Notation
  only — playback (`@pdur` legato) is unchanged. (PanolaMEI in the Panola quark, via measure-level
  `<slur tstamp tstamp2>`.)
```

- [ ] **Step 3: Commit** (MusicScene repo)

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): Panola slurs"
```

---

## Self-review

- **Spec coverage:** syntax `start/end/endstart` (Task 2 test + eventsOf); one-open-slur pairing + chained + warn-recover (Task 2 `applySlur`, Steps 4/6); measure-level `<slur tstamp tstamp2="Δm+beat" staff>` (Task 2 Step 7); cross-barline `Δm` (crossbar test); tuplet-onset snap (Step 5 tuplet line); harness (Task 1); PanolaMEI whelk docs (Task 3); MSScore help (Task 4); regression + CHANGELOG (Task 5). All spec sections covered.
- **Type consistency:** event key `slur` set in `eventsOf`, read in both `applySlur` call sites; `voiceToMeasures` returns `(measures:, dynams:, slurs:)`, and `scoreAsMEI` reads `v[\slurs]`; slur record keys `startMeasure/startTstamp/endMeasure/endTstamp` written in `applySlur` and read identically in the emission. `applySlur` used in tuplet + normal branches with the same `(slurVal, m, ts)` signature.
- **Placeholder scan:** no TBD/TODO; every code step shows complete SC/Python.
