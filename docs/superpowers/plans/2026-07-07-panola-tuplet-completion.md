# Panola tuplet completion (SP2c v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notate incomplete `*m/d` tuplets the music21 way — complete them by splitting the following note/rest into the `<tuplet>` bracket (tied) — per `docs/superpowers/specs/2026-07-07-panola-tuplet-completion-design.md`.

**Architecture:** Three changes to `PanolaMEI.sc`'s `scoreAsMEI`. **Piece 1:** `meterPieces` keeps each fragment's tuplet descriptor. **Piece 2:** a `wrapTuplets` helper groups consecutive same-ratio fragment-records into `<tuplet>` brackets, and becomes the `\normal`-path emission (nil-tuplet fragments render exactly as today). **Piece 3:** an incomplete `*m/d` unit is completed by spelling its remainder as tuplet member(s) that join the bracket, tying the donor note out. Complete `*m/d` units keep their atomic `tupletMEI` path.

**Tech Stack:** SuperCollider (sclang); Python pytest driving sclang → MEI → Verovio (`tools/panola_mei/`, `render_props`); whelk → schelp via `gendoc.bat`.

---

## Repositories & branches

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch **master**; bash path `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola`). `PanolaMEI.sc` + regenerated HelpSource commit here.
- **MusicScene repo** — `D:\Projects\MusicScene` (branch **feature/panola-tuplet-completion**). The pytest tests commit here.

sclang: `C:\Program Files\SuperCollider-3.14.1\sclang.exe`. Editing `PanolaMEI.sc` recompiles on the next run; a syntax error → MEI generation fails (`ERROR` in stdout / no file); a runtime error → 120s hang (run the temp `.scd` by hand). Stuck sclang: PowerShell `Get-Process sclang | Stop-Process -Force`. `PanolaMEI.sc` is TAB-indented.

## Current code (reference — all in `scoreAsMEI`)

- `meterPieces` (`:91-106`) returns `[meidur, dots, beats]` fragments, **dropping** `component[\tuplets]`.
- The `\normal` emit loop (`:224-238`) builds a record per fragment: `( str: meiElement.(ev, pc[0], pc[1], tie, k), md: pc[0].asInteger, rest: ev[\rest], beatPos: subpos )`, tie = `i/m/t` from `firstFrag`/`isFirst`/`isLast`.
- The `\tuplet` path (`:200-218`) emits complete units atomically via `tupletMEI.(unit, k)` (one record, `md:0, tuplet:true`); an incomplete unit warns (`:213` and in `groupEvents` `:283`).
- `groupEvents` (`:295`) closes a same-ratio run when `acc` hits a container in `[0.25,0.5,1.0,2.0,4.0]`; sets `complete: closed`, `beats: acc`, `num: d`, `numbase: m`, `members: [...]`.
- `tupletMEI` (`:286`), `beamRun` (`:272`), `beamMeasure` (`:256`) join records to MEI.
- Fragment element 0 (`meidur`) is the MEI dur token (`"8"`, `"breve"`); `.asInteger` gives the numeric for beaming (0 for breve/long/maxima).

---

### Task 1: Pieces 1–2 — carry the tuplet descriptor and bracket split fragments

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (`meterPieces`; add `wrapTuplets`; the `\normal` emit loop)
- Create/Test: `D:\Projects\MusicScene\tools\panola_mei\test_tuplet_completion.py`

- [ ] **Step 1: Write the failing test** — create `test_tuplet_completion.py`:

```python
"""SP2c tuplet-completion tests: PanolaMEI brackets split fragments and completes incomplete tuplets.
Generates MEI via sclang, asserts on the MEI XML, and renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_tuplet_completion.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_tupc_")
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
def test_split_fragments_render_inside_a_tuplet():
    # c5_8*2/3 d5 c5_2 : the incomplete triplet (still partial in Phase A) pushes the half note onto a
    # non-dyadic onset (2/3); the splitter spells its fragments as triplet values, which must now be
    # WRAPPED in <tuplet> brackets rather than emitted as bare mis-valued notes. Before Piece 1-2 there
    # is exactly one <tuplet> (the partial triplet) and bare dur="8"/dur="4" tuplet-value notes after it;
    # after, the cascade fragments are bracketed too.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 c5_2")], "4/4", \\Cmajor, [\\treble], nil)')
    assert mei.count("<tuplet ") >= 2, mei                 # partial triplet + at least one cascade bracket
    # no tuplet-valued note sits directly outside a bracket (every <note> after a </tuplet> that is a
    # triplet fragment is itself inside a <tuplet>); sanity: it renders
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_plain_and_complete_tuplets_unchanged():
    # a plain-note score and a complete triplet must be byte-identical to before (nil-tuplet fragments
    # render exactly as today; complete *m/d keeps its atomic path).
    plain = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 c5_4")], "4/4", \\Cmajor, [\\treble], nil)')
    assert plain.count("<tuplet ") == 0 and plain.count("<note") == 4, plain
    trip = _mei('Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert '<tuplet num="3" numbase="2">' in trip and trip.count('<note dur="4"') == 3, trip
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_tuplet_completion.py -q`
Expected: `test_split_fragments_render_inside_a_tuplet` FAILS (currently `<tuplet>` count is 1 — the cascade fragments are bare notes). `test_plain_and_complete_tuplets_unchanged` should already PASS.

- [ ] **Step 3a: Piece 1 — `meterPieces` carries the tuplet descriptor.** Replace the `comps.do` body (`:96-104`):

```supercollider
			comps.do({ |c|
				var sp = c[\spelling];
				if (sp[\inexpressible]) {
					("PanolaMEI: inexpressible piece " ++ c[\durationQL].asString ++ " — using decompose").warn;
					decompose.(c[\durationQL].asFloat).do({ |pc| out = out.add([pc[0], pc[1], durToBeats.(pc[0], pc[1]), nil]) });
				} {
					sp[\components].do({ |x|
						var tup = x[\tuplets].isEmpty.if({ nil },
							{ ( num: x[\tuplets][0][\actual], numbase: x[\tuplets][0][\normal] ) });
						out = out.add([x[\meidur], x[\dots], x[\ql].asFloat, tup]);
					});
				};
			});
```

- [ ] **Step 3b: Piece 2 — add `wrapTuplets`.** Insert right after `beamRun` (`:284`, before `tupletMEI`):

```supercollider
		// group consecutive fragment-records that share a tuplet ratio into one <tuplet> bracket record
		// (beamed inside via beamRun); records with a nil ratio pass through unchanged. This is music21's
		// makeTupletBrackets over split fragments.
		var wrapTuplets = { |recs|
			var out = [], i = 0;
			while { i < recs.size } {
				var rec = recs[i], tup = rec[\tup];
				if (tup.notNil) {
					var run = [rec], j = i + 1;
					while { (j < recs.size) and: { recs[j][\tup].notNil }
						and: { recs[j][\tup][\num] == tup[\num] } and: { recs[j][\tup][\numbase] == tup[\numbase] } } {
						run = run.add(recs[j]); j = j + 1;
					};
					out = out.add(( str: "<tuplet num=\"" ++ tup[\num] ++ "\" numbase=\"" ++ tup[\numbase] ++ "\">"
						++ beamRun.(run) ++ "</tuplet>", md: 0, rest: false, beatPos: run[0][\beatPos], tuplet: true ));
					i = j;
				} { out = out.add(rec); i = i + 1 };
			};
			out;
		};
```

- [ ] **Step 3c: Piece 2 — route the `\normal` emit loop through `wrapTuplets`.** Replace the inner `pieces.do` block + the `measures[...] = ...add(...)` inside the `\normal` `while` (`:227-235`) so it builds fragment-records (carrying `tup`) then wraps them:

```supercollider
						while { remaining > eps } {
							var take = (bb - pos).min(remaining), crosses = remaining > ((bb - pos) + eps);
							var lastFrag = crosses.not, pieces = meterPieces.(pos, take, ev[\rest], pmeter), subpos = pos, frecs = [];
							pieces.do({ |pc, c|
								var isFirst = firstFrag and: { c == 0 }, isLast = lastFrag and: { c == (pieces.size - 1) }, tie = nil;
								if (ev[\rest].not and: { (isFirst and: { isLast }).not }) {
									tie = isFirst.if({"i"},{ isLast.if({"t"},{"m"}) });
								};
								frecs = frecs.add(( str: meiElement.(ev, pc[0], pc[1], tie, k), md: pc[0].asInteger,
									rest: ev[\rest], beatPos: subpos, tup: pc[3] ));
								subpos = subpos + pc[2];
							});
							wrapTuplets.(frecs).do({ |r| measures[measures.size-1] = measures[measures.size-1].add(r) });
							pos = pos + take; remaining = remaining - take; firstFrag = false;
							if ((bb - pos) < eps) { measures = measures.add([]); pos = 0.0 };
						};
```

(The tie logic is unchanged; only the records now carry `tup` and are passed through `wrapTuplets`. A `nil`-tuplet fragment yields a record identical to before, so plain/dyadic output is byte-for-byte unchanged.)

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q`
Expected: `test_tuplet_completion.py` (2 passed) AND the full `panola_mei` suite green — `test_tuplets` (complete tuplets/`with_rest`/`sixeighths`/`mixed`/`quintuplet`/`quarter3`/`then_plain`/`incomplete`), `test_asmei`, `test_meter_notation`, `test_expression`, `test_slurs` all unchanged. If `test_tuplets::test_tuplet_edge_cases` changed a `>= 1`/`== 1` count, re-derive: cascade fragments becoming brackets can only *raise* tuplet counts where the test uses `>=`; the `then_plain` `== 1` case has a *complete* triplet (dyadic follow-on, no cascade) so it must stay 1 — if it changed, investigate.

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): bracket split fragments in PanolaMEI (meterPieces keeps tuplet; wrapTuplets)

Piece 1+2 of tuplet completion: meterPieces no longer drops the spelling's
tuplet descriptor, and the \\normal-path emission groups consecutive same-ratio
fragments into <tuplet> brackets. Fixes the SP2b tuplet-drop bug. Complete *m/d
tuplets keep their atomic path; nil-tuplet output is byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_mei/test_tuplet_completion.py
git commit -m "test(panola_mei): split fragments render inside a <tuplet>; plain/complete unchanged

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Piece 3 — complete an incomplete tuplet by splitting the follower

This is the intricate task; **let the tests define the exact output** and iterate. The idea: when a `*m/d` run is incomplete, spell its remainder as tuplet member(s), merge them with the unit's original members into one bracket, and tie the donor note out.

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (restructure the `groupEvents` iteration; add the completion path)
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_tuplet_completion.py`

- [ ] **Step 1: Add the failing tests**

```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_trailing_incomplete_triplet_stays_partial():
    # c5_8*2/3 d5 : 2 of 3 triplet-eighths, then NOTHING follows. music21 leaves a trailing incomplete
    # tuplet partial (it never fabricates a rest), so this stays a 2-note bracket + the warning.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5")], "4/4", \\Cmajor, [\\treble], nil)')
    body = mei.split("</tuplet>")[0]
    assert body.count("<note") == 2 and body.count("<rest") == 0, mei   # partial: 2 notes, no fabricated rest
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_rest_follower_completes_by_splitting_the_rest():
    # c5_8*2/3 d5 r_2 : a rest follows, so completion SPLITS the existing rest (music21-faithful) -> the
    # first bracket gains a tuplet rest member (2 notes + 1 rest); the remainder continues.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 r_2")], "4/4", \\Cmajor, [\\treble], nil)')
    body = mei.split("</tuplet>")[0]
    assert body.count("<note") == 2 and body.count("<rest") == 1, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_incomplete_triplet_then_note_ties_into_the_bracket():
    # c5_8*2/3 d5 c5_4 : the quarter's leading third completes the triplet as a tied triplet-eighth INSIDE
    # the bracket; the remainder (2/3 beat, non-dyadic) becomes its own triplet-quarter bracket, tied.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 c5_4")], "4/4", \\Cmajor, [\\treble], nil)')
    first = mei.split("</tuplet>")[0]
    assert first.count("<note") == 3, mei                        # c5, d5, + tied completing e-note
    assert 'tie="i"' in first, mei                               # the completing member ties out
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_tuplet_completion.py -q`
Expected: both new tests FAIL — the incomplete triplet is still emitted as a 2-note partial bracket (`ends_mid` behaviour) with a warning.

- [ ] **Step 3: Implement the completion.**

**3a. Convert the unit iteration to an indexed loop with lookahead.** Replace `groupEvents.(events).do({ |unit| … })` (`:200`) with:

```supercollider
				var units = groupEvents.(events), ui = 0, containers = [0.25, 0.5, 1.0, 2.0, 4.0];
				while { ui < units.size } {
					var unit = units[ui], consumedDonor = false;
					// the 3b branch replaces the current `groupEvents.(events).do` body (`:201-239`),
					// still using `unit`
					ui = consumedDonor.if({ ui + 2 }, { ui + 1 });
				};
```

Keep the existing `\tuplet`-complete and `\normal` bodies exactly as they are (only the outer iteration and the incomplete-tuplet branch change). Only an **incomplete `\tuplet`** unit takes the new path.

**3b. Completion path** — inside the loop, before the existing `\tuplet` emission, branch on incomplete + donor:

```supercollider
					if ((unit[\kind] == \tuplet) and: { unit[\complete].not }) {
						var container = containers.detect({ |cc| cc >= (unit[\beats] - eps) }),
							remainder = container - unit[\beats],
							donor = ((ui + 1) < units.size).if({ units[ui + 1] }, { nil }),
							inBar = container.notNil and: { (pos + container) <= (bb + eps) },  // stays in this bar
							// canDonor: split a long-enough note/rest follower into the bracket (music21's rule
							// — the follower must EXCEED the remainder). Completion NEVER fabricates a rest; a
							// trailing / no-donor / too-short-follower incomplete tuplet stays warned + partial,
							// exactly as music21 leaves it. (The canRest line below is dead — remove it in code.)
							canDonor = inBar and: { donor.notNil } and: { donor[\kind] == \normal }
								and: { (donor[\ev][\beats] + eps) >= remainder },
							canRest = inBar and: { canDonor.not } and: { donor.isNil or: { donor[\ev][\rest] == true } };
						if (canDonor) {   // NOTE: canRest removed — completion never fabricates a rest (music21)
							var frecs = [], compSp = PanolaDurationSpeller.spell(PanolaRational.fromFloat(remainder)),
								dev = donor[\ev], donorRest = dev[\rest],
								hasRemainder = (donor[\ev][\beats] - remainder) > eps, sub = pos;
							// (i) the unit's original members, at their written values, as tuplet-ratio records
							unit[\members].do({ |mev|
								frecs = frecs.add(( str: meiElement.(mev, mev[\meidur], mev[\dots], nil, k),
									md: mev[\meidur].asInteger, rest: mev[\rest], beatPos: sub,
									tup: ( num: unit[\num], numbase: unit[\numbase] ) ));
								sub = sub + mev[\beats];
							});
							// (ii) the completing member(s) from the donor's leading `remainder`. These + the
							// donor's remainder form one tied note (a note); a rest ties nothing.
							compSp[\components].do({ |x, ci|
								var hasPrev = (ci > 0),
									hasNext = (ci < (compSp[\components].size - 1)) or: { hasRemainder },
									ctie = donorRest.if({ nil }, {
										(hasPrev and: { hasNext }).if({ "m" },
											{ hasPrev.if({ "t" }, { hasNext.if({ "i" }, { nil }) }) }) });
								frecs = frecs.add(( str: meiElement.(dev, x[\meidur], x[\dots], ctie, k),
									md: x[\meidur].asInteger, rest: donorRest, beatPos: sub,
									tup: ( num: unit[\num], numbase: unit[\numbase] ) ));
								sub = sub + x[\ql].asFloat;
							});
							wrapTuplets.(frecs).do({ |r| measures[measures.size-1] = measures[measures.size-1].add(r) });
							pos = pos + container;
							if ((bb - pos) < eps) { measures = measures.add([]); pos = 0.0 };
							// (iii) reduce the donor to its remainder at the container boundary; tie it in if a note
							if (hasRemainder) {
								units[ui + 1] = ( kind: \normal, ev: dev.copy.put(\beats, dev[\beats] - remainder)
									.put(\tieIn, donorRest.not) );
							} { consumedDonor = true };
						} {
							// unchanged fallback: the current incomplete-tuplet warn (`:213`) + `tupletMEI`
							// emit + pos advance (`:215-218`)
						};
					} {
						// unchanged: the current complete-`\tuplet` emit (`:201-218`) and the `\normal`
						// body (`:219-239`), the latter with Task 1's `wrapTuplets` + 3c's tie change
					};
```

**3c. Honor `tieIn` in the `\normal` emit loop.** So the donor's remainder continues the tie from its completing member, change the tie derivation (Task 1's block) to treat an incoming tie:

```supercollider
								var isFirst = firstFrag and: { c == 0 }, isLast = lastFrag and: { c == (pieces.size - 1) },
									hasPrev = (ev[\tieIn] == true) or: { isFirst.not }, hasNext = isLast.not, tie = nil;
								if (ev[\rest].not) {
									tie = (hasPrev and: { hasNext }).if({ "m" },
										{ hasPrev.if({ "t" }, { hasNext.if({ "i" }, { nil }) }) });
								};
```

(For `tieIn = nil/false` this is identical to the old `i/m/t`-or-nil logic; with `tieIn` the first fragment becomes `m`/`t`, chaining from the completing member.)

Notes for the implementer:
- `PanolaDurationSpeller.spell(PanolaRational.fromFloat(remainder))` yields the completing member(s) at the tuplet ratio (`spell(1/3)`→`eighth[3:2]`, `spell(2/3)`→`quarter[3:2]`). Their `tup` is forced to the unit's `num/numbase` so they join the unit's bracket (the inferred ratio matches, but pinning it guarantees one merged bracket).
- The donor's remainder is emitted by the **next** loop iteration through the normal path (now Task-1-bracketing), so a non-dyadic remainder self-brackets and the `tieIn` chains the tie.
- If `canComplete` is false (no donor, donor too short, or completion would cross the barline), fall back to the **existing** partial-bracket + warning — that path is unchanged.

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q`
Expected: the two Task-2 tests pass, Task-1's two pass, and the full suite stays green — **`test_tuplets` byte-identical** (complete units never enter the completion branch; `with_rest`/`sixeighths`/`mixed`/`quintuplet`/`quarter3`/`then_plain` are all complete or dyadic-follow). Iterate on the `<note>`/`<rest>`/`tie` counts until the Task-2 assertions hold; if a count is off, dump the MEI (`_mei(...)`) and inspect the bracket contents.

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): complete incomplete tuplets by splitting the follower (music21-style)

Piece 3: an incomplete *m/d run spells its remainder as tuplet member(s) that
merge into the bracket; a donor note ties out, a donor rest contributes a rest
member. Retires the incomplete-tuplet warning for the completable cases.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_mei/test_tuplet_completion.py
git commit -m "test(panola_mei): incomplete triplet completes with a rest / ties a note into the bracket

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Whelk docs refresh + regenerate schelp

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (doc comment only)
- Regenerate: `…/panola/HelpSource/Classes/PanolaMEI.schelp`

- [ ] **Step 1: Update the whelk prose.** In `PanolaMEI`'s `[general]`/`[classmethod.scoreAsMEI]` blocks, note that incomplete `teletype::*m/d::` tuplets are now completed by splitting the following note/rest into the bracket (music21-style), linking `link::Classes/PanolaMeterSplitter::`/`link::Classes/PanolaDurationSpeller::`. Whelk-safe: `strong::`/`teletype::`/`link::` only, no `## … || …`, balanced `/* */`. Do NOT document the inner closures (`wrapTuplets`, `meterPieces` are locals, not methods).

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
Expected: schelp present; `tools/panola_mei` all green; only `PanolaMEI.sc` (prose) + `PanolaMEI.schelp` changed (other 7 schelp byte-identical).

- [ ] **Step 4: Commit** (Panola quark)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "docs(panola): PanolaMEI whelk doc notes music21-style tuplet completion; regen schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q` → all green (Task 1's 2 + Task 2's 2 + `test_tuplets` + `test_asmei` + `test_meter_notation` + `test_expression` + `test_slurs`).
- [ ] Full regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration tools/panola_mei tools/msscore/test_midi_routing.py -q` → SP1/SP2a/SP2b/msscore unaffected.
- [ ] **Byte-identical check:** dump `test_tuplets`' `triplet`/`with_rest`/`sixeighths`/`mixed`/`quintuplet`/`quarter3`/`then_plain` MEI before (HEAD `661a69f`-era) and after; confirm the `<tuplet>`/`<note>` structure is unchanged for these already-correct inputs.

## Notes for the implementer

- **The hard invariant is byte-identity for complete tuplets.** They never enter the completion branch (Task 2 gates on `unit[\complete].not`) and don't go through `meterPieces` (they use `tupletMEI`), so the only risk is Task 1's `\normal`-path refactor changing `nil`-tuplet output — verify a plain score is unchanged first (Task 1 Step 4).
- **`tup` equality** must be compared field-wise (`[\num]`/`[\numbase]`), not `==` on the Event (`wrapTuplets`).
- **Ties chain through brackets** — a tie attribute is on the `<note>`, independent of the `<tuplet>` wrapper; `wrapTuplets` only regroups records, it never touches their `str`/tie.
- **Fallback stays warned; never fabricate a rest.** No follower (a trailing incomplete tuplet), a too-short follower, or would-cross-barline keeps the existing partial-bracket + warning — do not delete that code. music21 leaves a trailing incomplete tuplet partial; SP2c does NOT invent a rest to pad it.
- **One completion path (`canDonor`).** Completion fires only when there is an adjacent following note/rest to split. A donor **note** ties out; a donor **rest** contributes rest member(s) by splitting the existing rest (`donorRest` true, no tie). There is no rest-fabrication path.
- **Whelk docs (Task 3)** must be whelk-safe or the class library won't compile and the whole suite fails.
