# Panola duration spelling engine (SP1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `PanolaRational` (exact rationals) and `PanolaDurationSpeller` (music21-style quarterLength → notation spelling) in the Panola quark, per `docs/superpowers/specs/2026-07-06-panola-duration-spelling-design.md`.

**Architecture:** Two new standalone SuperCollider classes in the Panola quark. `PanolaRational` gives exact rational arithmetic (backed by Float-valued integers to dodge SC's 32-bit Integer overflow). `PanolaDurationSpeller` runs the ordered algorithm (simple → dotted → tuplet → multi-component split → large-tuplet fallback → inexpressible) over rationals, returning a lightweight spelling Event. No changes to existing Panola/PanolaMEI code (that's SP2).

**Tech Stack:** SuperCollider (sclang) for the classes; Python pytest driving headless sclang for tests (same harness style as `tools/msscore/`, `tools/panola_mei/`); whelk → schelp via gendoc.

---

## Repositories & branches

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (git branch **master**; bash path `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola`). The two new class files + regenerated HelpSource commit here.
- **MusicScene repo** — `D:\Projects\MusicScene` (git branch **feature/panola-duration-spelling**, already checked out; the spec is committed there). The pytest tests commit here.

Editing a `.sc` recompiles the class library on the next `sclang` run, so a syntax error surfaces immediately as the test failing to construct the class. Every test script ends with `0.exit;`. sclang path: `C:\Program Files\SuperCollider-3.14.1\sclang.exe`. A stuck sclang can be cleared with PowerShell `Get-Process sclang | Stop-Process -Force`.

## File structure

- **Create** `…/panola/Classes/PanolaRational.sc` — exact rational value type (Task 1).
- **Create** `…/panola/Classes/PanolaDurationSpeller.sc` — the spelling engine, built up across Tasks 2–5.
- **Regenerate** `…/panola/HelpSource/Classes/PanolaRational.schelp` and `PanolaDurationSpeller.schelp` (Task 6).
- **Create** `D:\Projects\MusicScene\tools\panola_duration\test_duration_spelling.py` — all SP1 tests, grown per task.

---

### Task 1: PanolaRational — exact rational arithmetic

**Files:**
- Create: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaRational.sc`
- Create/Test: `D:\Projects\MusicScene\tools\panola_duration\test_duration_spelling.py`

- [ ] **Step 1: Write the failing test** (create `tools\panola_duration\test_duration_spelling.py`)

```python
"""SP1 duration-spelling tests for the Panola quark (PanolaRational + PanolaDurationSpeller).
Pure sclang value computation -- no server. Run:
  py -m pytest tools/panola_duration/test_duration_spelling.py -q   (skips if sclang absent)
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


RATIONAL_SCRIPT = r'''(
("REDUCE:" ++ PanolaRational(4, 8).asString).postln;
("ADD:" ++ (PanolaRational(1,3) + PanolaRational(1,6)).asString).postln;
("SUB:" ++ (PanolaRational(3,4) - PanolaRational(1,4)).asString).postln;
("MUL:" ++ (PanolaRational(1,2) * PanolaRational(2,3)).asString).postln;
("DIV:" ++ (PanolaRational(1,2) / PanolaRational(1,4)).asString).postln;
("EQ:" ++ (PanolaRational(4,8) == PanolaRational(1,2)).asString).postln;
("LT:" ++ (PanolaRational(1,3) < PanolaRational(1,2)).asString).postln;
("NEG:" ++ PanolaRational(-2,4).asString).postln;
("BIG:" ++ (PanolaRational(1,65536) * PanolaRational(1,2)).asString).postln;
("F13:" ++ PanolaRational.fromFloat(1/3).asString).postln;
("F04:" ++ PanolaRational.fromFloat(0.4).asString).postln;
("F01:" ++ PanolaRational.fromFloat(0.1).asString).postln;
("DEC:" ++ PanolaRational.fromDecimalString("0.625").asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_rational():
    r = _run(RATIONAL_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    for expect in ["REDUCE:1/2", "ADD:1/2", "SUB:1/2", "MUL:1/3", "DIV:2/1", "EQ:true",
                   "LT:true", "NEG:-1/2", "BIG:1/131072", "F13:1/3", "F04:2/5", "F01:1/10",
                   "DEC:5/8"]:
        assert expect in r.stdout, f"missing {expect}\n{r.stdout[-1500:]}"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: FAIL — `PanolaRational` does not exist yet (sclang errors, markers missing).

- [ ] **Step 3: Implement `PanolaRational`** (create the file with exactly this content)

```supercollider
// Exact rational number for Panola duration spelling. num/den are stored as Float-valued
// integers (doubles are exact to 2^53, far above any intermediate here) so the arithmetic
// never overflows SuperCollider's 32-bit Integer. Always reduced; sign kept in num; den > 0.
PanolaRational {
	var <num, <den;

	*new { | num = 0, den = 1 |
		^super.new.pr_init(num.asFloat, den.asFloat);
	}

	*fromInteger { | n | ^this.new(n.asFloat, 1.0); }

	*pr_gcd { | a, b |
		a = a.abs; b = b.abs;
		while { b > 0.5 } { var t = b; b = a % b; a = t };
		^a;
	}

	pr_init { | n, d |
		var g;
		if (d == 0) { Error("PanolaRational: zero denominator").throw };
		if (d < 0) { n = n.neg; d = d.neg };
		g = PanolaRational.pr_gcd(n, d);
		if (g < 0.5) { g = 1.0 };
		num = n / g;
		den = d / g;
	}

	*pr_coerce { | x |
		^x.isKindOf(PanolaRational).if({ x }, {
			x.isInteger.if({ this.new(x, 1) }, { this.fromFloat(x.asFloat) })
		});
	}

	// exact dyadic fraction of a finite double, then limit the denominator
	*fromFloat { | x, maxDenom = 65536 |
		var n, d = 1.0, r;
		// SC 3.14.1's Float has no isInf/isInfinite (only isNaN); test infinity directly.
		if (x.isKindOf(Float) and: { x.isNaN or: { (x == inf) or: { x == inf.neg } } }) {
			Error("PanolaRational.fromFloat: non-finite").throw;
		};
		n = x.asFloat;
		while { (n.frac != 0) and: { d < 1.15e18 } } { n = n * 2; d = d * 2 };
		r = this.new(n, d);
		^(r.den > maxDenom).if({ r.limitDenominator(maxDenom) }, { r });
	}

	*fromDecimalString { | s |
		var neg = (s[0] == $-), str = neg.if({ s.copyRange(1, s.size - 1) }, { s });
		var parts = str.split($.);
		var whole = parts[0].asInteger, frac = (parts.size > 1).if({ parts[1] }, { "" });
		var den = 10.pow(frac.size);
		var num = (whole * den) + ((frac.size > 0).if({ frac.asInteger }, { 0 }));
		^this.new(neg.if({ num.neg }, { num }), den);
	}

	// CPython Fraction.limit_denominator, in Float-integer arithmetic
	limitDenominator { | maxDenom = 65536 |
		var p0 = 0.0, q0 = 1.0, p1 = 1.0, q1 = 0.0, n = num, d = den, a, q2, k, b1, b2, running = true;
		if (maxDenom < 1) { Error("limitDenominator: maxDenom < 1").throw };
		if (den <= maxDenom) { ^this };
		while { running } {
			a = (n / d).floor;
			q2 = q0 + (a * q1);
			if (q2 > maxDenom) { running = false } {
				# p0, q0, p1, q1 = [p1, q1, p0 + (a * p1), q2];
				# n, d = [d, n - (a * d)];
			};
		};
		k = ((maxDenom - q0) / q1).floor;
		b1 = PanolaRational.new(p0 + (k * p1), q0 + (k * q1));
		b2 = PanolaRational.new(p1, q1);
		^((b2 - this).abs <= (b1 - this).abs).if({ b2 }, { b1 });
	}

	+ { | o | o = PanolaRational.pr_coerce(o); ^PanolaRational.new((num * o.den) + (o.num * den), den * o.den); }
	- { | o | o = PanolaRational.pr_coerce(o); ^PanolaRational.new((num * o.den) - (o.num * den), den * o.den); }
	* { | o | o = PanolaRational.pr_coerce(o); ^PanolaRational.new(num * o.num, den * o.den); }
	/ { | o | o = PanolaRational.pr_coerce(o); ^PanolaRational.new(num * o.den, den * o.num); }

	== { | o | (o.isKindOf(PanolaRational) or: { o.isNumber }).if(
		{ o = PanolaRational.pr_coerce(o); ^(num == o.num) and: { den == o.den } }, { ^false }); }
	hash { ^num.asInteger.hash bitXor: den.asInteger.hash; }
	< { | o | o = PanolaRational.pr_coerce(o); ^((num * o.den) < (o.num * den)); }
	<= { | o | ^(this < o) or: { this == o }; }
	> { | o | ^(this <= o).not; }
	>= { | o | ^(this < o).not; }

	negate { ^PanolaRational.new(num.neg, den); }
	neg { ^this.negate; }
	reciprocal { ^PanolaRational.new(den, num); }
	abs { ^PanolaRational.new(num.abs, den); }
	isNegative { ^num < 0; }
	isZero { ^num == 0; }
	numerator { ^num.asInteger; }
	denominator { ^den.asInteger; }
	asFloat { ^num / den; }
	asInteger { ^(num / den).asInteger; }
	asString { ^num.asInteger.asString ++ "/" ++ den.asInteger.asString; }
	printOn { | stream | stream << "PanolaRational(" << num.asInteger << ", " << den.asInteger << ")"; }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaRational.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): PanolaRational exact rational (Float-integer backed)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_duration_spelling.py
git commit -m "test(panola): PanolaRational arithmetic + fromFloat/fromDecimalString

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: PanolaDurationSpeller — scaffold, simple & dotted

**Files:**
- Create: `…/panola/Classes/PanolaDurationSpeller.sc`
- Test: `tools/panola_duration/test_duration_spelling.py` (add `test_simple_dotted`, `test_guards_zero`)

- [ ] **Step 1: Add the failing tests** (append to `test_duration_spelling.py`)

```python
SIMPLE_DOTTED_SCRIPT = r'''(
var fmt = { |sp|
    sp[\inexpressible].if({ "INEXPR:" ++ sp[\reason] }, {
        "OK:" ++ sp[\components].collect({ |c| c[\type].asString ++ "." ++ c[\dots] ++ "(" ++ c[\meidur] ++ ")" }).join("+");
    });
};
("Q1:" ++ fmt.(PanolaDurationSpeller.spell(1.0))).postln;
("E:" ++ fmt.(PanolaDurationSpeller.spell(0.5))).postln;
("W:" ++ fmt.(PanolaDurationSpeller.spell(4.0))).postln;
("DE:" ++ fmt.(PanolaDurationSpeller.spell(0.75))).postln;
("DDQ:" ++ fmt.(PanolaDurationSpeller.spell(1.75))).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_simple_dotted():
    r = _run(SIMPLE_DOTTED_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "Q1:OK:quarter.0(4)" in r.stdout, r.stdout[-1500:]
    assert "E:OK:eighth.0(8)" in r.stdout, r.stdout[-1500:]
    assert "W:OK:whole.0(1)" in r.stdout, r.stdout[-1500:]
    assert "DE:OK:eighth.1(8)" in r.stdout, r.stdout[-1500:]    # dotted eighth
    assert "DDQ:OK:quarter.2(4)" in r.stdout, r.stdout[-1500:]  # double-dotted quarter = 1.75


GUARDS_SCRIPT = r'''(
var fmt = { |sp| sp[\inexpressible].if({ "INEXPR:" ++ sp[\reason] }, { "OK:" ++ sp[\components].size }) };
("NEG:" ++ fmt.(PanolaDurationSpeller.spell(-1.0))).postln;
("NAN:" ++ fmt.(PanolaDurationSpeller.spell(0.0/0.0))).postln;
("ZERO:" ++ fmt.(PanolaDurationSpeller.spell(0.0))).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_guards_zero():
    r = _run(GUARDS_SCRIPT)
    assert "NEG:INEXPR:negative duration" in r.stdout, r.stdout[-1500:]
    assert "NAN:INEXPR:NaN or infinite duration" in r.stdout, r.stdout[-1500:]
    assert "ZERO:OK:0" in r.stdout, r.stdout[-1500:]   # zero duration -> empty components
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: FAIL — `PanolaDurationSpeller` does not exist.

- [ ] **Step 3: Create the class with the scaffold + simple + dotted** (create the file)

```supercollider
// music21-style duration spelling: a quarterLength -> a notation spelling of one or more
// components (note value + dots + optional tuplet). See the SP1 design doc. Pure, MEI-agnostic.
PanolaDurationSpeller {
	var <options;
	classvar <noteTypes;

	*initClass {
		// name, mei dur token, [num, den] quarterLength ; largest first
		noteTypes = [
			[\duplexMaxima, nil,      [64, 1]],
			[\maxima,       "maxima", [32, 1]],
			[\longa,        "long",   [16, 1]],
			[\breve,        "breve",  [8, 1]],
			[\whole,        "1",      [4, 1]],
			[\half,         "2",      [2, 1]],
			[\quarter,      "4",      [1, 1]],
			[\eighth,       "8",      [1, 2]],
			['16th',        "16",     [1, 4]],
			['32nd',        "32",     [1, 8]],
			['64th',        "64",     [1, 16]],
			['128th',       "128",    [1, 32]],
			['256th',       "256",    [1, 64]],
			['512th',       "512",    [1, 128]],
			['1024th',      "1024",   [1, 256]],
			['2048th',      "2048",   [1, 512]]
		];
	}

	*defaultOptions {
		^(mode: \exact, grid: PanolaRational(1, 512), tolerance: 1e-5, maxDots: 4,
			maxComponents: 16, maxTupletActual: 13, maxTupletNormal: 13, allowLargeTuplets: false,
			maxLargeTupletActual: 1024, maxLargeTupletNormal: 1024, minNoteType: '2048th',
			maxDenominator: 65536);
	}

	*new { | options | ^super.new.pr_init(options); }
	pr_init { | opts |
		options = this.class.defaultOptions;
		opts.notNil.if({ opts.keysValuesDo({ | k, v | options[k] = v }) });
	}

	*spell { | ql, options | ^this.new(options).spell(ql); }

	pr_entry { | name | ^noteTypes.detect({ | e | e[0] == name }); }
	pr_qlOf { | name | var e = this.pr_entry(name); ^PanolaRational(e[2][0], e[2][1]); }
	pr_meidurOf { | name | ^this.pr_entry(name)[1]; }

	pr_dottedValue { | baseQl, dots |
		var total = baseQl, half = baseQl;
		dots.do({ half = half / PanolaRational(2, 1); total = total + half });
		^total;
	}

	pr_component { | name, dots, ql |
		^(type: name, meidur: this.pr_meidurOf(name), dots: dots, ql: ql, tuplets: []);
	}
	pr_componentTuplet { | name, ql, actual, normal |
		^(type: name, meidur: this.pr_meidurOf(name), dots: 0, ql: ql,
			tuplets: [ (actual: actual, normal: normal, actualType: name, normalType: name) ]);
	}
	pr_spelled { | ql, components | ^(inexpressible: false, ql: ql, inferred: true, components: components); }
	pr_inexpressible { | ql, reason | ^(inexpressible: true, ql: ql, reason: reason); }

	normalizeToRational { | x |
		if (x.isKindOf(PanolaRational)) { ^x };
		if (x.isKindOf(String)) { ^PanolaRational.fromDecimalString(x) };
		if (x.isInteger) { ^PanolaRational(x, 1) };
		^PanolaRational.fromFloat(x, options[\maxDenominator]);
	}

	quantizeToGrid { | ql |
		var grid = options[\grid], tol = options[\tolerance];
		var steps = (ql / grid).asFloat.round.asInteger;
		var nearest = grid * PanolaRational(steps, 1);
		^((nearest - ql).abs.asFloat <= tol).if({ nearest }, { ql });
	}

	spell { | x |
		var ql, r;
		// NOTE: SuperCollider 3.14.1's Float has no isInf/isInfinite (only isNaN), so test infinity
		// against inf / inf.neg directly (calling x.isInfinite throws doesNotUnderstand).
		if (x.isKindOf(Float) and: { x.isNaN or: { (x == inf) or: { x == inf.neg } } }) {
			^this.pr_inexpressible(PanolaRational(0, 1), "NaN or infinite duration");
		};
		ql = this.normalizeToRational(x);
		if (ql.isNegative) { ^this.pr_inexpressible(ql, "negative duration") };
		if (ql.isZero) { ^this.pr_spelled(ql, []) };
		if (options[\mode] == \quantize) { ql = this.quantizeToGrid(ql) };

		r = this.trySimpleDuration(ql);      if (r.notNil) { ^this.pr_spelled(ql, [r]) };
		r = this.tryDottedDuration(ql);      if (r.notNil) { ^this.pr_spelled(ql, [r]) };
		// split (tied binary/dotted notes) is tried BEFORE tuplet so a dyadic duration like 0.625
		// spells as tied notes (eighth+32nd), not an ugly tuplet; only non-dyadic values (1/3, 1/5,
		// ...) cannot be split and fall through to the tuplet step. Matches the spec Expected-examples.
		r = this.splitIntoComponents(ql);    if (r.notNil) { ^this.pr_spelled(ql, r) };
		r = this.tryTupletDuration(ql);      if (r.notNil) { ^this.pr_spelled(ql, [r]) };
		r = this.tryLargeTupletFallback(ql); if (r.notNil) { ^this.pr_spelled(ql, [r]) };
		^this.pr_inexpressible(ql, this.pr_inexpressibleReason(ql));
	}

	trySimpleDuration { | ql |
		noteTypes.do({ | e | if (this.pr_qlOf(e[0]) == ql) { ^this.pr_component(e[0], 0, ql) } });
		^nil;
	}

	tryDottedDuration { | ql |
		var maxDots = options[\maxDots];
		noteTypes.do({ | e |
			var base = this.pr_qlOf(e[0]);
			(1..maxDots).do({ | dots |
				if (this.pr_dottedValue(base, dots) == ql) { ^this.pr_component(e[0], dots, ql) };
			});
		});
		^nil;
	}

	// filled in by later tasks
	tryTupletDuration { | ql | ^nil; }
	splitIntoComponents { | ql | ^nil; }
	tryLargeTupletFallback { | ql | ^nil; }
	pr_inexpressibleReason { | ql |
		var minQl = this.pr_qlOf(options[\minNoteType]);
		if (ql < minQl) { ^"smaller than minimum supported note value" };
		^"cannot decompose exactly into assignable components";
	}
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaDurationSpeller.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): PanolaDurationSpeller scaffold + simple/dotted spelling

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_duration_spelling.py
git commit -m "test(panola): duration speller simple/dotted + guards/zero

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Tuplet spelling + ranking

**Files:**
- Modify: `…/panola/Classes/PanolaDurationSpeller.sc` (replace the `tryTupletDuration` stub; add ranking helpers)
- Test: `tools/panola_duration/test_duration_spelling.py` (add `test_tuplets`)

- [ ] **Step 1: Add the failing test**

```python
TUPLET_SCRIPT = r'''(
var fmt = { |sp|
    sp[\inexpressible].if({ "INEXPR" }, {
        sp[\components].collect({ |c|
            var t = c[\tuplets];
            c[\type].asString ++ (t.isEmpty.if({ "" }, { "[" ++ t[0][\actual] ++ ":" ++ t[0][\normal] ++ "]" }));
        }).join("+");
    });
};
("T3:" ++ fmt.(PanolaDurationSpeller.spell(1/3))).postln;   // eighth triplet 3:2
("T6:" ++ fmt.(PanolaDurationSpeller.spell(1/6))).postln;   // 16th triplet 3:2
("T5:" ++ fmt.(PanolaDurationSpeller.spell(1/5))).postln;   // 16th quintuplet 5:4 (1/4*4/5=1/5)
("T11:" ++ fmt.(PanolaDurationSpeller.spell(1/11))).postln; // 32nd 11:8 (power-of-two normal), not 11:1
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplets():
    r = _run(TUPLET_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "T3:eighth[3:2]" in r.stdout, r.stdout[-1500:]
    assert "T6:16th[3:2]" in r.stdout, r.stdout[-1500:]
    assert "T5:16th[5:4]" in r.stdout, r.stdout[-1500:]
    assert "T11:32nd[11:8]" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py::test_tuplets -q`
Expected: FAIL — `tryTupletDuration` still returns nil, so `1/3` falls through to inexpressible → markers wrong.

- [ ] **Step 3: Replace the `tryTupletDuration` stub and add ranking helpers**

In `PanolaDurationSpeller.sc`, replace the line `	tryTupletDuration { | ql | ^nil; }` with:

```supercollider
	tryTupletDuration { | ql |
		var cands = [], maxA = options[\maxTupletActual], maxN = options[\maxTupletNormal];
		noteTypes.do({ | e |
			var base = this.pr_qlOf(e[0]);
			(2..maxA).do({ | actual |
				(1..maxN).do({ | normal |
					if ((actual != normal) and: { (base * PanolaRational(normal, actual)) == ql }) {
						cands = cands.add((name: e[0], actual: actual, normal: normal));
					};
				});
			});
		});
		if (cands.isEmpty) { ^nil };
		cands = cands.sort({ | a, b | this.pr_tupletBefore(a, b) });
		^this.pr_componentTuplet(cands[0][\name], ql, cands[0][\actual], cands[0][\normal]);
	}

	pr_tupletRank { | c |
		var common = [[3,2],[5,4],[6,4],[7,4],[7,8],[5,2],[9,8],[3,4],[2,3]];
		var ci = common.indexOfEqual([c[\actual], c[\normal]]);
		// c[\normal].neg: for non-common tuplets, prefer the LARGEST normal (the power-of-two-normal
		// convention), so 1/11 spells as 32nd[11:8], not the degenerate quarter[11:1].
		^[ ci ? 999, c[\actual], c[\normal].neg, this.pr_qlOf(c[\name]).asFloat.neg ];
	}
	pr_tupletBefore { | a, b |
		var ra = this.pr_tupletRank(a), rb = this.pr_tupletRank(b);
		ra.size.do({ | i |
			if (ra[i] < rb[i]) { ^true };
			if (ra[i] > rb[i]) { ^false };
		});
		^false;
	}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit** (Panola quark + MusicScene)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaDurationSpeller.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): tuplet spelling + candidate ranking

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_duration_spelling.py
git commit -m "test(panola): duration speller tuplet inference (3:2, 5:4)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Multi-component split (tied notes)

**Files:**
- Modify: `…/panola/Classes/PanolaDurationSpeller.sc` (replace the `splitIntoComponents` stub; add `pr_findLargestAssignableAtMost`)
- Test: `tools/panola_duration/test_duration_spelling.py` (add `test_split`)

- [ ] **Step 1: Add the failing test**

```python
SPLIT_SCRIPT = r'''(
var fmt = { |sp|
    sp[\inexpressible].if({ "INEXPR" }, {
        sp[\components].collect({ |c| c[\type].asString ++ "." ++ c[\dots] }).join("+");
    });
};
("S125:" ++ fmt.(PanolaDurationSpeller.spell(1.25))).postln;   // quarter + 16th
("S0625:" ++ fmt.(PanolaDurationSpeller.spell(0.625))).postln; // eighth + 32nd
("SUM:" ++ (PanolaDurationSpeller.spell(1.25)[\components].inject(PanolaRational(0,1), { |a, c| a + c[\ql] }) == PanolaRational(5,4)).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_split():
    r = _run(SPLIT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "S125:quarter.0+16th.0" in r.stdout, r.stdout[-1500:]
    assert "S0625:eighth.0+32nd.0" in r.stdout, r.stdout[-1500:]
    assert "SUM:true" in r.stdout, r.stdout[-1500:]   # components sum exactly to the input
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py::test_split -q`
Expected: FAIL — `splitIntoComponents` still returns nil, so `1.25`/`0.625` fall through to inexpressible.

- [ ] **Step 3: Replace the `splitIntoComponents` stub and add the helper**

In `PanolaDurationSpeller.sc`, replace the line `	splitIntoComponents { | ql | ^nil; }` with:

```supercollider
	splitIntoComponents { | ql |
		var remaining = ql, comps = [], maxComp = options[\maxComponents];
		while { remaining.isZero.not } {
			var c = this.pr_findLargestAssignableAtMost(remaining);
			if (c.isNil) { ^nil };
			comps = comps.add(c);
			remaining = remaining - c[\ql];
			if (comps.size > maxComp) { ^nil };
		};
		^comps;
	}

	pr_findLargestAssignableAtMost { | remaining |
		var best = nil, bestQl = nil, maxDots = options[\maxDots];
		noteTypes.do({ | e |
			var base = this.pr_qlOf(e[0]);
			(0..maxDots).do({ | dots |
				var v = this.pr_dottedValue(base, dots);
				if ((v <= remaining) and: { bestQl.isNil or: { v > bestQl } }) {
					bestQl = v; best = this.pr_component(e[0], dots, v);
				};
			});
		});
		^best;
	}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: PASS (5 passed).

- [ ] **Step 5: Commit** (Panola quark + MusicScene)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaDurationSpeller.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): multi-component split (tied notes) via greedy largest-assignable

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_duration_spelling.py
git commit -m "test(panola): duration speller split (1.25 -> quarter+16th; sum-exact)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Large-tuplet fallback, quantize mode, inexpressible

**Files:**
- Modify: `…/panola/Classes/PanolaDurationSpeller.sc` (replace the `tryLargeTupletFallback` stub)
- Test: `tools/panola_duration/test_duration_spelling.py` (add `test_quantize_and_inexpressible`, `test_largetuplet_toggle`)

- [ ] **Step 1: Add the failing tests**

```python
LTQI_SCRIPT = r'''(
var fmt = { |sp|
    sp[\inexpressible].if({ "INEXPR:" ++ sp[\reason] }, {
        sp[\components].collect({ |c| c[\type].asString }).join("+");
    });
};
var msgy = 0.6249852340957234;
("EXACT:" ++ fmt.(PanolaDurationSpeller.spell(msgy))).postln;
("QUANT:" ++ fmt.(PanolaDurationSpeller.spell(msgy, (mode: \quantize, grid: PanolaRational(1,512), tolerance: 2e-5)))).postln;
("SUBMIN:" ++ fmt.(PanolaDurationSpeller.spell(PanolaRational(1, 8192)))).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_quantize_and_inexpressible():
    r = _run(LTQI_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "QUANT:eighth+32nd" in r.stdout, r.stdout[-1500:]          # snapped to 0.625, then split
    assert "EXACT:eighth+32nd" not in r.stdout, r.stdout[-1500:]      # exact mode did NOT silently snap to 0.625
    assert "SUBMIN:INEXPR:smaller than minimum supported note value" in r.stdout, r.stdout[-1500:]


# The large-tuplet fallback (allowLargeTuplets) is what makes an otherwise-inexpressible value expressible.
# 1/17 needs a 17:1 tuplet, which exceeds maxTupletActual (13), so it is inexpressible by default; with
# allowLargeTuplets (maxLargeTupletActual 1024) it becomes an exact quarter in a 17:1 tuplet.
LARGETUPLET_SCRIPT = r'''(
var v = PanolaRational(1, 17);
("OFF:" ++ PanolaDurationSpeller.spell(v)[\inexpressible].asString).postln;
("ON:" ++ PanolaDurationSpeller.spell(v, (allowLargeTuplets: true))[\inexpressible].asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_largetuplet_toggle():
    r = _run(LARGETUPLET_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "OFF:true" in r.stdout, r.stdout[-1500:]    # 1/17 not expressible with tuplets <= 13
    assert "ON:false" in r.stdout, r.stdout[-1500:]    # allowLargeTuplets -> exact 17:1 tuplet, not inexpressible
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: `test_quantize_and_inexpressible` already PASSES (quantize/split/inexpressible were finished in Tasks 2–4); `test_largetuplet_toggle` FAILS on `ON:false` — the `tryLargeTupletFallback` stub returns nil, so `1/17` with `allowLargeTuplets` is still inexpressible (`ON:true`). That failure is the red driver for Step 3.

- [ ] **Step 3: Replace the `tryLargeTupletFallback` stub**

In `PanolaDurationSpeller.sc`, replace the line `	tryLargeTupletFallback { | ql | ^nil; }` with:

```supercollider
	tryLargeTupletFallback { | ql |
		if (options[\allowLargeTuplets].not) { ^nil };
		noteTypes.do({ | e |
			var base = this.pr_qlOf(e[0]);
			var ratio = ql / base;                 // = normal / actual
			var normal = ratio.numerator, actual = ratio.denominator;
			if ((actual != normal) and: { actual >= 1 } and: { normal >= 1 }
				and: { actual <= options[\maxLargeTupletActual] }
				and: { normal <= options[\maxLargeTupletNormal] }) {
				^this.pr_componentTuplet(e[0], ql, actual, normal);
			};
		});
		^nil;
	}
```

- [ ] **Step 4: Run the full file to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q`
Expected: PASS (7 passed).

- [ ] **Step 5: Commit** (Panola quark + MusicScene)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaDurationSpeller.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): large-tuplet fallback for exact-mode spelling

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_duration/test_duration_spelling.py
git commit -m "test(panola): quantize snap, sub-min inexpressible, large-tuplet toggle

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Whelk docs (every member) + regenerate HelpSource with gendoc.bat

Document **every** member of both new classes in the project's whelk style — the same format used in `Classes/PanolaMEI.sc` / `Classes/Panola.sc`: a `/* … */` block immediately above each `var`, classmethod, and method. Then regenerate all Panola schelp with the quark's `gendoc.bat`.

The whelk block format (read `Classes/PanolaMEI.sc` for live examples):
- above a `var x;`: `[method.x]` + `description = "…"` + `[method.x.returns]` + `what = "…"`.
- above a `*classMethod { … }`: `[classmethod.name]` + `description` + `[classmethod.name.args]` (one `arg = "…"` line per argument) + `[classmethod.name.returns]` + `what`.
- above an instance `method { … }`: `[method.name]` + `description` + `[method.name.args]` (if any) + `[method.name.returns]` + `what`.
- Prose is plain `strong::`/`teletype::`/`link::` markup — **never** `## … || …` definition-list lines (whelk silently eats those).

**Files:**
- Modify: `…/panola/Classes/PanolaRational.sc`, `…/panola/Classes/PanolaDurationSpeller.sc` (add `[general]` + per-member whelk blocks)
- Regenerate (via gendoc.bat): all `…/panola/HelpSource/Classes/*.schelp`

- [ ] **Step 1: Document `PanolaRational.sc`.** Insert the `[general]` block before `PanolaRational {`, and a whelk block above every member below.

`[general]` block:
```supercollider
/*
[general]
title = "PanolaRational"
summary = "an exact rational number used by Panola's duration spelling"
categories = "Utils"
related = "Classes/PanolaDurationSpeller"
description = '''
PanolaRational is a minimal exact rational (teletype::num/den::, always reduced, sign in the numerator,
denominator positive). It exists because SuperCollider has no rational type and because notation must not
be treated as floating point. Numerator and denominator are stored as Float-valued integers so the
arithmetic stays exact without overflowing SuperCollider's 32-bit Integer. It supports the strong::+ - * /::
operators and the comparison operators, plus construction from an Integer, a decimal String
(teletype::*fromDecimalString::), or a Float via a limit-denominator continued fraction
(teletype::*fromFloat::), e.g. teletype::0.3333333:: becomes teletype::1/3::.
'''
*/
```

Two representative member blocks (write the rest in the same shape):
```supercollider
	/*
	[classmethod.fromFloat]
	description = "the exact rational of a finite Float, with the denominator limited so common values snap to their intended fraction (e.g. 0.3333333 -> 1/3, 0.4 -> 2/5)"
	[classmethod.fromFloat.args]
	x = "a finite Float"
	maxDenom = "the largest allowed denominator (default 65536)"
	[classmethod.fromFloat.returns]
	what = "a PanolaRational"
	*/
	*fromFloat { | x, maxDenom = 65536 | ... }

	/*
	[method.limitDenominator]
	description = "the closest rational to this value whose denominator is at most maxDenom (CPython Fraction.limit_denominator)"
	[method.limitDenominator.args]
	maxDenom = "the largest allowed denominator (default 65536)"
	[method.limitDenominator.returns]
	what = "a PanolaRational"
	*/
	limitDenominator { | maxDenom = 65536 | ... }
```

Document these members with these descriptions (expand each into the block format above):
- `var num` — "the numerator (a Float holding an exact integer)".
- `var den` — "the denominator (a Float holding an exact positive integer)".
- `*new(num, den)` — "create a reduced rational num/den"; args `num`="the numerator", `den`="the denominator (default 1)"; returns "a PanolaRational".
- `*fromInteger(n)` — "an Integer as n/1"; args `n`="an Integer"; returns "a PanolaRational".
- `*fromFloat`, `limitDenominator` — as shown above.
- `*fromDecimalString(s)` — "parse a decimal String such as \"0.625\" as an exact rational (5/8)"; args `s`="a decimal String"; returns "a PanolaRational".
- `numerator` — returns "the numerator as an Integer". `denominator` — returns "the denominator as an Integer".
- `asFloat` — returns "the value as a Float". `asInteger` — returns "the value truncated toward zero as an Integer".
- `asString` — returns "the value as \"num/den\"".
- `reciprocal` — returns "den/num as a PanolaRational". `abs` — "the absolute value". `negate` — "the negation".
- `isNegative` — returns "true if the value is < 0". `isZero` — returns "true if the value is 0".

(The binary operators `+ - * / == < <= > >=` and `hash`/`printOn` are described in `[general]`; leave them undocumented — the sibling panola classes likewise don't add per-operator blocks.)

- [ ] **Step 2: Document `PanolaDurationSpeller.sc`.** Insert the `[general]` block before `PanolaDurationSpeller {`, and a whelk block above every member below.

`[general]` block:
```supercollider
/*
[general]
title = "PanolaDurationSpeller"
summary = "spell a quarterLength as conventional notation (music21-style)"
categories = "Notation, Utils"
related = "Classes/PanolaRational, Classes/Panola"
description = '''
PanolaDurationSpeller maps a single duration in strong::quarterLength:: units (teletype::1.0:: = quarter,
teletype::0.5:: = eighth, teletype::0.25:: = 16th) to a notation spelling: one or more components, each a
note value plus dots plus an optional tuplet. It tries, in order, an exact ordinary value, a dotted value,
a decomposition into several tied components, a tuplet, and (optionally) a large-tuplet fallback, otherwise
it reports the duration teletype::inexpressible::. All arithmetic is exact (link::Classes/PanolaRational::).

code::
PanolaDurationSpeller.spell(1.0);    // quarter
PanolaDurationSpeller.spell(0.75);   // dotted eighth
PanolaDurationSpeller.spell(1/3);    // eighth with a 3:2 tuplet
PanolaDurationSpeller.spell(1.25);   // quarter tied to a 16th
::

strong::Modes.:: In teletype::\\exact:: mode (default) the input value is preserved exactly; if no exact
spelling exists the result is teletype::inexpressible:: (or a precise large tuplet when
teletype::allowLargeTuplets:: is set). In teletype::\\quantize:: mode the value is snapped to a grid within
a tolerance before spelling; quantization is never implicit. Options (a plain Event) tune the note-type
range, dots, tuplet limits, and float handling.
'''
*/
```

Document these members (expand each into the block format; args as noted):
- `var options` — "the effective options Event (defaults merged with any overrides)".
- `*new(options)` — "a speller whose options are defaultOptions merged with the given overrides"; args `options`="an Event overriding any defaultOptions keys, or nil"; returns "a PanolaDurationSpeller".
- `*spell(ql, options)` — "convenience: spell ql with a speller built from options"; args `ql`="a quarterLength", `options`="an options Event or nil"; returns "a spelling Event".
- `*defaultOptions` — "the default options Event (mode, grid, tolerance, maxDots, maxComponents, tuplet limits, float policy)"; returns "an Event".
- `spell(x)` — "spell a quarterLength x (a PanolaRational, Integer, decimal String, or Float) as a notation spelling"; args `x`="the quarterLength"; returns "a spelling Event: on success (inexpressible: false, ql:, inferred: true, components: [ … ]); otherwise (inexpressible: true, ql:, reason:)".
- `normalizeToRational(x)` — "convert x to a PanolaRational (a Float via a limit-denominator continued fraction, capped at maxDenominator)"; args `x`; returns "a PanolaRational".
- `quantizeToGrid(ql)` — "snap ql to the nearest grid multiple when within tolerance (quantize mode)"; args `ql`; returns "a PanolaRational".
- `trySimpleDuration(ql)` — "a single ordinary-note-value component equal to ql, or nil"; args `ql`; returns "a component Event or nil".
- `tryDottedDuration(ql)` — "a single dotted-note component equal to ql, or nil"; args `ql`; returns "a component Event or nil".
- `tryTupletDuration(ql)` — "a single note-under-a-tuplet component equal to ql (best-ranked candidate), or nil"; args `ql`; returns "a component Event or nil".
- `splitIntoComponents(ql)` — "decompose ql into tied ordinary/dotted components, or nil if it cannot be split exactly"; args `ql`; returns "an Array of component Events, or nil".
- `tryLargeTupletFallback(ql)` — "spell the whole ql as one large tuplet when allowLargeTuplets is set, or nil"; args `ql`; returns "a component Event or nil".
- The private helpers (`pr_entry`, `pr_qlOf`, `pr_meidurOf`, `pr_dottedValue`, `pr_component`, `pr_componentTuplet`, `pr_spelled`, `pr_inexpressible`, `pr_inexpressibleReason`, `pr_tupletRank`, `pr_tupletBefore`, `pr_findLargestAssignableAtMost`) — give each a one-line `[method.pr_x]` description of what it returns (e.g. `pr_qlOf` — "the quarterLength of a note type as a PanolaRational"). The classvar `noteTypes` is described in `[general]`; no separate block needed.

- [ ] **Step 3: Regenerate all Panola schelp with gendoc.bat**

`gendoc.bat` (in the quark root) deletes every `HelpSource/Classes/*.schelp` and regenerates them from all `Classes/*.sc`, so unchanged classes reproduce byte-for-byte and the two new classes get fresh schelp. Run it (it's a Windows batch file):
```bash
cd "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" && cmd //c gendoc.bat
```
Expected: prints `Removing old help files...` / `Generating help files...` / `Done.` with no `ERROR`.

- [ ] **Step 4: Verify the new schelp exist and the classes still compile**

```bash
ls "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaRational.schelp" "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaDurationSpeller.schelp"
grep -c quarterLength "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaDurationSpeller.schelp"
cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q
```
Expected: both schelp files listed; grep count non-zero; pytest **7 passed** (doc-comment edits must not break compilation).

- [ ] **Step 5: Commit** (Panola quark — includes any incidentally-regenerated sibling schelp)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add -A Classes HelpSource
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "docs(panola): whelk docs for PanolaRational + PanolaDurationSpeller; regen schelp (gendoc)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration/test_duration_spelling.py -q` → **7 passed** (rational, simple/dotted, guards/zero, tuplets, split, quantize/inexpressible, large-tuplet toggle).
- [ ] Regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei tools/msscore/test_midi_routing.py -q` → unchanged (SP1 adds new classes only; nothing existing is touched).
- [ ] Confirm the spec's Expected-examples all hold: `1.0`→quarter, `0.75`→dotted eighth, `1/3`→eighth 3:2, `1.25`→quarter+16th, `0.625`→eighth+32nd, `0.6249852…` exact→inexpressible / quantize→eighth+32nd.

## Notes for the implementer

- **`^` inside a `.do`/closure is a non-local return** from the enclosing method in SuperCollider — that is intentional in `trySimpleDuration`/`tryDottedDuration`/`pr_findLargestAssignableAtMost`/`tryLargeTupletFallback` (return the first/So-far-best match).
- **All comparisons are on `PanolaRational`, never floats.** `quantizeToGrid` and the NaN/Inf guard are the only places that touch Float, deliberately.
- **`# a, b = [x, y]`** is SuperCollider's destructuring multiple assignment; the right-hand array is fully evaluated (using the old values) before assignment, which is why the `limitDenominator` step swaps `p0,q0,p1,q1` and `n,d` correctly.
- If a tuplet test's exact `actual:normal` differs from the expected marker, check `pr_tupletRank`'s `common` list ordering — the ranking, not the search, decides which equivalent tuplet wins.
- Keep `noteTypes` largest-first; `pr_findLargestAssignableAtMost` and the `try*` order depend on it.
