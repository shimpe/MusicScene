# Panola barline-crossing tuplets (SP2d v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split an explicit `*m/d` tuplet that crosses a barline into two (or more) tied per-measure `<tuplet>` brackets, per `docs/superpowers/specs/2026-07-07-panola-barline-crossing-tuplets-design.md`.

**Architecture:** In `PanolaMEI.sc`'s `voiceToMeasures`, the complete-`\tuplet` branch (`:268-285`) currently warns + emits the whole bracket in one bar when the tuplet crosses a barline. Replace that: when it crosses, **walk the members, split a straddling member at the barline** (spell the two fragments at the tuplet ratio with `PanolaDurationSpeller`), place records into per-measure buckets carrying the tuplet ratio, and let SP2c's `wrapTuplets` bracket each bucket — the straddling member's tie crosses the barline. If any straddling fragment can't be spelled at the tuplet's own ratio, fall back to today's whole-bracket + warning. Non-crossing tuplets keep the atomic `tupletMEI` path (byte-identical).

**Tech Stack:** SuperCollider (sclang); Python pytest driving sclang → MEI → Verovio (`tools/panola_mei/`, `render_props`); whelk → schelp via `gendoc.bat`.

---

## Repositories & branches

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch **master**; bash path `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola`). `PanolaMEI.sc` + regenerated HelpSource commit here.
- **MusicScene repo** — `D:\Projects\MusicScene` (branch **feature/panola-tuplet-completion**). Tests commit here.

sclang `C:\Program Files\SuperCollider-3.14.1\sclang.exe`. Editing `PanolaMEI.sc` recompiles next run; a syntax error → MEI fails; a runtime error → 120s hang (run the temp `.scd` by hand, **real Windows paths** not `/tmp`). Stuck sclang: PowerShell `Get-Process sclang | Stop-Process -Force`. TAB-indented.

## Current code (reference)

The complete-`\tuplet` branch inside the `if (completed.not) { if (unit[\kind] == \tuplet) {` block (`PanolaMEI.sc:268-285`):

```supercollider
					if (unit[\kind] == \tuplet) {
						// tuplet groups are atomic: never decomposed or split-and-tied across a barline
						var tbeats = unit[\beats];
							// give each tuplet member its real sub-tuplet beat offset, so dynamics/slur endpoints
							// land on the right note (a slur inside one tuplet must not collapse to a point)
							unit[\members].inject(0.0, { |macc, mev|
								var mts = pos + macc + 1;
								if (mev[\dynMark].notNil) { dynams = dynams.add(( measure: measures.size, tstamp: mts, mark: mev[\dynMark] )) };
								if ((mev[\slur] ? "") != "") { applySlur.(mev[\slur], measures.size, mts) };
								macc + mev[\beats];
							});
						if ((tbeats > ((bb - pos) + eps)) and: { (bb - pos) > eps }) {
							("PanolaMEI: tuplet crosses a barline; kept whole in bar " ++ measures.size ++ " (split tuplets unsupported)").warn;
						};
						measures[measures.size-1] = measures[measures.size-1].add(
							( str: tupletMEI.(unit, k), md: 0, rest: false, beatPos: pos, tuplet: true ));
						pos = pos + tbeats;
						if (pos >= (bb - eps)) { measures = measures.add([]); pos = (pos - bb).max(0.0) };
					} {
```

`wrapTuplets` (added in SP2c) groups consecutive same-ratio fragment-records into one `<tuplet num numbase>` record (beamed via `beamRun`); it's already defined above this block. `meiElement.(ev, meidur, dots, tie, k)` builds a `<note>` string. A spelling component is `( type:, meidur:, dots:, ql:, tuplets: [( actual:, normal:, … )] )`.

---

### Task 1: split a barline-crossing tuplet into tied per-measure brackets

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (the complete-`\tuplet` branch)
- Create/Test: `D:\Projects\MusicScene\tools\panola_mei\test_barline_tuplets.py`

- [ ] **Step 1: Write the failing tests** — create `test_barline_tuplets.py`:

```python
"""SP2d: an explicit *m/d tuplet crossing a barline splits into tied per-measure <tuplet> brackets.
Generates MEI via sclang, asserts on the MEI XML, renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_barline_tuplets.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_bxt_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read(), r.stdout
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_septuplet_across_a_barline_splits_into_two_brackets():
    # 7:4 septuplet of 16ths starting on the "and" of beat 4 (3.5) spans 3.5-4.5, crossing the barline.
    # The straddling member is cut exactly in half -> two tied 32nd[7:4]; two <tuplet 7:4> brackets.
    mei, out = _mei('Panola.scoreAsMEI([Panola("c5_4 d5 e5 f5_8 g5_16*4/7 a5 b5 c6 d6 e6 f6")], '
                    '"4/4", \\Cmajor, [\\treble], nil)')
    assert "crosses a barline" not in out, out[-1500:]              # no warning: it split cleanly
    assert mei.count('<tuplet num="7" numbase="4">') == 2, mei      # one bracket per bar
    assert mei.count("<measure ") == 2, mei
    assert mei.count('<note dur="32"') == 2, mei                    # the straddling 16th -> two 32nds
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei              # tied across the barline
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_quarter_triplet_across_a_barline():
    # a 3:2 quarter-triplet starting at beat 3 spans 3-5, crossing the barline; the middle member
    # straddles and splits into two tied triplet-eighths -> two <tuplet 3:2> brackets.
    mei, out = _mei('Panola.scoreAsMEI([Panola("c5_2 d5_4 e5_4*2/3 f5 g5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert "crosses a barline" not in out, out[-1500:]
    assert mei.count('<tuplet num="3" numbase="2">') == 2, mei
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_noncrossing_tuplets_unchanged():
    # a complete in-bar triplet is byte-identical (atomic path); a 7:4 septuplet in beat 1 is one bracket.
    trip, _ = _mei('Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert trip.count("<tuplet ") == 1 and trip.count('<note dur="4"') == 3, trip
    sept, _ = _mei('Panola.scoreAsMEI([Panola("c5_16*4/7 d5 e5 f5 g5 a5 b5 c6_2 r_4")], "4/4", \\Cmajor, [\\treble], nil)')
    assert sept.count('<tuplet num="7" numbase="4">') == 1, sept
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_barline_tuplets.py -q`
Expected: the two crossing tests FAIL (today the tuplet is emitted whole in one bar with the `"crosses a barline"` warning → 1 bracket, 1 measure). `test_noncrossing_tuplets_unchanged` PASSES already.

- [ ] **Step 3: Implement the split.** Replace the complete-`\tuplet` block (`PanolaMEI.sc:268-285`, the `if (unit[\kind] == \tuplet) { … }` part shown above) with:

```supercollider
					if (unit[\kind] == \tuplet) {
						var tbeats = unit[\beats],
							crosses = (tbeats > ((bb - pos) + eps)) and: { (bb - pos) > eps },
							ratio = ( num: unit[\num], numbase: unit[\numbase] ),
							// build per-measure record buckets by walking members, splitting a straddling
							// member at the barline. Returns nil if any straddling fragment is inexpressible
							// or not a single component at the unit's ratio -> caller falls back.
							buildSplit = {
								var buckets = [[]], sub = pos, ok = true, speller = PanolaDurationSpeller.new,
									fragAt = { |d|   // spell d beats -> (meidur, dots) at the unit's ratio, or nil
										var sp = speller.spell(PanolaRational.fromFloat(d)), c;
										(sp[\inexpressible] or: { sp[\components].size != 1 }).if({ nil }, {
											c = sp[\components][0];
											((c[\tuplets].size == 1)
												and: { c[\tuplets][0][\actual] == ratio[\num] }
												and: { c[\tuplets][0][\normal] == ratio[\numbase] }).if(
												{ ( meidur: c[\meidur], dots: c[\dots] ) }, { nil }); });
									};
								unit[\members].do({ |mev|
									var mb = mev[\beats], firstPiece = true;
									// dyn/slur at the member onset (measure = base + current bucket index)
									if (mev[\dynMark].notNil) { dynams = dynams.add(( measure: measures.size + (buckets.size - 1), tstamp: sub + 1, mark: mev[\dynMark] )) };
									if ((mev[\slur] ? "") != "") { applySlur.(mev[\slur], measures.size + (buckets.size - 1), sub + 1) };
									while { (mb > eps) and: { ok } } {
										var room = bb - sub;
										(mb <= (room + eps)).if({
											// the (remaining) member fits in this bar
											var md = firstPiece.if({ mev[\meidur] }, { var f = fragAt.(mb); f.isNil.if({ ok = false; nil }, { f[\meidur] }) }),
												dt = firstPiece.if({ mev[\dots] }, { var f = fragAt.(mb); f.isNil.if({ 0 }, { f[\dots] }) }),
												tie = firstPiece.if({ nil }, { "t" });
											if (ok) {
												buckets[buckets.size - 1] = buckets[buckets.size - 1].add(
													( str: meiElement.(mev, md, dt, tie, k), md: md.asInteger, rest: mev[\rest], beatPos: sub, tup: ratio ));
											};
											sub = sub + mb; mb = 0;
											if ((bb - sub) < eps) { buckets = buckets.add([]); sub = 0.0 };
										}, {
											// the member straddles the barline: emit `room` beats here (tie), cross over
											var f = fragAt.(room);
											f.isNil.if({ ok = false }, {
												var tie = firstPiece.if({ "i" }, { "m" });
												buckets[buckets.size - 1] = buckets[buckets.size - 1].add(
													( str: meiElement.(mev, f[\meidur], f[\dots], tie, k), md: f[\meidur].asInteger, rest: mev[\rest], beatPos: sub, tup: ratio ));
												buckets = buckets.add([]); mb = mb - room; sub = 0.0; firstPiece = false;
											});
										});
									};
								});
								ok.if({ buckets }, { nil });
							},
							split = crosses.if({ buildSplit.value }, { nil });
						if (split.notNil) {
							// emit each per-measure bucket through wrapTuplets, advancing pos across barlines
							split.do({ |bucket, bi|
								wrapTuplets.(bucket).do({ |r| measures[measures.size - 1] = measures[measures.size - 1].add(r) });
								if (bi < (split.size - 1)) { measures = measures.add([]) };
							});
							pos = (pos + tbeats) - ((split.size - 1) * bb);
						} {
							// non-crossing, or a fragment could not be spelled: atomic bracket (+ warn if it crosses)
							unit[\members].inject(0.0, { |macc, mev|
								var mts = pos + macc + 1;
								if (mev[\dynMark].notNil) { dynams = dynams.add(( measure: measures.size, tstamp: mts, mark: mev[\dynMark] )) };
								if ((mev[\slur] ? "") != "") { applySlur.(mev[\slur], measures.size, mts) };
								macc + mev[\beats];
							});
							if (crosses) { ("PanolaMEI: tuplet crosses a barline; kept whole in bar " ++ measures.size ++ " (fragment not expressible at the tuplet ratio)").warn };
							measures[measures.size-1] = measures[measures.size-1].add(
								( str: tupletMEI.(unit, k), md: 0, rest: false, beatPos: pos, tuplet: true ));
							pos = pos + tbeats;
							if (pos >= (bb - eps)) { measures = measures.add([]); pos = (pos - bb).max(0.0) };
						};
					} {
```

Notes for the implementer (this is intricate — **let the tests drive it**):
- `buildSplit` does the dyn/slur side effects while walking; those are only wanted when the split succeeds. If `ok` ends false, the fallback re-does dyn/slur in the atomic path — so on fallback the dyn/slur may be added twice. **Fix:** either gate the dyn/slur adds inside `buildSplit` behind a post-hoc filter, or (simpler) collect dyn/slur into locals during the walk and only commit them if `split.notNil`. Do whichever keeps a fallback from double-adding dynams; a crossing tuplet with a `@dyn` is an edge — get it right or leave the mark off on the rare fallback, but never double.
- The record shape matches `wrapTuplets` (needs `tup`, `md`, `rest`, `beatPos`, `str`).
- `pos` after the split = the real end position modulo the barline: `(pos + tbeats) - (numBarsCrossed * bb)`, where `numBarsCrossed = split.size - 1`.
- A member may cross **multiple** barlines (a long tuplet) — the `while` loop handles that (it keeps slicing `room` off `mb`). The first slice ties `"i"`, middle slices `"m"`, the final piece `"t"`.

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q`
Expected: `test_barline_tuplets` (3 passed) AND the full `panola_mei` suite green — **`test_tuplets` byte-identical** (non-crossing tuplets never enter the split path). Iterate on the split until the crossing tests pass; dump the MEI (`_mei(...)`) and inspect the two brackets + the tie if a count is off.

- [ ] **Step 5: Verify byte-identity for non-crossing tuplets**

Dump MEI for `c5_4*2/3 d5 e5`, `c5_8*2/3 d5 e5 f5 g5 a5` (sixeighths), `c5_16*4/5 d5 e5 f5 g5` (a quintuplet in beat 1), `c5_8*2/3 r d5 c5_2 r_4` (with_rest) under HEAD-before vs after; confirm identical. Any difference = a bug in the crossing gate (`crosses` must be false for these).

- [ ] **Step 6: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): split barline-crossing tuplets into tied per-measure brackets

Walk the members, split a straddling member at the barline, spell each fragment
at the tuplet ratio (SP1) and bracket per measure with wrapTuplets (SP2c); the
straddling member's tie crosses the barline. Fall back to the whole bracket +
warning when a fragment is not expressible at the ratio. Non-crossing tuplets
keep their atomic path (byte-identical).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_mei/test_barline_tuplets.py
git commit -m "test(panola_mei): septuplet/triplet across a barline -> two tied <tuplet> brackets

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Whelk docs refresh + regenerate schelp

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (doc comment only)
- Regenerate: `…/panola/HelpSource/Classes/PanolaMEI.schelp`

- [ ] **Step 1: Update the whelk prose.** In `PanolaMEI`'s `[general]` / `[classmethod.scoreAsMEI]` blocks, replace the "a tuplet that would cross a barline stays a warned partial bracket" wording with: a tuplet that **crosses a barline is split into tied per-measure `<tuplet>` brackets** (a straddling member is cut at the barline into tied sub-tuplet notes); if a straddling fragment is not expressible at the tuplet ratio it falls back to the whole bracket + warning. Whelk-safe: `strong::`/`teletype::`/`link::` only, no `## … || …`, balanced `/* */`. Do NOT document inner closures.

- [ ] **Step 2: Regenerate**

```powershell
& "C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\gendoc.bat"
```
Expected: `Removing old help files...` / `Generating help files...` / `Done.` no ERROR.

- [ ] **Step 3: Verify**

```bash
ls "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMEI.schelp"
cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q
```
Expected: schelp present; `tools/panola_mei` all green; only `PanolaMEI.sc` (prose) + `PanolaMEI.schelp` changed (other 7 schelp byte-identical); the `.sc` diff is doc-comment-only (`git diff --numstat` symmetric, all inside `/* */`).

- [ ] **Step 4: Commit** (Panola quark)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "docs(panola): PanolaMEI whelk doc notes barline-crossing tuplet splitting; regen schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q` → all green (barline-tuplet tests + `test_tuplets` + `test_tuplet_completion` + `test_meter_notation` + `test_asmei` + `test_expression` + `test_slurs`).
- [ ] Full regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration tools/panola_mei tools/msscore/test_midi_routing.py -q`.
- [ ] Spot-check: dump the septuplet-across-a-barline MEI and eyeball the two `<tuplet num="7" numbase="4">` brackets with the tied 32nds across the barline.

## Notes for the implementer

- **The crossing gate is the safety line.** `crosses` must be false for every non-crossing tuplet, so they take the unchanged atomic path and stay byte-identical. Verify a plain in-bar triplet first (Step 5).
- **Fallback never renders worse than today.** If `buildSplit` returns nil (a fragment not spellable at the ratio), you get exactly the old whole-bracket + warning.
- **Ties chain through brackets** — the tie attribute is on the `<note>`; `wrapTuplets` only regroups records. A straddling member: first slice `"i"`, interior slices `"m"`, last `"t"`.
- **`tup` equality is field-wise** in `wrapTuplets` (already so). The split records set `tup = (num, numbase)` from the unit.
- **Do not touch `tupletMEI` or the `\normal`/completion paths.** Only the complete-`\tuplet` branch changes.
- **Whelk docs (Task 2)** must be whelk-safe or the class library won't compile and the whole suite fails.
