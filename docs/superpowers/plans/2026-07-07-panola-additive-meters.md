# Panola additive-meter grouping (SP2e v1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Accept an additive meter string (`"2+2+3/8"`) so irregular meters engrave with their grouping — meter-aware splitting at group boundaries, beaming per group, and an additive meter signature — per `docs/superpowers/specs/2026-07-07-panola-additive-meters-design.md`.

**Architecture:** In `PanolaMEI.sc`'s `scoreAsMEI`, add a `parseMeter` helper returning a self-contained meter **descriptor** `( count, num, den, groups, bb, groupStarts, pmeter )`, and route every meter-dependent step through it: `voiceToMeasures` gets `m[\bb]`/`m[\pmeter]` (splitting via `PanolaMeter`'s additive group boundaries, already built in SP2a); `beamMeasure` is generalized from a uniform `groupBeats` to explicit `m[\groupStarts]`; the `<scoreDef>` emits `meter.count = m[\count]`. Plain meters produce a descriptor identical in effect to today's code (byte-identical output). Per the spec's forward-compatibility rule, the descriptor is passed as a parameter everywhere so a future mid-piece meter change is a per-measure descriptor lookup, not a rewrite.

**Tech Stack:** SuperCollider (sclang); Python pytest driving sclang → MEI → Verovio (`tools/panola_mei/`, `render_props`); whelk → schelp via `gendoc.bat`.

---

## Repositories & branches

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch **master**; bash path `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola`). `PanolaMEI.sc` + regenerated HelpSource commit here.
- **MusicScene repo** — `D:\Projects\MusicScene` (branch **feature/panola-additive-meters**). Tests commit here.

sclang `C:\Program Files\SuperCollider-3.14.1\sclang.exe`. Editing `PanolaMEI.sc` recompiles next run; syntax error → MEI fails; runtime error → 120s hang (run the temp `.scd` by hand, **real Windows paths** not `/tmp`). Stuck sclang: PowerShell `Get-Process sclang | Stop-Process -Force`. TAB-indented.

## Current code (reference)

- `barBeats` (`:188`): `{ |m| var p = m.split($/); p[0].asInteger * (4.0 / p[1].asInteger) }` — breaks on `"2+2+3"` (`.asInteger` reads `2`). **Superseded** by `parseMeter` and removed.
- `beamMeasure` (`:400`): beams beamable runs (`rest.not and md >= 8`) sharing `(beatPos / groupBeats).floor`.
- The body meter setup (`:509-514`): `bb = barBeats.(meter); mp = meter.split($/); groupBeats = ((den==8) and (num%3==0)) ? 1.5 : 1.0; pmeter = PanolaMeter(mp[0].asInteger, mp[1].asInteger);` then `voiceToMeasures.(…, bb, key, pmeter)` (`:515`), `emptyRest.(bb)` (`:517`), `beamMeasure.(…, groupBeats)` (`:520`).
- The meter signature (`:538`): `"<scoreDef meter.count=\"" ++ mp[0] ++ "\" meter.unit=\"" ++ mp[1] ++ "\" …"`.
- `PanolaMeter(num, den, groups)` already builds additive group boundaries (strength 75) when `groups` is non-nil (SP2a); `nil` groups → its simple/compound path.

---

### Task 1: parseMeter descriptor + thread it (splitting, beaming, signature)

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc`
- Create/Test: `D:\Projects\MusicScene\tools\panola_mei\test_additive_meters.py`

- [ ] **Step 1: Write the failing tests** — create `test_additive_meters.py`:

```python
"""SP2e: additive meter grouping ("2+2+3/8") -> group-boundary splitting, per-group beaming, additive sig.
Generates MEI via sclang, asserts on the MEI XML, renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_additive_meters.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(panola, meter):
    d = tempfile.mkdtemp(prefix="panola_add_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        expr = ('Panola.scoreAsMEI([Panola("%s")], "%s", \\Cmajor, [\\treble], nil)' % (panola, meter))
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_additive_meter_signature_and_barlength():
    # seven eighths fill exactly one 2+2+3/8 bar (3.5 quarter-beats); the signature is additive.
    mei = _mei("c5_8 d5 e5 f5 g5 a5 b5", "2+2+3/8")
    assert 'meter.count="2+2+3" meter.unit="8"' in mei, mei
    assert mei.count("<measure ") == 1, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_additive_beaming_2_2_3():
    # a bar of seven eighths beams 2 + 2 + 3 -> three <beam> groups, not a uniform grouping.
    mei = _mei("c5_8 d5 e5 f5 g5 a5 b5", "2+2+3/8")
    assert mei.count("<beam>") == 3, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_additive_splitting_at_group_boundary():
    # in 2+2+3/8, group boundaries sit at beats 1.0 and 2.0 (strength 75). A quarter starting on the
    # off-beat of group 1 (onset 0.5, weak) crosses the 1.0 boundary -> two tied eighths; a quarter that
    # starts on the group-3 boundary (onset 2.0) spans only weaker subdivisions -> stays a quarter.
    mei = _mei("c5_8 d5_4 f5_8 g5_4 a5_8", "2+2+3/8")
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei          # d5_4 split+tied at the group boundary
    # g5_4 (onset 2.0) stays a single quarter (not over-split within its group)
    assert re.search(r'<note dur="4"[^>]*pname="g"', mei), mei
    assert render_props(mei)["ok"], mei
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei/test_additive_meters.py -q`
Expected: FAIL — today `"2+2+3/8"` parses the numerator as `2` (`barBeats`/`mp[0].asInteger`), so the bar length, signature, splitting, and beaming are all wrong (likely a broken/short bar).

- [ ] **Step 3a: Add `parseMeter`.** Insert immediately after `barBeats` (`:188`) — then **delete the `barBeats` definition** (it is superseded and is removed in Step 3c's body edit):

```supercollider
		// parse a meter string into a self-contained descriptor. An additive numerator ("2+2+3/8") carries
		// groups; a plain one ("7/8") has groups nil. Every meter-dependent step consumes THIS descriptor
		// (passed as a parameter), so a future mid-piece meter change is a per-measure descriptor lookup,
		// not a rewrite. count = the display numerator; num = its sum; bb = bar length in quarterLength;
		// groupStarts = cumulative beat positions where each beam/metric group begins.
		var parseMeter = { |m|
			var parts = m.split($/), numStr = parts[0], den = parts[1].asInteger, unit = 4.0 / parts[1].asInteger;
			var groups = (numStr.indexOf($+).notNil).if({ numStr.split($+).collect({ |g| g.asInteger }) }, { nil });
			var num = groups.notNil.if({ groups.sum }, { numStr.asInteger });
			var bb = num * unit, starts;
			groups.notNil.if({
				starts = [0.0];
				groups.drop(-1).do({ |g| starts = starts.add(starts.last + (g * unit)) });
			}, {
				var gb = ((den == 8) and: { (num % 3) == 0 }).if({ 1.5 }, { 1.0 });
				starts = (0..(((bb / gb).ceil.asInteger) - 1)).collect({ |kk| kk * gb });
			});
			( count: numStr, num: num, den: den, groups: groups, bb: bb, groupStarts: starts,
				pmeter: PanolaMeter(num, den, groups) );
		};
```

- [ ] **Step 3b: Generalize `beamMeasure`** — change its signature and grouping from a uniform `groupBeats` to a `groupStarts` list. Replace the head of `beamMeasure` (`:400-406`):

```supercollider
		var beamMeasure = { |records, groupStarts|
			var result = "", i = 0, eps = 1e-6,
				groupOf = { |bp| (groupStarts.count({ |s| s <= (bp + eps) }) - 1) };
			while { i < records.size } {
				var rec = records[i], beamable = rec[\rest].not and: { rec[\md] >= 8 };
				if (beamable) {
					var grp = groupOf.(rec[\beatPos]), run = [rec], j = i + 1;
					while { (j < records.size) and: { records[j][\rest].not and: { (records[j][\md] >= 8) and: { groupOf.(records[j][\beatPos]) == grp } } } } {
						run = run.add(records[j]); j = j + 1;
					};
```
(the rest of `beamMeasure` — the `if (run.size >= 2) …` emit and the `else` branch — is unchanged.)

- [ ] **Step 3c: Rewrite the body meter setup** (`:509-520`) to use the descriptor:

```supercollider
		var perVoice, nm, m, body = "";
		clefs = clefs ? voices.collect({ \treble });
		m = parseMeter.(meter);
		perVoice = voices.collect({ |p| voiceToMeasures.(annotateExpression.(eventsOf.(p)), m[\bb], key, m[\pmeter]) });
		nm = perVoice.collect({ |v| v[\measures].size }).maxItem;
		perVoice = perVoice.collect({ |v| while { v[\measures].size < nm } { v[\measures] = v[\measures].add(emptyRest.(m[\bb])) }; v });
		nm.do({ |i|
			body = body ++ "<measure n=\"" ++ (i+1) ++ "\">";
			perVoice.do({ |v, s| body = body ++ "<staff n=\"" ++ (s+1) ++ "\"><layer n=\"1\">" ++ beamMeasure.(v[\measures][i], m[\groupStarts]) ++ "</layer></staff>" });
```
(the dynam/slur emission and `</measure>` inside the `nm.do` loop are unchanged; only the `var` line, the setup lines, and the `beamMeasure` call change. Remove `bb`, `mp`, `pmeter`, `groupBeats` from the removed setup.)

- [ ] **Step 3d: Additive meter signature** (`:538`) — emit the descriptor's count + den:

```supercollider
			++ "<scoreDef meter.count=\"" ++ m[\count] ++ "\" meter.unit=\"" ++ m[\den] ++ "\" key.sig=\"" ++ keyToSig.(key) ++ "\">"
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q`
Expected: `test_additive_meters` (3 passed) AND the full `panola_mei` suite green. If any existing test changed, it's a byte-identity break — investigate (Step 5).

- [ ] **Step 5: Verify byte-identity for existing meters**

Dump MEI for a `4/4` score (`c5_4 e5 g5 a5`), `3/4` (`c5_4 e5 g5`), `6/8` (`c5_8 d5 e5 f5 g5 a5`), and a bare `7/8` (`c5_8 d5 e5 f5 g5 a5 b5`) under HEAD-before (`git show <old>:Classes/PanolaMEI.sc`) vs after; confirm **byte-identical** (same `meter.count`, same `<beam>` grouping, same splitting). `groupOf` must reduce to the old `(beatPos/groupBeats).floor` for these (it does: uniform `groupStarts` = `[0, gb, 2gb, …]`).

- [ ] **Step 6: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(panola): additive meters (2+2+3/8) — grouped splitting, beaming, meter sig

parseMeter returns a self-contained meter descriptor (count/num/den/groups/bb/
groupStarts/pmeter) consumed as a parameter everywhere (so mid-piece meter
changes stay a future per-measure lookup, not a rewrite). Additive numerators
thread groups into PanolaMeter (SP2a splitting), beam per group (groupStarts),
and emit meter.count=\"2+2+3\". Plain meters byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/panola_mei/test_additive_meters.py
git commit -m "test(panola_mei): additive 2+2+3/8 signature, 2+2+3 beaming, group-boundary split

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Whelk docs refresh + regenerate schelp

**Files:**
- Modify: `…/panola/Classes/PanolaMEI.sc` (doc comment only)
- Regenerate: `…/panola/HelpSource/Classes/PanolaMEI.schelp`

- [ ] **Step 1: Update the whelk prose.** In `PanolaMEI`'s `[general]` / `[classmethod.scoreAsMEI]` blocks, note that the `meter` argument accepts an **additive numerator** (`teletype::"2+2+3/8"::`) that groups the bar — splitting at the group boundaries, beaming per group, and an additive meter signature — while a plain `teletype::"7/8"::` stays ungrouped. Document the `meter` string form in the `scoreAsMEI` args prose. Whelk-safe: `strong::`/`teletype::`/`link::` only, no `## … || …`, balanced `/* */`. Do NOT document inner closures.

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
Expected: schelp present; `tools/panola_mei` all green; only `PanolaMEI.sc` (prose) + `PanolaMEI.schelp` changed; the `.sc` diff is doc-comment-only (`git diff --numstat`, all inside `/* */`).

- [ ] **Step 4: Commit** (Panola quark)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "docs(panola): PanolaMEI whelk doc notes additive meter strings; regen schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q` → all green (additive tests + `test_asmei` + `test_meter_notation` + `test_tuplets` + `test_tuplet_completion` + `test_barline_tuplets` + `test_degenerate_tuplets` + `test_expression` + `test_slurs`).
- [ ] Full regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_duration tools/panola_mei tools/msscore/test_midi_routing.py -q`.
- [ ] Spot-check: dump the `"2+2+3/8"` MEI and eyeball the `2+2+3` signature, the 2+2+3 beam grouping, and the group-boundary tie.

## Notes for the implementer

- **Byte-identity is the safety line.** For a plain meter, `parseMeter` must yield a descriptor whose `bb`, `groupStarts`, `pmeter`, and `count` reproduce today's behavior exactly. Verify `4/4`/`3/4`/`6/8`/`7/8` byte-identical (Step 5) before trusting the additive path.
- **`groupOf` vs the old `.floor`.** For uniform `groupStarts = [0, gb, 2gb, …]`, `groupStarts.count { s <= bp } - 1 == (bp/gb).floor`. Keep the `+ eps` so a note exactly on a boundary lands in the new group (matches the old floor at integer multiples).
- **The descriptor is passed as a parameter** to `voiceToMeasures` (`m[\bb]`, `m[\pmeter]`), `emptyRest` (`m[\bb]`), and `beamMeasure` (`m[\groupStarts]`) — do NOT reintroduce module-level `bb`/`groupBeats` globals; that's the forward-compatibility constraint (mid-piece meter changes must stay a clean future addition).
- **`PanolaMeter` already does additive splitting** — you are only *supplying* it the groups; do not change `PanolaMeter`.
- **Whelk docs (Task 2)** must be whelk-safe or the class library won't compile and the whole suite fails.
