# Panola meter-aware note splitting engine (SP2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `PanolaMeter` (metric boundary hierarchy) and `PanolaMeterSplitter` (meter-aware note splitting) in the Panola quark, per `docs/superpowers/specs/2026-07-07-panola-meter-splitting-design.md`.

**Architecture:** Two new standalone SuperCollider classes in the Panola quark, consuming SP1's `PanolaDurationSpeller` + `PanolaRational`. `PanolaMeter` builds a strength-ranked boundary list for simple/compound/additive meters. `PanolaMeterSplitter.split` splits a note at the boundaries stronger than its onset (the onset-strength rule), spells each piece, and ties them — then later tasks layer tuplet-container handling, fallbacks, and an optimization pass (avoid dots across strong boundaries, merge needless ties). Notation-only, exact by default. Phased: a correct splitter first (Tasks 1–4), then the optimization pass (Task 5), then docs (Task 6). A full candidate+cost model is intentionally omitted — the onset-strength rule already forces a split at every boundary stronger than the note's onset, leaving no optional split a cost model would take.

**Tech Stack:** SuperCollider (sclang); Python pytest driving headless sclang (same harness as `tools/panola_duration/`); whelk → schelp via the quark's `gendoc.bat`.

---

## Repositories & branches

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (git branch **master**; bash path `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola`). The two new class files + regenerated HelpSource commit here.
- **MusicScene repo** — `D:\Projects\MusicScene` (git branch **feature/panola-duration-spelling**; the spec is committed there). The pytest tests commit here.

Editing a `.sc` recompiles the class library on the next `sclang` run (a syntax/whelk-comment error surfaces as the test failing to construct the class, or a 120s hang because a runtime error skips `0.exit`). sclang path: `C:\Program Files\SuperCollider-3.14.1\sclang.exe`. Stuck sclang → PowerShell `Get-Process sclang | Stop-Process -Force`. `^` inside a `.do`/`while` closure is a non-local return from the method (used intentionally). All arithmetic/comparison is on `PanolaRational` (never floats), except the deliberate quantize/tolerance and the NaN/Inf guard.

## File structure

- **Create** `…/panola/Classes/PanolaMeter.sc` — the metric boundary hierarchy (Task 1).
- **Create** `…/panola/Classes/PanolaMeterSplitter.sc` — the splitter, built up across Tasks 2–6.
- **Regenerate** `…/panola/HelpSource/Classes/*.schelp` via `gendoc.bat` (Task 7).
- **Create** `D:\Projects\MusicScene\tools\panola_duration\test_meter_splitting.py` — all SP2a tests, grown per task.

Whelk doc comments on every member of both classes are added in **Task 7** (a final docs pass, matching SP1). Do NOT add whelk `/* … */` blocks in Tasks 1–6.

---

### Task 1: PanolaMeter — metric boundary hierarchy

**Files:**
- Create: `…/panola/Classes/PanolaMeter.sc`
- Create/Test: `D:\Projects\MusicScene\tools\panola_duration\test_meter_splitting.py`

- [ ] **Step 1: Write the failing test** (create the test file)

```python
"""SP2a meter-splitting tests for the Panola quark (PanolaMeter + PanolaMeterSplitter).
Pure sclang value computation -- no server. Run:
  py -m pytest tools/panola_duration/test_meter_splitting.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script)
        path = f.name
    try:
        return subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)


# format a meter's boundaries as "off@strength" tokens joined by ; (offsets as num/den)
METER_SCRIPT = r'''(
var fmt = { |m| m.boundaries.collect({ |b| b[\offsetQL].asString ++ "@" ++ b[\strength] }).join(";") };
("M44:" ++ fmt.(PanolaMeter(4, 4))).postln;
("M34:" ++ fmt.(PanolaMeter(3, 4))).postln;
("M68:" ++ fmt.(PanolaMeter(6, 8))).postln;
("M78:" ++ fmt.(PanolaMeter(7, 8, [2,2,3]))).postln;
("LEN44:" ++ PanolaMeter(4,4).measureLengthQL.asString).postln;
("LEN68:" ++ PanolaMeter(6,8).measureLengthQL.asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_meter_boundaries():
    r = _run(METER_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "LEN44:4/1" in r.stdout, r.stdout[-1500:]
    assert "LEN68:3/1" in r.stdout, r.stdout[-1500:]
    # 4/4: 0@100 0.5@30 1@60 1.5@30 2@80 2.5@30 3@60 3.5@30 4@100
    assert "M44:0/1@100;1/2@30;1/1@60;3/2@30;2/1@80;5/2@30;3/1@60;7/2@30;4/1@100" in r.stdout, r.stdout[-1500:]
    # 3/4: 0@100 1@60 2@60 3@100 (+ subdivisions 0.5,1.5,2.5 @30)
    assert "M34:0/1@100;1/2@30;1/1@60;3/2@30;2/1@60;5/2@30;3/1@100" in r.stdout, r.stdout[-1500:]
    # 6/8: 0@100 0.5@40 1@40 1.5@70 2@40 2.5@40 3@100
    assert "M68:0/1@100;1/2@40;1/1@40;3/2@70;2/1@40;5/2@40;3/1@100" in r.stdout, r.stdout[-1500:]
    # 7/8 [2,2,3]: 0@100 0.5@40 1@75 1.5@40 2@75 2.5@40 3@40 3.5@100
    assert "M78:0/1@100;1/2@40;1/1@75;3/2@40;2/1@75;5/2@40;3/1@40;7/2@100" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q`
Expected: FAIL — `PanolaMeter` does not exist.

- [ ] **Step 3: Implement `PanolaMeter`** (create the file)

```supercollider
// Metric boundary hierarchy for a time signature. boundaries is a strength-ranked list of
// ( offsetQL: PanolaRational, strength: Integer, label: String ), sorted by offset, one per offset
// (max strength kept). Simple / compound / additive meters. See the SP2a design doc.
PanolaMeter {
	var <numerator, <denominator, <groups, <measureLengthQL, <boundaries;

	*new { | numerator, denominator, groups | ^super.new.pr_init(numerator, denominator, groups); }

	*isCompound { | num, den | ^((num % 3) == 0) and: { num > 3 } and: { #[8, 16].includes(den) }; }

	pr_init { | num, den, grps |
		numerator = num; denominator = den; groups = grps;
		measureLengthQL = PanolaRational(num * 4, den);
		boundaries = this.pr_build;
	}

	pr_unit { ^PanolaRational(4, denominator); }              // QL of one denominator-unit

	pr_build {
		var bs = List.new, unit = this.pr_unit;
		bs.add(( offsetQL: PanolaRational(0, 1),   strength: 100, label: "measure-start" ));
		bs.add(( offsetQL: measureLengthQL,        strength: 100, label: "measure-end" ));
		if (groups.notNil) { this.pr_additive(bs, unit) } {
			if (PanolaMeter.isCompound(numerator, denominator)) { this.pr_compound(bs, unit) }
			{ this.pr_simple(bs, unit) };
		};
		^this.pr_sortUnique(bs);
	}

	pr_simple { | bs, unit |
		var half = unit / PanolaRational(2, 1), nHalf;
		(1..(numerator - 1)).do({ | bi |
			var str = (numerator == 4).if({ (bi == 2).if({ 80 }, { 60 }) },
				{ (numerator == 2).if({ 70 }, { 60 }) });
			bs.add(( offsetQL: unit * PanolaRational(bi, 1), strength: str, label: "beat" ));
		});
		nHalf = (measureLengthQL / half).asInteger;
		(1..(nHalf - 1)).do({ | i |
			bs.add(( offsetQL: half * PanolaRational(i, 1), strength: 30, label: "subdivision" ));
		});
	}

	pr_compound { | bs, unit |
		var beatLen = unit * PanolaRational(3, 1), beatCount = numerator div: 3, nUnit;
		(1..(beatCount - 1)).do({ | bi |
			bs.add(( offsetQL: beatLen * PanolaRational(bi, 1), strength: 70, label: "compound-beat" ));
		});
		nUnit = (measureLengthQL / unit).asInteger;
		(1..(nUnit - 1)).do({ | i |
			bs.add(( offsetQL: unit * PanolaRational(i, 1), strength: 40, label: "eighth-subbeat" ));
		});
	}

	pr_additive { | bs, unit |
		var offset = PanolaRational(0, 1);
		groups.do({ | g, gi |
			var groupStart = offset;
			offset = offset + (unit * PanolaRational(g, 1));
			if (gi < (groups.size - 1)) {
				bs.add(( offsetQL: offset, strength: 75, label: "additive-group" ));
			};
			(1..(g - 1)).do({ | j |
				bs.add(( offsetQL: groupStart + (unit * PanolaRational(j, 1)), strength: 40, label: "subdivision" ));
			});
		});
	}

	pr_sortUnique { | bs |
		var dict = Dictionary.new;
		bs.do({ | b |
			var key = b[\offsetQL].asString, ex = dict[key];
			if (ex.isNil or: { b[\strength] > ex[\strength] }) { dict[key] = b };
		});
		^dict.values.sort({ | a, c | a[\offsetQL] < c[\offsetQL] });
	}
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMeter.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): PanolaMeter metric boundary hierarchy (simple/compound/additive)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_meter_splitting.py
git commit -m "test(panola): PanolaMeter boundaries for 4/4, 3/4, 6/8, 7/8[2,2,3]

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: PanolaMeterSplitter — onset-strength split + spell + tie

**Files:**
- Create: `…/panola/Classes/PanolaMeterSplitter.sc`
- Test: `tools/panola_duration/test_meter_splitting.py` (add `test_basic_split`)

- [ ] **Step 1: Add the failing test**

```python
# format a split as "type.dots/tie" components joined by + ; tie = F(from) N(to) B(both) -(none)
SPLIT_FMT = r'''
var fmtComp = { |c|
    var sp = c[\spelling], tie;
    tie = (c[\tieFromPrevious] and: { c[\tieToNext] }).if({ "B" },
        { c[\tieFromPrevious].if({ "F" }, { c[\tieToNext].if({ "N" }, { "-" }) }) });
    sp[\inexpressible].if({ "INEXPR" }, {
        sp[\components].collect({ |x|
            var t = x[\tuplets];
            x[\type].asString ++ "." ++ x[\dots] ++ (t.isEmpty.if({ "" }, { "[" ++ t[0][\actual] ++ ":" ++ t[0][\normal] ++ "]" }));
        }).join(",") ++ "/" ++ tie;
    });
};
var fmt = { |comps| comps.collect(fmtComp).join("+") };
var ev = { |onN, onD, durN, durD, isRest = false|
    ( onsetQL: PanolaRational(onN, onD), durationQL: PanolaRational(durN, durD), isRest: isRest );
};
'''

BASIC_SPLIT_SCRIPT = r'''(''' + SPLIT_FMT + r'''
("E1:"    ++ fmt.(PanolaMeterSplitter.split(ev.(3,2, 1,1), PanolaMeter(4,4)))).postln;   // 1.5,1.0 -> e+e
("HALF:"  ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 2,1), PanolaMeter(4,4)))).postln;   // 0,2   -> half
("QQ:"    ++ fmt.(PanolaMeterSplitter.split(ev.(1,1, 2,1), PanolaMeter(4,4)))).postln;   // 1,2   -> q+q
("DQ:"    ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 3,2), PanolaMeter(4,4)))).postln;   // 0,1.5 -> dotted q
("E2:"    ++ fmt.(PanolaMeterSplitter.split(ev.(1,1, 1,1), PanolaMeter(6,8)))).postln;   // 1,1   -> e+e (6/8)
("E3:"    ++ fmt.(PanolaMeterSplitter.split(ev.(1,2, 2,1), PanolaMeter(7,8,[2,2,3])))).postln; // 0.5,2 -> e+q+e
("REST:"  ++ fmt.(PanolaMeterSplitter.split(ev.(3,2, 1,1, true), PanolaMeter(4,4)))).postln;   // rest, no ties
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_basic_split():
    r = _run(BASIC_SPLIT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "E1:eighth.0/N+eighth.0/F" in r.stdout, r.stdout[-1500:]      # crosses 2.0 midpoint
    assert "HALF:half.0/-" in r.stdout, r.stdout[-1500:]                 # single half note (onset 100)
    assert "QQ:quarter.0/N+quarter.0/F" in r.stdout, r.stdout[-1500:]    # breaks at 2.0 (80 > 60)
    assert "DQ:quarter.1/-" in r.stdout, r.stdout[-1500:]                # dotted quarter, un-split
    assert "E2:eighth.0/N+eighth.0/F" in r.stdout, r.stdout[-1500:]      # crosses 1.5 compound beat
    assert "E3:eighth.0/N+quarter.0/B+eighth.0/F" in r.stdout, r.stdout[-1500:]  # crosses 1.0 and 2.0 groups
    assert "REST:eighth.0/-+eighth.0/-" in r.stdout, r.stdout[-1500:]    # rest split, NO ties
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py::test_basic_split -q`
Expected: FAIL — `PanolaMeterSplitter` does not exist.

- [ ] **Step 3: Create `PanolaMeterSplitter`** (create the file)

```supercollider
// Meter-aware note splitting: split a note at the metrical boundaries stronger than its onset (the
// onset-strength rule), spell each piece with PanolaDurationSpeller, and tie them. Later tasks add
// tuplet-container handling, fallbacks, and an optimization pass. See the SP2a design doc.
// Notation-only, exact by default.
PanolaMeterSplitter {
	var <options;

	*new { | options | ^super.new.pr_init(options); }
	pr_init { | opts |
		options = this.class.defaultOptions;
		opts.notNil.if({ opts.keysValuesDo({ | k, v | options[k] = v }) });
	}

	*defaultOptions {
		^( splitAtMeasureBoundaries: true, splitAtBeatBoundaries: true,
			splitAtStrongSubBeatBoundaries: false, splitAtTupletBoundaries: true,
			allowSyncopation: false, maxSplitPieces: 12, greedyMinBoundaryStrength: 60,
			dotBoundaryThreshold: 80, tieCost: 10, dotCost: 2, tupletCost: 20,
			hiddenBoundaryCostFactor: 1.0, syncopationPenalty: 40,
			quantizeMode: \none, quantizeGrid: PanolaRational(1, 512), quantizeTolerance: 1e-5,
			spellingOptions: nil );
	}

	*split { | noteEvent, meter, options | ^this.new(options).split(noteEvent, meter); }

	split { | noteEvent, meter |
		var ev = this.pr_prepareInput(noteEvent);
		^this.pr_splitBasic(ev, meter);        // Task 5 will route tuplet-context / candidates here
	}

	pr_prepareInput { | ev |
		var onset = ev[\onsetQL] ? PanolaRational(0, 1);
		var e = ( onsetQL: onset, durationQL: ev[\durationQL], isRest: ev[\isRest] ? false,
			tupletContext: ev[\tupletContext] );
		if (options[\quantizeMode] == \grid) {
			var g = options[\quantizeGrid], tol = options[\quantizeTolerance];
			var snap = { | q | var n = (q / g).asFloat.round.asInteger, near = g * PanolaRational(n, 1);
				((near - q).abs.asFloat <= tol).if({ near }, { q }) };
			var s = snap.(onset), en = snap.(onset + ev[\durationQL]);
			e = ( onsetQL: s, durationQL: en - s, isRest: e[\isRest], tupletContext: e[\tupletContext] );
		};
		^e;
	}

	pr_onsetStrength { | onset, boundaries |
		var b = boundaries.detect({ | x | x[\offsetQL] == onset });
		^b.notNil.if({ b[\strength] }, { 0 });
	}

	pr_policyAllows { | label |
		^case
			{ #["measure-start", "measure-end"].includesEqual(label) } { options[\splitAtMeasureBoundaries] }
			{ #["beat", "compound-beat", "additive-group"].includesEqual(label) } { options[\splitAtBeatBoundaries] }
			{ #["subdivision", "eighth-subbeat"].includesEqual(label) } { options[\splitAtStrongSubBeatBoundaries] }
			{ label == "tuplet-boundary" } { options[\splitAtTupletBoundaries] }
			{ true } { false };
	}

	// split points for the span, using the onset-strength rule
	// onsetBoundaries (default boundaries): the set the onset strength is measured against. For a
	// tuplet-contained note this is the METER only, so a mid-tuplet onset reads strength 0 and the
	// tuplet grid lines (50 > 0) split it; passing the merged set would make the onset read 50 and
	// block the split (50 > 50 is false).
	pr_splitPoints { | start, end, boundaries, onsetBoundaries |
		var onsetStr = this.pr_onsetStrength(start, onsetBoundaries ? boundaries), pts = [start];
		boundaries.do({ | b |
			if ((start < b[\offsetQL]) and: { b[\offsetQL] < end }) {
				var mandatory = (b[\strength] > onsetStr) and: { this.pr_policyAllows(b[\label]) };
				if (mandatory or: { b[\strength] >= 90 }) { pts = pts.add(b[\offsetQL]) };
			};
		});
		pts = pts.add(end);
		^this.pr_sortUniqueRationals(pts);
	}

	pr_sortUniqueRationals { | arr |
		var dict = Dictionary.new;
		arr.do({ | r | dict[r.asString] = r });
		^dict.values.sort({ | a, b | a < b });
	}

	pr_spellAndTie { | pts, ev |
		var comps = [], speller = PanolaDurationSpeller.new(options[\spellingOptions]), n = pts.size - 1;
		n.do({ | i |
			var s = pts[i], d = pts[i + 1] - pts[i];
			comps = comps.add((
				startQL: s, durationQL: d, spelling: speller.spell(d), isRest: ev[\isRest],
				tieFromPrevious: (i > 0) and: { ev[\isRest].not },
				tieToNext: (i < (n - 1)) and: { ev[\isRest].not }
			));
		});
		^comps;
	}

	pr_splitBasic { | ev, meter |
		var start = ev[\onsetQL], end = ev[\onsetQL] + ev[\durationQL];
		^this.pr_spellAndTie(this.pr_splitPoints(start, end, meter.boundaries), ev);
	}
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMeterSplitter.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): PanolaMeterSplitter onset-strength split + spell + tie

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_meter_splitting.py
git commit -m "test(panola): meter splitter basic onset-strength split (Ex1-3 + anti-over-split)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Tuplet-contained splitting

**Files:**
- Modify: `…/panola/Classes/PanolaMeterSplitter.sc` (route tuplet-context in `split`; add tuplet helpers)
- Test: `tools/panola_duration/test_meter_splitting.py` (add `test_tuplet_split`)

- [ ] **Step 1: Add the failing test**

```python
TUPLET_SPLIT_SCRIPT = r'''(''' + SPLIT_FMT + r'''
var tev = { |onN, onD, durN, durD, tcStartN, tcStartD, tcTotN, tcTotD, act, nrm|
    ( onsetQL: PanolaRational(onN, onD), durationQL: PanolaRational(durN, durD), isRest: false,
      tupletContext: ( startQL: PanolaRational(tcStartN, tcStartD), totalDurationQL: PanolaRational(tcTotN, tcTotD),
                       numberNotesActual: act, numberNotesNormal: nrm ) );
};
// triplet-eighth grid over 1.0..2.0 (3:2). note onset 4/3, dur 2/3 -> two tied triplet eighths.
("T4:" ++ fmt.(PanolaMeterSplitter.split(tev.(4,3, 2,3, 1,1, 1,1, 3,2), PanolaMeter(4,4)))).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplet_split():
    r = _run(TUPLET_SPLIT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "T4:eighth.0[3:2]/N+eighth.0[3:2]/F" in r.stdout, r.stdout[-1500:]  # two tied triplet eighths
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py::test_tuplet_split -q`
Expected: FAIL — a tuplet-context note currently goes through the basic (non-tuplet) split, so it isn't split at the tuplet grid → single `quarter[3:2]`, not two tied triplet eighths.

- [ ] **Step 3: Route tuplet-context and add the tuplet helpers**

In `PanolaMeterSplitter.sc`, replace the `split` method with:

```supercollider
	split { | noteEvent, meter |
		var ev = this.pr_prepareInput(noteEvent);
		^(ev[\tupletContext].notNil).if(
			{ this.pr_splitTupletContained(ev, meter) },
			{ this.pr_splitBasic(ev, meter) });
	}
```

and add these methods:

```supercollider
	pr_tupletBoundaries { | tc |
		var bs = [], start = tc[\startQL], total = tc[\totalDurationQL], act = tc[\numberNotesActual];
		var unit = total / PanolaRational(act, 1);
		(0..act).do({ | i |
			var off = start + (unit * PanolaRational(i, 1));
			var str = ((i == 0) or: { i == act }).if({ 90 }, { 50 });
			bs = bs.add(( offsetQL: off, strength: str, label: "tuplet-boundary" ));
		});
		^bs;
	}

	pr_splitTupletContained { | ev, meter |
		var start = ev[\onsetQL], end = ev[\onsetQL] + ev[\durationQL];
		var merged = meter.boundaries ++ this.pr_tupletBoundaries(ev[\tupletContext]);
		// split on the merged grid, but measure onset strength against the METER only (a mid-tuplet
		// onset is metrically weak = 0, so the tuplet grid lines split it -> tied triplet members).
		^this.pr_spellAndTie(this.pr_splitPoints(start, end, merged, meter.boundaries), ev);
	}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMeterSplitter.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): tuplet-contained splitting (split at the tuplet grid + meter)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_meter_splitting.py
git commit -m "test(panola): triplet crossing a beat -> two tied triplet eighths

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Fallbacks (greedy + smallest-grid) and sum-exactness

**Files:**
- Modify: `…/panola/Classes/PanolaMeterSplitter.sc` (add fallbacks; call them when a piece is inexpressible)
- Test: `tools/panola_duration/test_meter_splitting.py` (add `test_fallback_and_sum`)

- [ ] **Step 1: Add the failing test**

```python
FALLBACK_SCRIPT = r'''(''' + SPLIT_FMT + r'''
var sumOK = { |comps, dn, dd|
    comps.inject(PanolaRational(0,1), { |a, c| a + c[\durationQL] }) == PanolaRational(dn, dd);
};
// (SC requires all `var` before any statement) 1/17 is inexpressible in 4/4 -> drives the fallback
var one17 = PanolaMeterSplitter.split(ev.(0,1, 1,17), PanolaMeter(4,4));
// sum-exactness across the earlier examples
("SUM1:" ++ sumOK.(PanolaMeterSplitter.split(ev.(3,2, 1,1), PanolaMeter(4,4)), 1, 1).asString).postln;
("SUM3:" ++ sumOK.(PanolaMeterSplitter.split(ev.(1,2, 2,1), PanolaMeter(7,8,[2,2,3])), 2, 1).asString).postln;
// an off-grid duration must not crash (5/7 actually spells as a 7:10 septuplet, so it stays on the
// basic path; kept as a no-crash smoke check)
("OFFGRID:" ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 5,7), PanolaMeter(4,4)))).postln;
("ONE17SUM:" ++ (one17.inject(PanolaRational(0,1), { |a, c| a + c[\durationQL] }) == PanolaRational(1,17)).asString).postln;
("ONE17MANY:" ++ (one17.size > 1).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_fallback_and_sum():
    r = _run(FALLBACK_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "SUM1:true" in r.stdout, r.stdout[-1500:]     # components sum exactly to the input
    assert "SUM3:true" in r.stdout, r.stdout[-1500:]
    assert "OFFGRID:" in r.stdout, r.stdout[-1500:]      # produced a result, did not crash/hang
    assert "ONE17SUM:true" in r.stdout, r.stdout[-1500:]  # fallback result sums exactly to 1/17
    assert "ONE17MANY:true" in r.stdout, r.stdout[-1500:] # smallest-grid fallback -> many tied pieces
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py::test_fallback_and_sum -q`
Expected: FAIL on the `ONE17*` assertions — a `1/17`-QL note is inexpressible in 4/4 (needs a 17:1 tuplet beyond `maxTupletActual`), and the current `pr_splitBasic` emits a single inexpressible component (`ONE17MANY:false`) rather than falling back to the smallest grid. (`SUM1`/`SUM3`/`OFFGRID` already pass — `5/7` spells as a 7:10 septuplet on the basic path and does not exercise the fallback.)

- [ ] **Step 3: Add greedy + smallest-grid fallbacks, and use them when a basic split has an inexpressible piece**

In `PanolaMeterSplitter.sc`, replace `pr_splitBasic` with:

```supercollider
	pr_splitBasic { | ev, meter |
		var start = ev[\onsetQL], end = ev[\onsetQL] + ev[\durationQL];
		var comps = this.pr_spellAndTie(this.pr_splitPoints(start, end, meter.boundaries), ev);
		^this.pr_allSpellable(comps).if({ comps }, { this.pr_fallback(ev, meter) });
	}

	pr_allSpellable { | comps | ^comps.every({ | c | c[\spelling][\inexpressible].not }); }

	pr_fallback { | ev, meter |
		var comps = this.pr_fallbackAggressive(ev, meter);
		^this.pr_allSpellable(comps).if({ comps }, { this.pr_splitAtSmallestGrid(ev) });
	}

	pr_fallbackAggressive { | ev, meter |
		var start = ev[\onsetQL], end = ev[\onsetQL] + ev[\durationQL], minS = options[\greedyMinBoundaryStrength];
		var pts = [start];
		meter.boundaries.do({ | b |
			if ((start < b[\offsetQL]) and: { b[\offsetQL] < end } and: { b[\strength] >= minS }) {
				pts = pts.add(b[\offsetQL]);
			};
		});
		pts = pts.add(end);
		^this.pr_spellAndTie(this.pr_sortUniqueRationals(pts), ev);
	}

	pr_splitAtSmallestGrid { | ev |
		var grid = this.pr_minNoteTypeQL, start = ev[\onsetQL], end = ev[\onsetQL] + ev[\durationQL];
		var pts = [start], cur = start + grid;
		while { cur < end } { pts = pts.add(cur); cur = cur + grid };
		pts = pts.add(end);
		^this.pr_spellAndTie(this.pr_sortUniqueRationals(pts), ev);
	}

	pr_minNoteTypeQL {
		var so = options[\spellingOptions], name = (so.notNil and: { so[\minNoteType].notNil }).if(
			{ so[\minNoteType] }, { '2048th' });
		^PanolaDurationSpeller.new.pr_qlOf(name);
	}
```

Note: `pr_qlOf` is an existing `PanolaDurationSpeller` helper (returns a note type's quarterLength). If it is private and inaccessible, add a public `*noteTypeQL(name)` classmethod to `PanolaDurationSpeller` returning `PanolaRational(entry[2][0], entry[2][1])`, and call that instead — but prefer reusing the existing helper.

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMeterSplitter.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): greedy + smallest-grid fallbacks for unspellable pieces

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_meter_splitting.py
git commit -m "test(panola): meter split sum-exactness + off-grid no-crash fallback

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Optimization pass (merge + avoid dots across strong boundaries)

**Files:**
- Modify: `…/panola/Classes/PanolaMeterSplitter.sc` (add `pr_optimize`; call it at the end of `split`)
- Test: `tools/panola_duration/test_meter_splitting.py` (add `test_optimize`)

- [ ] **Step 1: Add the failing test**

```python
OPT_SCRIPT = r'''(''' + SPLIT_FMT + r'''
// a dotted quarter that hides a strong boundary (>= dotBoundaryThreshold 80) is re-split; one that
// hides only a weak boundary is kept. onset 1.0 dur 1.5 in 4/4: dotted quarter spans beat-3 midpoint?
// span 1.0-2.5 crosses 2.0 (strength 80) -> the mandatory rule already splits at 2.0, so this yields
// quarter+eighth; assert that (no dotted value hiding the 80-boundary survives).
("NODOT:" ++ fmt.(PanolaMeterSplitter.split(ev.(1,1, 3,2), PanolaMeter(4,4)))).postln;   // -> quarter+eighth
// onset 0.0 dur 1.5: dotted quarter hides only beat-1 (60 < 80) -> kept as a single dotted quarter
("KEEPDOT:" ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 3,2), PanolaMeter(4,4)))).postln; // -> dotted quarter
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_optimize():
    r = _run(OPT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "NODOT:quarter.0/N+eighth.0/F" in r.stdout, r.stdout[-1500:]  # dot across the 80-boundary avoided
    assert "KEEPDOT:quarter.1/-" in r.stdout, r.stdout[-1500:]           # dot over a weak boundary kept
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py::test_optimize -q`
Expected: The mandatory rule may already produce `NODOT` (2.0 is a mandatory split for onset 1.0), so `NODOT` can pass at Phase-1; `KEEPDOT` should also already pass. This task adds the explicit `avoidDotsAcrossStrongBoundaries` + `mergeAdjacentPiecesIfSafe` passes so the behavior is guaranteed and pinned.

- [ ] **Step 3: Add the optimization pass**

In `PanolaMeterSplitter.sc`, update `split` to call the optimizer, and add the methods:

```supercollider
	split { | noteEvent, meter |
		var ev = this.pr_prepareInput(noteEvent);
		var comps = (ev[\tupletContext].notNil).if(
			{ this.pr_splitTupletContained(ev, meter) },
			{ this.pr_splitBasic(ev, meter) });
		^this.pr_optimize(comps, ev, meter);
	}

	pr_optimize { | comps, ev, meter |
		comps = this.pr_avoidDotsAcrossStrong(comps, ev, meter);
		comps = this.pr_mergeIfSafe(comps, ev, meter);
		^comps;
	}

	// re-split a component whose (single) dotted spelling hides a boundary >= dotBoundaryThreshold
	pr_avoidDotsAcrossStrong { | comps, ev, meter |
		var out = [];
		comps.do({ | c |
			var sp = c[\spelling], dotted = (sp[\inexpressible].not) and: { sp[\components].size == 1 }
				and: { sp[\components][0][\dots] > 0 };
			var cStart = c[\startQL], cEnd = c[\startQL] + c[\durationQL];
			var hidesStrong = meter.boundaries.any({ | b |
				(cStart < b[\offsetQL]) and: { b[\offsetQL] < cEnd } and: { b[\strength] >= options[\dotBoundaryThreshold] } });
			if (dotted and: { hidesStrong }) {
				// split this piece as its own note at the meter boundaries and inherit c's tie flags
				var sub = this.pr_splitPoints(cStart, cEnd, meter.boundaries);
				var subComps = this.pr_spellAndTie(sub, ev);
				// fix outer tie flags: first inherits tieFromPrevious, last inherits tieToNext
				subComps = subComps.collect({ | sc, i |
					var e = sc.copy;
					if (ev[\isRest].not) {
						e[\tieFromPrevious] = (i > 0).if({ true }, { c[\tieFromPrevious] });
						e[\tieToNext] = (i < (subComps.size - 1)).if({ true }, { c[\tieToNext] });
					};
					e;
				});
				out = out ++ subComps;
			} {
				out = out.add(c);
			};
		});
		^out;
	}

	// merge two adjacent pieces when the merged span hides no strong boundary and spells cleanly
	pr_mergeIfSafe { | comps, ev, meter |
		var out = [], i = 0, speller = PanolaDurationSpeller.new(options[\spellingOptions]);
		while { i < comps.size } {
			var cur = comps[i], merged = false;
			if ((i + 1) < comps.size) {
				var nxt = comps[i + 1];
				var mStart = cur[\startQL], mEnd = nxt[\startQL] + nxt[\durationQL], mDur = mEnd - mStart;
				// reference the NOTE's true onset (not mStart): merge must be the exact inverse of split,
				// so it never recombines across a boundary the split forced. Using mStart would let a
				// middle fragment (starting on a strong boundary) legalize a merge that hides that boundary.
				var mOnsetStr = this.pr_onsetStrength(ev[\onsetQL], meter.boundaries);
				var hidesStrong = meter.boundaries.any({ | b |
					(mStart < b[\offsetQL]) and: { b[\offsetQL] < mEnd } and: { b[\strength] > mOnsetStr } });
				var sp = speller.spell(mDur);
				if (hidesStrong.not and: { sp[\inexpressible].not } and: { sp[\components].size == 1 }) {
					out = out.add(( startQL: mStart, durationQL: mDur, spelling: sp, isRest: ev[\isRest],
						tieFromPrevious: cur[\tieFromPrevious], tieToNext: nxt[\tieToNext] ));
					i = i + 2; merged = true;
				};
			};
			if (merged.not) { out = out.add(cur); i = i + 1 };
		};
		^out;
	}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q`
Expected: PASS (5 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMeterSplitter.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): optimization pass (avoid dots across strong boundaries; merge-if-safe)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_meter_splitting.py
git commit -m "test(panola): dots avoided across strong boundaries, kept over weak ones

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Whelk docs (every member) + regenerate HelpSource with gendoc.bat

Document **every** member (var/classmethod/method) of `PanolaMeter.sc` and `PanolaMeterSplitter.sc` in the PanolaMEI house style (`/* [general] */` + `[classmethod.x]`/`[method.x]` blocks with `description`/`.args`/`.returns` `what =`), using only plain `strong::`/`teletype::`/`link::` prose (never `## … || …`). Then regenerate all schelp with the quark's `gendoc.bat`. Study `Classes/PanolaMEI.sc` for the exact format.

**Files:**
- Modify: `…/panola/Classes/PanolaMeter.sc`, `…/panola/Classes/PanolaMeterSplitter.sc`
- Regenerate (via gendoc.bat): all `…/panola/HelpSource/Classes/*.schelp`

- [ ] **Step 1: Document `PanolaMeter.sc`.** Insert this `[general]` before `PanolaMeter {`, and a block above every member.

```supercollider
/*
[general]
title = "PanolaMeter"
summary = "the metric boundary hierarchy of a time signature"
categories = "Notation, Utils"
related = "Classes/PanolaMeterSplitter, Classes/PanolaDurationSpeller"
description = '''
PanolaMeter turns a time signature into a strength-ranked list of metric boundaries (each an offset in
quarterLength with an integer strength and a label), used by link::Classes/PanolaMeterSplitter:: to decide
where a note must break to respect the meter. Stronger boundaries (measure 100, the 4/4 half-measure 80,
compound beats 70, additive groups 75, ordinary beats 60, subdivisions 30-40) matter more. It handles
simple, compound (teletype::6/8:: teletype::9/8:: teletype::12/8::), and additive meters
(teletype::PanolaMeter(7, 8, [2,2,3])::). All offsets are exact link::Classes/PanolaRational::.
'''
*/
```

Members to document (expand each into the block format): `numerator`, `denominator`, `groups`,
`measureLengthQL`, `boundaries` (vars); `*new(numerator, denominator, groups)` — "build a meter; groups
(Array of denominator-unit counts) is only for additive meters"; `*isCompound(num, den)` — "whether a
meter is compound (num divisible by 3, > 3, denominator 8 or 16)"; and the private helpers `pr_init`,
`pr_unit` ("the quarterLength of one denominator-unit"), `pr_build`, `pr_simple`, `pr_compound`,
`pr_additive`, `pr_sortUnique` — one line each on what they build/return.

- [ ] **Step 2: Document `PanolaMeterSplitter.sc`.** Insert this `[general]` before `PanolaMeterSplitter {`, and a block above every member.

```supercollider
/*
[general]
title = "PanolaMeterSplitter"
summary = "split a note into tied, spelled components that respect the meter"
categories = "Notation, Utils"
related = "Classes/PanolaMeter, Classes/PanolaDurationSpeller"
description = '''
PanolaMeterSplitter takes a note (onset + duration in quarterLength, in a link::Classes/PanolaMeter::) and
splits it into tied components that respect the meter: a note may span boundaries no stronger than the one
it starts on, but must break at any stronger interior boundary (the onset-strength rule). Each piece is
spelled with link::Classes/PanolaDurationSpeller:: and the pieces are tied. Tuplet-contained notes split
on the tuplet grid, and an optimization pass avoids dots across strong boundaries and merges needless ties.
Notation-only, exact by default (quantization is opt-in).

code::
PanolaMeterSplitter.split(( onsetQL: PanolaRational(3,2), durationQL: PanolaRational(1,1) ), PanolaMeter(4,4));
// 1.5 + 1.0 in 4/4 -> eighth tied to eighth (it crosses the 2.0 half-measure)
::
'''
*/
```

Members to document: `options` (var); `*new(options)`, `*defaultOptions`, `*split(noteEvent, meter, options)`,
`split(noteEvent, meter)` — the public API (document the `noteEvent`/`options`/return `SplitComponent`
shapes in the prose); and the private helpers `pr_init`, `pr_prepareInput`, `pr_onsetStrength`,
`pr_policyAllows`, `pr_splitPoints` (incl. its `onsetBoundaries` param), `pr_sortUniqueRationals`,
`pr_spellAndTie`, `pr_splitBasic`,
`pr_tupletBoundaries`, `pr_splitTupletContained`, `pr_allSpellable`, `pr_fallback`, `pr_fallbackAggressive`,
`pr_splitAtSmallestGrid`, `pr_minNoteTypeQL`, `pr_optimize`, `pr_avoidDotsAcrossStrong`, `pr_mergeIfSafe` —
one line each describing what it returns/does.

- [ ] **Step 3: Regenerate all Panola schelp with gendoc.bat**

Run it via PowerShell by full path (a bash `cd` + `cmd //c` does not reliably set cmd's working dir):
```powershell
& "C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\gendoc.bat"
```
Expected: prints `Removing old help files...` / `Generating help files...` / `Done.` with no `ERROR`.

- [ ] **Step 4: Verify the new schelp exist and the classes still compile**

```bash
ls "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMeter.schelp" "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMeterSplitter.schelp"
cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q
```
Expected: both schelp listed; pytest **5 passed** (a doc-comment edit must not break compilation).

- [ ] **Step 5: Commit** (Panola quark)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add -A Classes HelpSource
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "docs(panola): whelk docs for PanolaMeter + PanolaMeterSplitter; regen schelp (gendoc)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_meter_splitting.py -q` → **5 passed** (meter boundaries, basic split, tuplet split, fallback/sum, optimize).
- [ ] Regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration tools/panola_mei tools/msscore/test_midi_routing.py -q` → the SP1 duration-speller suite and existing panola_mei / msscore suites are unaffected (SP2a adds new classes only).
- [ ] Spot-check the spec's Part-9 examples in sclang: Ex1 `1.5/1.0` in 4/4 → e+e; Ex2 `1.0/1.0` in 6/8 → e+e; Ex3 `0.5/2.0` in 7/8[2,2,3] → e+q+e; Ex4 triplet `4/3, 2/3` → two tied triplet eighths; the non-split cases (`0/2`→half, `0/1.5`→dotted quarter, `1/2`→q+q).

## Notes for the implementer

- **All offsets/durations are `PanolaRational`.** Never compare with floats; use `PanolaRational` `== < <=`. The only Float touchpoints are the quantize snap (`asFloat.round`) and its tolerance.
- **`^` inside `.do`/`while` is a non-local return** from the method — used in `pr_onsetStrength` etc.
- **`pr_sortUniqueRationals`/`pr_sortUnique`** dedupe by the exact `asString` of the rational, then sort by `PanolaRational <` — do not dedupe by float.
- **Phasing:** Tasks 1–4 produce a correct splitter; Task 5 refines readability (dots/merges) without changing the mandatory split points, so the Task 1–4 example assertions must keep passing after Task 5 (the full-file run at each task's Step 4 is the guard).
- **Whelk docs (Task 7)** must be whelk-safe: plain `strong::`/`teletype::`/`link::` prose, balanced `/* */`, no `## … || …` lines. A malformed block breaks class-library compilation (tests fail to construct the class).
- If `PanolaDurationSpeller.pr_qlOf` is inaccessible from `PanolaMeterSplitter` (private), add a public `*noteTypeQL(name)` classmethod to `PanolaDurationSpeller` and use it in `pr_minNoteTypeQL`.
