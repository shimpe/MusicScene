# Panola Tuplets → MEI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render Panola tuplets (triplets, quintuplets, …) as proper MEI `<tuplet>` groups instead of the current silent approximation to the nearest plain note value.

**Architecture:** All engraving logic lives in `PanolaMEI.sc` (the Panola quark). A rewritten `parseDur` exposes each note's written value + `mult/div`; a `groupEvents` pass splits a voice into *units* — plain notes (unchanged, beats-driven) and *tuplet groups* (consecutive same-ratio notes closed when their accumulated actual duration fills a power-of-2 container). Tuplet groups are emitted as `<tuplet num numbase>` at written values and treated as atomic by the meter engine (never decomposed or split across a barline). No MusicScene/`MSScore` changes — a tuplet is just more MEI.

**Tech stack:** SuperCollider (`PanolaMEI.sc` in the Panola quark), MEI + Verovio (`addons/musicscene/tools/verovio_render.py`), Python 3 pytest harness (`tools/panola_mei/`). Full TDD: sclang runs headlessly here.

**Spec:** `docs/superpowers/specs/2026-07-05-panola-tuplets-design.md`

**Two repos.**
- MusicScene (`D:\Projects\MusicScene`, branch `feature/panola-tuplets`): the Python test harness + docs.
- Panola quark (`C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola`, its own git repo): `Classes/PanolaMEI.sc`. Commit those changes in *that* repo.

**Conventions.**
- sclang: `"C:\Program Files\SuperCollider-3.14.1\sclang.exe" <script.scd>`; end scripts with `0.exit;`.
- Verovio wrapper: `py addons/musicscene/tools/verovio_render.py <in.mei> <out.svg> --page 1`.
- Beats are quarter-notes. Panola `notationdurationPattern` → `_<value>.0( .)*(\*<mult>/<div>)?` (e.g. `_8.0 .*2/3`); `durationPattern` → actual beats. MEI tuplet: `num = div`, `numbase = mult`.
- **After editing `PanolaMEI.sc`, run any test via sclang — sclang recompiles the class library on start, so a syntax error surfaces immediately as a compile error.**

---

## File structure

| File | Repo | Responsibility |
|---|---|---|
| `Classes/PanolaMEI.sc` | Panola quark | `parseDur` rewrite; `eventsOf` carries `mult/div/meidur/dots`; `groupEvents`; tuplet emission (`tupletMEI`, `beamRun`); atomic tuplets in `voiceToMeasures`. |
| `tools/panola_mei/render_check.py` | MusicScene | Add `tuplets` count (of `<tuplet ` in the MEI) to the reported props. |
| `tools/panola_mei/test_tuplets.py` | MusicScene | New pytest: sclang → MEI files → render + assert tuplet structure. |
| `tools/panola_mei/test_asmei.py` | MusicScene | Add a regression asserting non-tuplet MEI is unchanged by the `parseDur` rewrite. |
| `CHANGELOG.md` | MusicScene | Document the feature. |

**Event dict** (produced by `eventsOf`): `( kind: \note|\rest, pnames:[...], accids:[...], octs:[...], meidur:Int, dots:Int, mult:Int, div:Int, beats:Float )`.
**Unit dict** (produced by `groupEvents`): plain `( kind:\normal, ev:<event> )` or tuplet `( kind:\tuplet, num:Int(=div), numbase:Int(=mult), members:[<events>], beats:Float, complete:Bool )`.
**Measure record** (inside a measure array): `( str:MEI, md:Int, rest:Bool, beatPos:Float [, tuplet:true] )` — a tuplet unit becomes one record with `md:0` so `beamMeasure` passes it through untouched.

---

## Task 1: Harness — count tuplets in rendered MEI

**Files:** Modify `tools/panola_mei/render_check.py`; Test `tools/panola_mei/test_tuplets.py` (new).

- [ ] **Step 1: Write the failing test** (`tools/panola_mei/test_tuplets.py`)

```python
"""Tuplet rendering tests for Panola.scoreAsMEI (PanolaMEI in the Panola quark).
Runs sclang to generate MEI, renders via Verovio, and asserts tuplet structure.
Run:  py -m pytest tools/panola_mei/test_tuplets.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

MINIMAL_TUPLET = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<tuplet num="3" numbase="2"><note dur="8" oct="5" pname="c"/><note dur="8" oct="5" pname="d"/>'
  '<note dur="8" oct="5" pname="e"/></tuplet>'
  '<rest dur="2"/></layer></staff></measure></section></score></mdiv></body></music></mei>')

def test_render_props_counts_tuplets():
    p = render_props(MINIMAL_TUPLET)
    assert p["ok"] is True
    assert p["tuplets"] == 1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `py -m pytest tools/panola_mei/test_tuplets.py -q`
Expected: FAIL — `KeyError: 'tuplets'`.

- [ ] **Step 3: Add the `tuplets` prop** — in `tools/panola_mei/render_check.py`, extend the returned dict:

```python
        "beams": svg.count('class="beam"'), "flag_glyphs": svg.count('class="flag"'),
        "tuplets": mei.count("<tuplet "),
    }
```

(Insert the `"tuplets"` line just before the closing `}` of the `render_props` return dict.)

- [ ] **Step 4: Run to verify it passes**

Run: `py -m pytest tools/panola_mei/test_tuplets.py -q`
Expected: PASS.

- [ ] **Step 5: Commit** (MusicScene repo)

```bash
git add tools/panola_mei/render_check.py tools/panola_mei/test_tuplets.py
git commit -m "test(panola-mei): count <tuplet> groups in the render harness"
```

---

## Task 2: Rewrite `parseDur`; carry `mult/div` on events

**Files:** Modify `Classes/PanolaMEI.sc` (Panola quark); Test `tools/panola_mei/test_asmei.py` (MusicScene).

The current `parseDur` mis-parses the float value form (`8.0` → `80`) — harmless today because its output is unused, but the tuplet path will consume it. This task rewrites it and proves non-tuplet output is unchanged.

- [ ] **Step 1: Write the failing regression test** — append to `tools/panola_mei/test_asmei.py`:

```python
def test_written_values_correct_for_all_plain_durations():
    """After the parseDur rewrite, written value + dots must be correct for plain notes."""
    import re
    outdir = tempfile.mkdtemp(prefix="panola_dur_")
    scd = ('( File.use("%s/d.mei","w",{|f| f.write('
           'Panola("c5_1 c5_2 c5_4 c5_8 c5_16 c5_4. c5_8..").asMEI("4/4", \\Cmajor, \\treble)) });'
           ' "DONE".postln; 0.exit; )' % outdir.replace("\\", "/"))
    p = os.path.join(outdir, "s.scd"); open(p, "w").write(scd)
    if not os.path.exists(SCLANG):
        pytest.skip("sclang not installed")
    subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
    mei = open(os.path.join(outdir, "d.mei"), encoding="utf-8").read()
    shutil.rmtree(outdir, ignore_errors=True)
    durs = re.findall(r'<note dur="(\d+)"( dots="(\d+)")?', mei)
    got = [(d, (dots or "0")) for d, _, dots in durs]
    assert got == [("1","0"),("2","0"),("4","0"),("8","0"),("16","0"),("4","1"),("8","2")]
```

- [ ] **Step 2: Run to verify it fails** (or passes trivially — the current beats-driven path already yields these). Run: `py -m pytest tools/panola_mei/test_asmei.py::test_written_values_correct_for_all_plain_durations -q`. This test guards that the `parseDur` rewrite (next step) does not regress plain output. If it passes now, keep it; it must still pass after Step 3.

- [ ] **Step 3: Rewrite `parseDur` in `Classes/PanolaMEI.sc`.** Replace the whole `var parseDur = { ... };` block with:

```supercollider
		var parseDur = { |s|
			// notationdurationPattern form: "_<value>.0( .)*(\*<mult>/<div>)?", e.g. "_8.0 .*2/3"
			var afterU = s.copyRange(1, s.size - 1);
			var starIdx = afterU.indexOf($*);
			var durPart = if (starIdx.notNil) { afterU.copyRange(0, starIdx - 1) } { afterU };
			var ratioPart = if (starIdx.notNil) { afterU.copyRange(starIdx + 1, afterU.size - 1) } { "1/1" };
			var tokens = durPart.split($ );                 // ["8.0", "."]
			var value = tokens[0].asFloat.asInteger;        // 8
			var dots = tokens.size - 1;                     // count of space-separated "."
			var ratio = ratioPart.split($/);                // ["2", "3"]
			[value, dots, ratio[0].asInteger, ratio[1].asInteger];   // [meidur, dots, mult, div]
		};
```

- [ ] **Step 4: Carry `mult`/`div` on events.** In `eventsOf` (same file), replace the `names.collect(...)` line with:

```supercollider
			names.collect({ |nm, i|
				var e = parseName.(nm), d = parseDur.(durs[i]);
				e[\meidur] = d[0]; e[\dots] = d[1]; e[\mult] = d[2]; e[\div] = d[3]; e[\beats] = beats[i];
				e;
			});
```

- [ ] **Step 5: Run the regression + the full plain suite**

Run: `py -m pytest tools/panola_mei/test_asmei.py -q`
Expected: PASS (plain durations correct; all existing cases still render).

- [ ] **Step 6: Commit** — Panola repo (`PanolaMEI.sc`) and MusicScene repo (`test_asmei.py`) separately:

```bash
git -C "<panola>" add Classes/PanolaMEI.sc && git -C "<panola>" commit -m "refactor: parseDur yields (value,dots,mult,div); events carry mult/div"
git add tools/panola_mei/test_asmei.py && git commit -m "test(panola-mei): guard plain written durations after parseDur rewrite"
```

---

## Task 3: Group into tuplet units + emit `<tuplet>` (the core)

**Files:** Modify `Classes/PanolaMEI.sc`; Test `tools/panola_mei/test_tuplets.py`.

- [ ] **Step 1: Write the failing test** — append to `test_tuplets.py`:

```python
CASES = {   # name -> Panola.scoreAsMEI expression
    "triplet": 'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 e5 c5_2 r_4")], "4/4", \\Cmajor, [\\treble], nil)',
}

def _dump(outdir, cases):
    dir_sc = outdir.replace("\\", "/") + "/"
    lines = ['File.mkdir("%s");' % dir_sc]
    for n, expr in cases.items():
        lines.append('File.use("%s%s.mei","w",{|f| f.write(%s) });' % (dir_sc, n, expr))
    lines.append('"DONE".postln; 0.exit;')
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write("(\n" + "\n".join(lines) + "\n)\n"); path = f.name
    try:
        r = subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    assert "ERROR" not in r.stdout and "parse panola" not in r.stdout, r.stdout[-1500:]

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_eighth_triplet():
    outdir = tempfile.mkdtemp(prefix="panola_tup_")
    try:
        _dump(outdir, {"triplet": CASES["triplet"]})
        mei = open(os.path.join(outdir, "triplet.mei"), encoding="utf-8").read()
        p = render_props(mei)
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    assert p["ok"], p["stderr"][:200]
    assert p["tuplets"] == 1
    assert '<tuplet num="3" numbase="2">' in mei
    assert mei.count('<note dur="8"') == 3          # three written eighths inside the tuplet
```

- [ ] **Step 2: Run to verify it fails.** Run: `py -m pytest tools/panola_mei/test_tuplets.py::test_eighth_triplet -q`. Expected: FAIL — no `<tuplet>` (the triplet is currently decomposed to sixteenths).

- [ ] **Step 3: Add `beamRun` + `tupletMEI` helpers** in `Classes/PanolaMEI.sc`, immediately after the existing `beamMeasure` block:

```supercollider
		// beam consecutive beamable members (dur >= 8, not rest); used inside a tuplet
		var beamRun = { |recs|
			var result = "", i = 0;
			while { i < recs.size } {
				var rec = recs[i], beamable = rec[\rest].not and: { rec[\md] >= 8 };
				if (beamable) {
					var run = [rec], j = i + 1;
					while { (j < recs.size) and: { recs[j][\rest].not and: { recs[j][\md] >= 8 } } } { run = run.add(recs[j]); j = j + 1 };
					if (run.size >= 2) { result = result ++ "<beam>" ++ run.collect({ |r| r[\str] }).join ++ "</beam>" } { result = result ++ run[0][\str] };
					i = j;
				} { result = result ++ rec[\str]; i = i + 1 };
			};
			result;
		};
		// one tuplet group -> <tuplet num numbase> at written values, beamable members beamed inside
		var tupletMEI = { |unit, k|
			var recs = unit[\members].collect({ |ev|
				( str: meiElement.(ev, ev[\meidur], ev[\dots], nil, k), md: ev[\meidur], rest: ev[\rest] );
			});
			"<tuplet num=\"" ++ unit[\num] ++ "\" numbase=\"" ++ unit[\numbase] ++ "\">" ++ beamRun.(recs) ++ "</tuplet>";
		};
		// split a voice's events into plain-note units and tuplet-group units.
		// A tuplet run (same mult/div != 1/1) closes when its accumulated actual beats fill a
		// power-of-2 container (0.25/0.5/1/2/4); an unclosed run is emitted as a partial tuplet + warning.
		var groupEvents = { |events|
			var units = [], i = 0, eps = 1e-6, containers = [0.25, 0.5, 1.0, 2.0, 4.0];
			while { i < events.size } {
				var ev = events[i];
				if ((ev[\mult] == 1) and: { ev[\div] == 1 }) {
					units = units.add(( kind: \normal, ev: ev )); i = i + 1;
				} {
					var m = ev[\mult], d = ev[\div], members = [], acc = 0.0, closed = false;
					while { (i < events.size) and: { (events[i][\mult] == m) and: { events[i][\div] == d } } and: { closed.not } } {
						members = members.add(events[i]); acc = acc + events[i][\beats]; i = i + 1;
						if (containers.any({ |c| (acc - c).abs < eps })) { closed = true };
					};
					if (closed.not) { ("PanolaMEI: incomplete tuplet (" ++ members.size ++ " notes, ratio " ++ d ++ ":" ++ m ++ ") — emitting a partial bracket").warn };
					units = units.add(( kind: \tuplet, num: d, numbase: m, members: members, beats: acc, complete: closed ));
				};
			};
			units;
		};
```

- [ ] **Step 4: Consume units in `voiceToMeasures`.** Replace the opening of the `voiceToMeasures` block — change the top line and wrap the per-event body in a normal/tuplet branch. Replace:

```supercollider
		var voiceToMeasures = { |events, bb, k|
			var measures = [[]], pos = 0.0, eps = 1e-6;
			events.do({ |ev|
				var remaining = ev[\beats], firstFrag = true;
```

with:

```supercollider
		var voiceToMeasures = { |events, bb, k|
			var measures = [[]], pos = 0.0, eps = 1e-6;
			groupEvents.(events).do({ |unit|
				if (unit[\kind] == \tuplet) {
					var tbeats = unit[\beats];
					if ((tbeats > ((bb - pos) + eps)) and: { (bb - pos) > eps }) {
						("PanolaMEI: tuplet crosses a barline; kept whole in bar " ++ measures.size ++ " (split tuplets unsupported)").warn;
					};
					measures[measures.size-1] = measures[measures.size-1].add(( str: tupletMEI.(unit, k), md: 0, rest: false, beatPos: pos, tuplet: true ));
					pos = pos + tbeats;
					if (pos >= (bb - eps)) { measures = measures.add([]); pos = (pos - bb).max(0.0) };
				} {
					var ev = unit[\ev];
					var remaining = ev[\beats], firstFrag = true;
```

Then, at the **end** of the original per-event body, add one extra `}` to close the new `if (... tuplet ...) { } { ... }`. The original body ended:

```supercollider
					pos = pos + take; remaining = remaining - take; firstFrag = false;
					if ((bb - pos) < eps) { measures = measures.add([]); pos = 0.0 };
				};
			});
```

change it to (note the added `}` closing the normal branch, before `});`):

```supercollider
					pos = pos + take; remaining = remaining - take; firstFrag = false;
					if ((bb - pos) < eps) { measures = measures.add([]); pos = 0.0 };
				};
				};
			});
```

- [ ] **Step 5: Run to verify it passes**

Run: `py -m pytest tools/panola_mei/test_tuplets.py::test_eighth_triplet -q`
Expected: PASS — `<tuplet num="3" numbase="2">` with three `dur="8"` notes, renders OK.

- [ ] **Step 6: Commit** (Panola repo)

```bash
git -C "<panola>" add Classes/PanolaMEI.sc
git -C "<panola>" commit -m "feat: render tuplets as MEI <tuplet> (duration-based grouping, atomic in the meter engine)"
```

---

## Task 4: Grouping correctness — mixed, split runs, quintuplet, quarter-triplet

**Files:** Test `tools/panola_mei/test_tuplets.py` (the code from Task 3 should already handle these — this task proves it and fixes anything that fails).

- [ ] **Step 1: Add the cases** to `CASES` in `test_tuplets.py`:

```python
    "sixeighths": 'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 e5 f5 g5 a5")], "4/4", \\Cmajor, [\\treble], nil)',
    "mixed":      'Panola.scoreAsMEI([Panola("c5_4*2/3 d5_8*2/3 c5_2")], "4/4", \\Cmajor, [\\treble], nil)',
    "quintuplet": 'Panola.scoreAsMEI([Panola("c5_16*4/5 d5 e5 f5 g5")], "4/4", \\Cmajor, [\\treble], nil)',
    "quarter3":   'Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)',
```

- [ ] **Step 2: Write the test**

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_duration_based_grouping():
    outdir = tempfile.mkdtemp(prefix="panola_tup_")
    try:
        _dump(outdir, {k: CASES[k] for k in ["sixeighths","mixed","quintuplet","quarter3"]})
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read()
                for k in ["sixeighths","mixed","quintuplet","quarter3"]}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert props["sixeighths"]["tuplets"] == 2                                # two triplets, not one 6-tuplet
    assert meis["mixed"].count("<tuplet") == 1                                 # quarter+eighth = one triplet
    assert meis["mixed"].count('<note dur="4"') >= 1 and meis["mixed"].count('<note dur="8"') >= 1
    assert '<tuplet num="5" numbase="4">' in meis["quintuplet"]
    assert '<tuplet num="3" numbase="2">' in meis["quarter3"] and meis["quarter3"].count('<note dur="4"') == 3
```

- [ ] **Step 3: Run**

Run: `py -m pytest tools/panola_mei/test_tuplets.py::test_duration_based_grouping -q`
Expected: PASS. If a case fails, the bug is in `groupEvents`' container logic — compare the accumulated `acc` against `containers` for that ratio and fix (do not weaken the assertions).

- [ ] **Step 4: Commit** (MusicScene repo)

```bash
git add tools/panola_mei/test_tuplets.py
git commit -m "test(panola-mei): duration-based tuplet grouping (mixed/split/quintuplet/quarter)"
```

---

## Task 5: Edge cases — tuplet + plain in a bar, rests, incomplete run

**Files:** Test `tools/panola_mei/test_tuplets.py`.

- [ ] **Step 1: Add cases**

```python
    "then_plain": 'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 e5 c5_4 d5_4 e5_2")], "4/4", \\Cmajor, [\\treble], nil)',
    "with_rest":  'Panola.scoreAsMEI([Panola("c5_8*2/3 r d5 c5_2 r_4")], "4/4", \\Cmajor, [\\treble], nil)',
    "incomplete": 'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 c5_4 d5 e5 f5")], "4/4", \\Cmajor, [\\treble], nil)',
```

- [ ] **Step 2: Write the test**

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplet_edge_cases():
    outdir = tempfile.mkdtemp(prefix="panola_tup_")
    try:
        _dump(outdir, {k: CASES[k] for k in ["then_plain","with_rest","incomplete"]})
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read()
                for k in ["then_plain","with_rest","incomplete"]}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    # a plain quarter after the triplet is NOT inside a tuplet
    tp = meis["then_plain"]
    assert tp.count("<tuplet") == 1 and '</tuplet><note dur="4"' in tp.replace(" ", " ")
    # a rest can be a tuplet member
    assert "<tuplet" in meis["with_rest"] and "<rest" in meis["with_rest"].split("</tuplet>")[0]
    # renders despite an incomplete run (partial bracket + warning)
    assert props["incomplete"]["tuplets"] >= 1
```

- [ ] **Step 3: Run**

Run: `py -m pytest tools/panola_mei/test_tuplets.py::test_tuplet_edge_cases -q`
Expected: PASS. `<rest>` inside a tuplet works because `meiElement` already emits `<rest>` for `ev[\rest]`; the incomplete run renders because `groupEvents` emits the partial group. If the `then_plain` assertion about `</tuplet><note dur="4"` fails, confirm the quarter is a `\normal` unit (it has `mult==div==1`) and is emitted by the normal path, not swallowed by the tuplet.

- [ ] **Step 4: Commit** (MusicScene repo)

```bash
git add tools/panola_mei/test_tuplets.py
git commit -m "test(panola-mei): tuplet edge cases (plain-after, rests, incomplete run)"
```

---

## Task 6: Full regression + docs

**Files:** `tools/panola_mei/test_asmei.py`, `CHANGELOG.md`, `examples/supercollider/example_panola_score.scd` (optional demo comment).

- [ ] **Step 1: Run the whole suite** to confirm no regression:

Run: `py -m pytest tools/panola_mei/ -q`
Expected: PASS (all of `test_asmei.py` + `test_tuplets.py`). The existing non-tuplet cases in `test_asmei.py` prove plain scores still render identically.

- [ ] **Step 2: Add a CHANGELOG entry** — under `## [Unreleased]` → `### Added` in `CHANGELOG.md`:

```markdown
- **Tuplets in Panola notation.** `Panola.scoreAsMEI` / `MSScore` now render Panola tuplets (triplets,
  quintuplets, …; `c5_8*2/3 d5 e5`) as proper MEI `<tuplet>` brackets instead of approximating them as the
  nearest plain note value. Groups are formed by accumulated duration (so mixed-value tuplets like
  `c5_4*2/3 d5_8*2/3` group correctly) and are kept whole within a bar; barline-crossing / incomplete /
  nested cases render a best-effort bracket with a warning. (PanolaMEI in the Panola quark.)
```

- [ ] **Step 3: Commit** (MusicScene repo)

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): Panola tuplets -> MEI"
```

---

## Self-review

- **Spec coverage:** parsing rewrite (Task 2), two paths / normal unchanged (Task 2 regression + Task 3 branch), duration-based grouping on power-of-2 containers (Task 3 `groupEvents`, Task 4), emission `<tuplet num=div numbase=mult>` + inner beam (Task 3 `tupletMEI`/`beamRun`), atomic meter handling + barline warn (Task 3 `voiceToMeasures`), edge cases incomplete/rest/nested-warn (Task 3 warns + Task 5), testing incl. regression (Tasks 1,4,5,6). All spec sections covered.
- **Type consistency:** event keys `mult/div/meidur/dots/beats/pnames/accids/octs/rest`; unit keys `kind/ev/num/numbase/members/beats/complete`; record keys `str/md/rest/beatPos/tuplet` — used identically across `parseDur`→`eventsOf`→`groupEvents`→`tupletMEI`→`voiceToMeasures`→`beamMeasure`. `num=div`, `numbase=mult` consistent.
- **Placeholder scan:** no TBD/TODO; every code step shows complete SC/Python. The one prose step (Task 3 Step 4) gives the exact before/after edits including the extra closing brace.
