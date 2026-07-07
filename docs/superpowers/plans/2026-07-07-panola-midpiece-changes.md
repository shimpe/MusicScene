# Panola mid-piece meter / key / clef changes (SP2f) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Score-level **meter+key changes** at measure boundaries (via a `changes` list) and inline **clef changes** anywhere (via `@clef`), per `docs/superpowers/specs/2026-07-07-panola-midpiece-changes-design.md`.

**Architecture:** `PanolaMEI.scoreAsMEI(voices, changes, clefs, braces)` — `changes` is compiled into per-measure `meterFor(i)`/`keyFor(i)` lookups (built on the SP2e meter descriptor). `voiceToMeasures` consults the current measure's descriptor for variable bar lengths and per-measure key; the `<scoreDef>` emission adds mid-`<section>` scoreDefs where meter/key change; `@clef` (a per-note custom property) emits an inline `<clef>`. Phased: A (API + key + migration), B (meter, variable bb), C (inline clef).

**Tech Stack:** SuperCollider (sclang); Python pytest driving sclang → MEI → Verovio (`tools/panola_mei/`, `render_props`); whelk → schelp via `gendoc.bat`.

---

## Repositories & branches

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch **master**; bash path `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola`). `PanolaMEI.sc` + `Panola.sc` (asMEI) + regenerated HelpSource commit here.
- **MSScore quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore` (branch **master**). `MSScore.sc` commits here.
- **MusicScene repo** — `D:\Projects\MusicScene` (branch **feature/panola-midpiece-changes**). Tests + examples commit here.

sclang `C:\Program Files\SuperCollider-3.14.1\sclang.exe`. Editing a `.sc` recompiles next run; syntax error → MEI fails; runtime error → 120s hang (run the temp `.scd` by hand, **real Windows paths** not `/tmp`). Stuck sclang: PowerShell `Get-Process sclang | Stop-Process -Force`. TAB-indented.

## Current code (reference)

- `*scoreAsMEI { | voices, meter = "4/4", key = \Cmajor, clefs = nil, braces = nil |` (PanolaMEI.sc:54).
- `parseMeter` (`:193`) → SP2e descriptor `( count, num, den, groups, bb, groupStarts, pmeter )`.
- `keyToSig` (`:169`), `accidInKey(pname, accid, k)` (`:170`), `meiElement(ev, md, dt, tie, k)` (`:176`) — `meiElement` spells accidentals with the key `k`.
- `voiceToMeasures { |events, bb, k, pmeter| … }` (`:211`) — barline-splits with a constant `bb`, calls `meiElement(…, k)`.
- `eventsOf` (`:522`) reads `customPropertyPattern("dyn"/"art"/"slur", "")` into `e[\dyn]`/`e[\art]`/`e[\slur]`.
- `clefMap` (IdentityDictionary `\treble->["G","2"]`, `\bass->["F","4"]`, `\alto->["C","3"]`, `\tenor->["C","4"]`) + `staffGrp` build the initial staffDef clefs.
- Body (`:530`): `m = parseMeter.(meter); perVoice = voices.collect { voiceToMeasures.(…, m[\bb], key, m[\pmeter]) }; nm.do { … beamMeasure.(…, m[\groupStarts]) … }`; the top `<scoreDef meter.count=… meter.unit=… key.sig=…>` (`:564`).
- Callers: `Panola.asMEI { |meter, key, clef| ^PanolaMEI.scoreAsMEI([this], meter, key, [clef], nil) }` (Panola.sc:1048); `MSScore.mei { ^Panola.scoreAsMEI(voices, meter, key, clefs, braces) }` (MSScore.sc:356).

---

### Task 1: `changes` API + compilation + full migration (constant case byte-identical)

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (signature, `resolveChanges`, body), `…/panola/Classes/Panola.sc` (asMEI), `…/msscore/Classes/MSScore.sc` (mei)
- Modify: every `tools/panola_mei/test_*.py` scoreAsMEI call, `examples/supercollider/*.scd`

- [ ] **Step 1: Write the failing test** — create `tools/panola_mei/test_midpiece_changes.py`:

```python
"""SP2f: mid-piece meter/key changes via a `changes` list; inline clef via @clef.
Run:  py -m pytest tools/panola_mei/test_midpiece_changes.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_mp_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_new_api_constant_matches_old_shape():
    # a single measure-1 changes entry with no changes: one top <scoreDef>, correct sig, renders.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 a5")], '
               '[( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert mei.count("<scoreDef") == 1, mei
    assert 'meter.count="4" meter.unit="4"' in mei and 'key.sig="0"' in mei, mei
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_midpiece_changes.py -q`
Expected: FAIL — `scoreAsMEI` still takes `(voices, meter, key, clefs, braces)`, so passing a `changes` Array where `meter` is expected mis-parses.

- [ ] **Step 3a: New signature + `resolveChanges`.** Change the signature (PanolaMEI.sc:54-55) to `| voices, changes, clefs = nil, braces = nil |`. Add `resolveChanges` among the pure helpers (near `parseMeter`):

```supercollider
		// compile a `changes` list [ ( measure:, meter:, key: ) … ] into carry-forward per-measure lookups.
		var resolveChanges = { |changes|
			var srt = (changes ? [( measure: 1, meter: "4/4", key: \Cmajor )]).copy
				.sort({ |a, b| a[\measure] < b[\measure] });
			var cm = "4/4", ck = \Cmajor;
			// resolved: each entry's full (meter, key) after applying carry-forward
			srt.collect({ |c| cm = c[\meter] ? cm; ck = c[\key] ? ck; ( measure: c[\measure] ? 1, meter: cm, key: ck ) });
		};
```

- [ ] **Step 3b: Body uses `meterFor`/`keyFor`** (still constant `meterFor(1)`/`keyFor(1)` in Task 1). Replace the body setup (`:530`, the `m = parseMeter.(meter)` line) with:

```supercollider
		var resolved = resolveChanges.(changes);
		var atFor = { |i| var r = resolved.select({ |c| c[\measure] <= i }).last;
			r ? ( measure: 1, meter: "4/4", key: \Cmajor ) };
		var meterFor = { |i| parseMeter.(atFor.(i)[\meter]) };
		var keyFor = { |i| atFor.(i)[\key] };
		var m0 = meterFor.(1), k0 = keyFor.(1);
```
and thread `m0`/`k0` where the old code used `m`/`key`: `voiceToMeasures.(…, m0[\bb], k0, m0[\pmeter])`, `emptyRest.(m0[\bb])`, `beamMeasure.(…, m0[\groupStarts])`, and the top scoreDef `meter.count=m0[\count] meter.unit=m0[\den] key.sig=keyToSig.(k0)`. (`meterFor`/`keyFor` are defined now but only `(1)` is used until Tasks 2–3.)

- [ ] **Step 3c: Migrate the callers.**
  - `Panola.sc:1050`: `^PanolaMEI.scoreAsMEI([this], meter, key, [clef], nil);` → `^PanolaMEI.scoreAsMEI([this], [( measure: 1, meter: meter, key: key )], [clef], nil);` (asMEI keeps its `|meter, key, clef|` signature.)
  - `MSScore.sc:356`: `^Panola.scoreAsMEI(voices, meter, key, clefs, braces)` → `^Panola.scoreAsMEI(voices, [( measure: 1, meter: meter, key: key )], clefs, braces)`. (MSScore keeps its `meter`/`key` instance vars for now.)
  - **Every `tools/panola_mei/test_*.py` `Panola.scoreAsMEI(...)` call**: rewrite `…], "<METER>", <KEY>, <CLEFS>, <BRACES>)` → `…], [( measure: 1, meter: "<METER>", key: <KEY> )], <CLEFS>, <BRACES>)`. Sweep with grep: `grep -rn "scoreAsMEI" tools/panola_mei/`. Leave `.asMEI(...)` calls unchanged (asMEI's signature is unchanged).
  - **Examples** `examples/supercollider/*.scd`: `example_panola_score.scd`, `example_two_hands*.scd`, `example_panola_rhythms.scd`, `example_additive_meter.scd` — these mostly use `MSScore(meter:, key:, clefs:)` (unchanged) or `Panola.scoreAsMEI` in a `~dumpMEI` block. Update any direct `scoreAsMEI` calls to the `changes` form; MSScore-based examples are unaffected.

- [ ] **Step 4: Run to verify pass + byte-identity**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q`
Expected: all green (the new test + every migrated test). **Byte-identity:** the migrated tests assert the same MEI content as before — a single measure-1 `changes` entry must yield the identical document. Independently confirm: dump `Panola.scoreAsMEI([Panola("c5_4 c5_2 c5_4")], [(measure:1, meter:"4/4", key:\Cmajor)], [\treble], nil)` and compare to the old `…, "4/4", \Cmajor, …` output under `git show <old>:Classes/PanolaMEI.sc` — must be identical.

- [ ] **Step 5: Commit** (three repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc Classes/Panola.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola)!: scoreAsMEI takes a changes list (meter/key per measure); migrate asMEI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "feat(msscore): thread a one-entry changes list into scoreAsMEI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_mei examples/supercollider
git commit -m "test(panola_mei)!: migrate scoreAsMEI calls to the changes list; new-API test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Key change (per-measure key + mid-section scoreDef)

**Files:** Modify `…/panola/Classes/PanolaMEI.sc`; test `tools/panola_mei/test_midpiece_changes.py`

- [ ] **Step 1: Add the failing test**

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_key_change_at_a_measure():
    # 4/4 throughout; key goes Cmajor -> Gmajor at bar 2. A mid-section <scoreDef key.sig="1s"/> precedes
    # measure 2, and an f in bar 2 is spelled in G (no natural forced) while an f in bar 1 shows a natural
    # if needed. (c5 e5 g5 f5 | f5 g5 a5 b5)
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 c6 f5_4 g5 a5 b5")], '
               '[( measure: 1, meter: "4/4", key: \\Cmajor ), ( measure: 2, key: \\Gmajor )], [\\treble], nil)')
    body = mei.split("</scoreDef>", 1)[1]     # after the top scoreDef
    assert '<scoreDef key.sig="1s"/>' in body, mei          # mid-section key change before bar 2
    assert body.index('<scoreDef key.sig="1s"') < body.index('<measure n="2"'), mei
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify failure** — no mid-section scoreDef yet.

- [ ] **Step 3: Per-measure key + mid-section scoreDef.**
  - Thread `keyFor` into `voiceToMeasures` so `meiElement` uses the **current measure's** key: change `voiceToMeasures`'s signature to accept `keyFor` (a function) instead of `k`, and at each `meiElement.(ev, …, k)` call, pass `keyFor.(measures.size)`. (Update the `voiceToMeasures.(…)` call in the body to pass `keyFor` instead of `k0`.)
  - In the `nm.do { |i| … }` measure loop, **before** appending `"<measure n=…>"`, emit a mid-section scoreDef when the key (or later, meter) changes at `i` (and `i > 1`):
    ```supercollider
    if ((i > 0) and: { keyFor.(i + 1) != keyFor.(i) }) {   // i is 0-based here; measure number = i+1
        body = body ++ "<scoreDef key.sig=\"" ++ keyToSig.(keyFor.(i + 1)) ++ "\"/>";
    };
    ```
    (Adjust the 0-based `i` vs 1-based measure carefully — the loop is `nm.do { |i| … "<measure n=\"" ++ (i+1) … }`, so measure number is `i+1`; the change condition compares `keyFor.(i+1)` to `keyFor.(i)`.)
  - Keep the top scoreDef at `keyFor.(1)`.

- [ ] **Step 4: Run** — `py -m pytest tools/panola_mei -q` → the key-change test passes; all else green (a single measure-1 entry never triggers the mid-section scoreDef, so byte-identical).

- [ ] **Step 5: Commit** (panola quark + MusicScene test).

---

### Task 3: Meter change (variable bar lengths)

**Files:** Modify `…/panola/Classes/PanolaMEI.sc`; test `tools/panola_mei/test_midpiece_changes.py`

- [ ] **Step 1: Add the failing test**

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_meter_change_4_4_to_3_4():
    # 4/4 for bar 1 (4 quarters), 3/4 from bar 2 (3 quarters/bar). 4 + 3 + 3 = 10 quarters -> 3 measures.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 c6 c5_4 e5 g5 c5_4 e5 g5")], '
               '[( measure: 1, meter: "4/4" ), ( measure: 2, meter: "3/4" )], [\\treble], nil)')
    assert mei.count("<measure ") == 3, mei
    assert '<scoreDef meter.count="3" meter.unit="4"/>' in mei, mei   # mid-section meter change
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify failure** — with constant `bb`, the notes pack into 4/4 bars (wrong measure count, no meter change).

- [ ] **Step 3: Variable `bb`/`pmeter` in `voiceToMeasures`.** Pass `meterFor` (a function) into `voiceToMeasures` instead of the constant `bb`/`pmeter`. Inside, at the top of each measure use `var md = meterFor.(measures.size); var bb = md[\bb], pmeter = md[\pmeter];` and recompute them whenever a new measure begins (the barline-split loop's `take = (bb - pos).min(remaining)` and the `meterPieces.(pos, take, …, pmeter)` call use the current measure's `bb`/`pmeter`). `emptyRest` padding uses `meterFor.(<that measure>)[\bb]`. In the `nm.do` loop, also emit a mid-section `<scoreDef meter.count meter.unit/>` when the meter changes at `i+1` (combine with Task 2's key condition into one scoreDef when both change). `beamMeasure` gets `meterFor.(i+1)[\groupStarts]`.

  This is the intricate task — **let the test drive it**. The barline-split `while` loop must consult the current measure's `bb` (it currently closes over one `bb`); rework it so each new measure re-reads `meterFor.(measures.size)`.

- [ ] **Step 4: Run** — `py -m pytest tools/panola_mei -q` → the meter-change test passes; all else green (constant meter → `meterFor` returns the same descriptor every measure → byte-identical).

- [ ] **Step 5: Commit** (panola quark + MusicScene test).

---

### Task 4: Inline clef (`@clef`)

**Files:** Modify `…/panola/Classes/PanolaMEI.sc`; test `tools/panola_mei/test_midpiece_changes.py`

- [ ] **Step 1: Add the failing test**

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_inline_clef_change_mid_measure():
    # @clef^bass^ on the third note switches to bass clef mid-bar -> an inline <clef shape="F" line="4"/>
    # appears before that note, inside the measure.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g4_4@clef^bass^ c4")], '
               '[( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert '<clef shape="F" line="4"/>' in mei, mei
    layer = mei.split('<layer n="1">')[1].split("</layer>")[0]
    assert layer.index('<clef shape="F"') < layer.index('pname="g"'), mei   # clef precedes the g note
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify failure** — `@clef` is an unknown custom property, ignored today.

- [ ] **Step 3: Read `@clef` and emit an inline `<clef>`.**
  - In `eventsOf` (`:522`), add `var clefsP = panola.customPropertyPattern("clef", "").asStream.all;` and `e[\clef] = clefsP[i].asString;` alongside the dyn/art/slur reads.
  - When a note carries `e[\clef]` (non-empty), the note's emitted record `str` is prefixed with `"<clef shape=\"" ++ clefMap[clef.asSymbol][0] ++ "\" line=\"" ++ clefMap[clef.asSymbol][1] ++ "\"/>"`. Do this in the `\normal` emit path where `meiElement` builds the note str, on the **first fragment only** (a split note's clef leads the first piece). A `@clef` on a tuplet member similarly prefixes that member's str.
  - The `clefMap` symbols: `\treble`/`\bass`/`\alto`/`\tenor`. An unknown clef value warns and is ignored.

- [ ] **Step 4: Run** — `py -m pytest tools/panola_mei -q` → the clef test passes; all else green (no `@clef` → no inline clef → byte-identical).

- [ ] **Step 5: Commit** (panola quark + MusicScene test).

---

### Task 5: Whelk docs refresh + regenerate schelp

**Files:** Modify `…/panola/Classes/PanolaMEI.sc` (+ `Panola.sc` asMEI doc if needed) + `MSScore.sc` doc; regenerate `…/panola/HelpSource`.

- [ ] **Step 1: Update the whelk prose.** In `PanolaMEI`'s `[general]`/`[classmethod.scoreAsMEI]` blocks: the `meter`/`key` args are replaced by a `changes` list (`( measure:, meter:, key: )`, applied at measure starts; measure-1 sets the initial meter/key); mid-piece meter/key changes emit a mid-`section` `<scoreDef>`; a per-note `teletype::@clef^bass^:: `switches that staff's clef mid-measure. Update the `scoreAsMEI.args` for `changes`. Update `Panola.asMEI` and `MSScore` docs if their prose references the old args. Whelk-safe: `strong::`/`teletype::`/`link::` only, no `## … || …`, balanced `/* */`.

- [ ] **Step 2: Regenerate**

```powershell
& "C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\gendoc.bat"
```
Expected: `Done.` no ERROR.

- [ ] **Step 3: Verify** — schelp present; `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q` green; the `.sc` diffs are doc-comment-only.

- [ ] **Step 4: Commit** (panola quark; MSScore if its doc changed).

---

## Final verification

- [ ] `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q` → all green (the 4 new SP2f tests + every migrated existing test).
- [ ] Full regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration tools/panola_mei tools/msscore/test_midi_routing.py -q`.
- [ ] Spot-check: dump a `4/4→3/4` + `Cmajor→Gmajor` + `@clef` score and eyeball the mid-section scoreDefs, the 3/4 bars, and the mid-bar clef.

## Notes for the implementer

- **Byte-identity is the safety line** for Task 1 and every later task: a single measure-1 `changes` entry, no `@clef`, must reproduce today's document exactly (`meterFor`/`keyFor` return the constant values, no mid-section scoreDefs, no inline clefs).
- **The migration (Task 1) is mechanical but wide** — sweep all `scoreAsMEI` calls; `asMEI(...)` calls are unchanged (asMEI wraps internally). Run the full suite after the sweep; the assertions are unchanged, so any failure is a real regression.
- **Task 3 (variable bb) is the intricate one** — the barline-split `while` loop closes over one `bb`; rework it to re-read `meterFor.(measures.size)` when a new measure starts. Let the test drive it; dump MEI to check the measure count + barlines.
- **0-based `i` vs 1-based measure** in the `nm.do` loop: measure number is `i+1`; the mid-section scoreDef condition compares measure `i+1` to `i`.
- **`@clef` on a split/tuplet note** attaches to the first fragment only.
- **Whelk docs (Task 5)** must be whelk-safe or the class library won't compile and the whole suite fails.
- `MSScore` keeps a constant `meter`/`key` surface in this plan (wrapped into a one-entry `changes`); exposing a full `changes` surface on `MSScore` is a later, optional follow-up.
