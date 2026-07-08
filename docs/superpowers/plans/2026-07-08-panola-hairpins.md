# Panola Hairpins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `@hairpin` property renders MEI `<hairpin form="cres|dim" tstamp tstamp2 staff/>` — a spanning crescendo/decrescendo mark, tracked exactly like a slur but with a direction.

**Architecture:** Mirror the existing slur machinery in `PanolaMEI.sc`. Add a per-note `@hairpin` value (`eventsOf`), a parallel `openHairpin`/`hairpins`/`applyHairpin` tracker inside `voiceToMeasures` invoked at every site `applySlur` is called, and a parallel `<hairpin>` emit block in the output loop. No parser change (values are plain words: `cresc`/`dim`/`end`/`endcresc`/`enddim`). MSScore inherits it for free.

**Tech Stack:** SuperCollider (`PanolaMEI.sc`), Python + pytest + sclang + Verovio (`tools/panola_mei/`), whelk/`gendoc.bat`, a SuperCollider `.scd` example.

---

## Repos, branches & conventions

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch `master`). `.sc` classes + `HelpSource` schelp. **CRLF line endings, TAB indentation.**
- **MusicScene** — `D:\Projects\MusicScene` (create branch `feature/panola-hairpins` before editing; never work on `main`). Python tests, example, CHANGELOG, BACKLOG.

Conventions:
- `.sc` edits must preserve **CRLF + tabs**. Read each anchor exactly before editing; verify with `cat -A` that new lines end `\r$` and indent with tabs (not spaces). If an `Edit` literal won't match (CRLF/tab), do a byte-anchored replacement (e.g. a small Python script anchoring on a unique substring) and confirm a single occurrence.
- Python tests spawn a fresh `sclang` per run, so `.sc` edits are picked up with no manual recompile. Use `py` (not `python`). Bash tool = Git Bash.
- Run only `tools/panola_mei/ tools/msscore/` (never `tools/` alone).
- **Commit only after the user confirms** (executing this plan is such confirmation). End commit messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

Reference — the current slur emit block (`PanolaMEI.sc` ~lines 638–645), which the hairpin block mirrors:

```
			perVoice.do({ |v, s|
				v[\slurs].select({ |sl| sl[\startMeasure] == (i+1) }).do({ |sl|
					var t1 = sl[\startTstamp], t2 = sl[\endTstamp], dm = sl[\endMeasure] - sl[\startMeasure];
					var t1s = (t1.frac < 1e-6).if({ t1.asInteger.asString }, { t1.round(0.0001).asString });
					var t2s = (t2.frac < 1e-6).if({ t2.asInteger.asString }, { t2.round(0.0001).asString });
					body = body ++ "<slur tstamp=\"" ++ t1s ++ "\" tstamp2=\"" ++ dm ++ "m+" ++ t2s ++ "\" staff=\"" ++ (s+1) ++ "\"/>";
				});
			});
```

---

## Task 1: `render_check` — count hairpins

**Files:**
- Modify: `D:\Projects\MusicScene\tools\panola_mei\render_check.py`
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_hairpins.py` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/panola_mei/test_hairpins.py` with a MINIMAL-MEI count test (modeled on `test_slurs.py`):

```python
"""Hairpin tests for Panola.scoreAsMEI (PanolaMEI). sclang -> MEI -> Verovio render + assert.
Run:  py -m pytest tools/panola_mei/test_hairpins.py -q   (skips if sclang absent)
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
  '<hairpin form="cres" tstamp="1" tstamp2="0m+4" staff="1"/></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_hairpin():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["hairpins"] == 1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `py -m pytest tools/panola_mei/test_hairpins.py::test_render_props_counts_hairpin -q`
Expected: FAIL with `KeyError: 'hairpins'` (render_props has no such key yet).

- [ ] **Step 3: Add the count to `render_check.py`**

In `tools/panola_mei/render_check.py`, in the dict returned by `render_props`, next to the `"slurs": mei.count("<slur ")` line add:

```python
        "hairpins": mei.count("<hairpin "),
```

- [ ] **Step 4: Run it to verify it passes**

Run: `py -m pytest tools/panola_mei/test_hairpins.py::test_render_props_counts_hairpin -q`
Expected: PASS (Verovio renders the `<hairpin>` and the count is 1).

- [ ] **Step 5: Commit**

```bash
git -C "D:/Projects/MusicScene" add tools/panola_mei/render_check.py tools/panola_mei/test_hairpins.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): render_check counts <hairpin>; MINIMAL hairpin renders

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `PanolaMEI.sc` — emit `<hairpin>` from `@hairpin`

The core. Every change parallels the slur code. **Read each anchor in the file before editing** (CRLF/tabs).

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaMEI.sc`
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_hairpins.py`

- [ ] **Step 1: Write the failing behavioral tests**

Append to `tools/panola_mei/test_hairpins.py`:

```python
from tools.panola_mei.test_expression import _dump, SCLANG

CASES = {
  "within":    r'Panola.scoreAsMEI([Panola("c5_4@hairpin^cresc^ d5 e5 f5@hairpin^end^ g5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "dim":       r'Panola.scoreAsMEI([Panola("c5_4@hairpin^decrescendo^ d5 e5 f5@hairpin^end^ g5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "crossbar":  r'Panola.scoreAsMEI([Panola("c5_4@hairpin^cresc^ d5 e5 f5 g5@hairpin^end^ a5 b5 c6")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "messa":     r'Panola.scoreAsMEI([Panola("c5_4@hairpin^cresc^ d5 e5@hairpin^enddim^ f5 g5@hairpin^end^ a5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "coexist":   r'Panola.scoreAsMEI([Panola("c5_4@dyn^p^@slur^start^@hairpin^cresc^ d5 e5 f5@slur^end^@hairpin^end^ g5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "unmatched": r'Panola.scoreAsMEI([Panola("c5_4 d5@hairpin^end^ e5 f5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "twovoice":  r'Panola.scoreAsMEI([Panola("c5_4 d5 e5 f5"), Panola("c3_4@hairpin^cresc^ e3 g3 c4@hairpin^end^")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble, \bass], nil)',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_hairpins():
    outdir = tempfile.mkdtemp(prefix="panola_hairpin_")
    try:
        _dump(outdir, CASES)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in CASES}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    # basic crescendo within a bar
    assert props["within"]["hairpins"] == 1
    assert '<hairpin form="cres" tstamp="1" tstamp2="0m+4" staff="1"/>' in meis["within"]
    # decrescendo via synonym
    assert '<hairpin form="dim" tstamp="1" tstamp2="0m+4" staff="1"/>' in meis["dim"]
    # crossing a barline
    assert props["crossbar"]["hairpins"] == 1
    assert '<hairpin form="cres" tstamp="1" tstamp2="1m+1" staff="1"/>' in meis["crossbar"]
    # messa di voce: cres then dim sharing the boundary note (beat 3)
    assert props["messa"]["hairpins"] == 2
    assert '<hairpin form="cres" tstamp="1" tstamp2="0m+3" staff="1"/>' in meis["messa"]
    assert '<hairpin form="dim" tstamp="3" tstamp2="1m+1" staff="1"/>' in meis["messa"]
    # a note may carry @dyn, @slur AND @hairpin
    assert props["coexist"]["hairpins"] == 1 and props["coexist"]["slurs"] == 1 and props["coexist"]["dynam"] >= 1
    # end with nothing open -> no hairpin (warned)
    assert props["unmatched"]["hairpins"] == 0
    # hairpin on the lower staff
    assert props["twovoice"]["hairpins"] == 1 and 'form="cres"' in meis["twovoice"] and 'staff="2"' in meis["twovoice"]
```

- [ ] **Step 2: Run to verify they fail**

Run: `py -m pytest tools/panola_mei/test_hairpins.py::test_hairpins -q`
Expected: FAIL — `@hairpin` isn't handled, so no `<hairpin>` is emitted (`hairpins == 0`, string asserts fail). If SKIPPED (sclang absent), STOP and report BLOCKED.

- [ ] **Step 3: `eventsOf` — read the per-note `@hairpin` value**

Find the `eventsOf` closure (~line 585). After the line that sets `slurs` and reads properties, mirror the slur extraction. The current lines are:

```
			var slurs = panola.customPropertyPattern("slur", "").asStream.all;
			var clefsP = panola.customPropertyPattern("clef", "").asStream.all;
```

Add after the `slurs` line:

```
			var hairpinsP = panola.customPropertyPattern("hairpin", "").asStream.all;
```

And in the per-note record block, the current line is:

```
				e[\dyn] = dyns[i].asString; e[\art] = arts[i].asString; e[\slur] = slurs[i].asString;
				e[\clef] = clefsP[i].asString;
```

Change the second line to also set `hairpin`:

```
				e[\clef] = clefsP[i].asString; e[\hairpin] = hairpinsP[i].asString;
```

- [ ] **Step 4: `voiceToMeasures` — add the hairpin tracker locals**

The current locals line (~249) is:

```
			var measures = [[]], pos = 0.0, eps = 1e-6, dynams = [], openSlur = nil, slurs = [], applySlur;
```

Add hairpin locals:

```
			var measures = [[]], pos = 0.0, eps = 1e-6, dynams = [], openSlur = nil, slurs = [], applySlur;
			var openHairpin = nil, hairpins = [], applyHairpin;
```

- [ ] **Step 5: Define `applyHairpin` after `applySlur`**

Immediately after the `applySlur = { ... };` closure (it ends with the line `			};` right before `units = groupEvents.(events);` ~line 280), insert the `applyHairpin` closure (real tabs, one tab less than the case bodies as in `applySlur`):

```
			// pair @hairpin^cresc/dim/end/endcresc/enddim^ into hairpin markers (form cres|dim). one open
			// hairpin at a time (like slurs); endcresc/enddim close the open one and open a new one of that
			// form at the SAME note (messa di voce). m/ts = 1-based measure and beat. warn + recover.
			applyHairpin = { |hpVal, m, ts|
				var formOf = { |v|
					case
					{ (v == "cresc") or: { v == "crescendo" } } { "cres" }
					{ (v == "dim") or: { v == "decresc" } or: { v == "decrescendo" } or: { v == "diminuendo" } } { "dim" }
					{ true } { nil };
				};
				var closeOpen = {
					if (openHairpin.notNil) {
						hairpins = hairpins.add(( startMeasure: openHairpin[\measure], startTstamp: openHairpin[\tstamp],
							endMeasure: m, endTstamp: ts, form: openHairpin[\form] ));
						openHairpin = nil;
					};
				};
				case
				{ hpVal == "end" } {
					if (openHairpin.isNil) { "PanolaMEI: hairpin end with no open hairpin; ignored".warn };
					closeOpen.value;
				}
				{ (hpVal == "endcresc") or: { hpVal == "enddim" } } {
					if (openHairpin.isNil) { "PanolaMEI: hairpin endcresc/enddim with no open hairpin; only opening a new one".warn };
					closeOpen.value;
					openHairpin = ( measure: m, tstamp: ts, form: (hpVal == "endcresc").if({ "cres" }, { "dim" }) );
				}
				{ formOf.(hpVal).notNil } {
					if (openHairpin.notNil) { "PanolaMEI: hairpin start while a hairpin is open; the previous one is dropped".warn };
					openHairpin = ( measure: m, tstamp: ts, form: formOf.(hpVal) );
				}
				{ true } { if (hpVal != "") { ("PanolaMEI: unknown hairpin value '" ++ hpVal ++ "'").warn } };
			};
```

- [ ] **Step 6: Thread `applyHairpin` through every slur call site**

There are five sites. At each, add the hairpin line immediately after the existing slur line, guarding on a non-empty value exactly like the slur guard. **Anchor lines (read them in the file first):**

  (a) Tuplet-completion member (~line 303):
```
							if ((mev[\slur] ? "") != "") { applySlur.(mev[\slur], measures.size, sub + 1) };
```
  add after it:
```
							if ((mev[\hairpin] ? "") != "") { applyHairpin.(mev[\hairpin], measures.size, sub + 1) };
```

  (b) Tuplet-completion donor (~line 315):
```
							if ((dev[\slur] ? "") != "") { applySlur.(dev[\slur], measures.size, sub + 1) };
```
  add after it:
```
							if ((dev[\hairpin] ? "") != "") { applyHairpin.(dev[\hairpin], measures.size, sub + 1) };
```

  (c) Split-remainder clearing (~line 335) — the `.put(\slur, "")` on the reduced donor. Current:
```
								units[ui + 1] = ( kind: \normal, ev: dev.copy.put(\beats, dev[\beats] - remainder).put(\tieIn, compRest.not).put(\dynMark, nil).put(\slur, "").put(\clef, "") );
```
  add `.put(\hairpin, "")` before `.put(\clef, "")`:
```
								units[ui + 1] = ( kind: \normal, ev: dev.copy.put(\beats, dev[\beats] - remainder).put(\tieIn, compRest.not).put(\dynMark, nil).put(\slur, "").put(\hairpin, "").put(\clef, "") );
```

  (d) Bucket-split (barline-crossing) — declare `pendHairpin`, collect, and commit.
  - Declaration (~line 353), current: `pendDyn = [], pendSlur = [],` → add `pendHairpin = [],`:
```
							pendDyn = [], pendSlur = [], pendHairpin = [],
```
  - Collect at the member walk (~line 372), after:
```
										if ((mev[\slur] ? "") != "") { pendSlur = pendSlur.add([ mev[\slur], measures.size + (buckets.size - 1), sub + 1 ]) };
```
    add:
```
										if ((mev[\hairpin] ? "") != "") { pendHairpin = pendHairpin.add([ mev[\hairpin], measures.size + (buckets.size - 1), sub + 1 ]) };
```
  - Commit on success (~line 405), after:
```
							pendSlur.do({ |ss| applySlur.(ss[0], ss[1], ss[2]) });
```
    add:
```
							pendHairpin.do({ |ss| applyHairpin.(ss[0], ss[1], ss[2]) });
```

  (e) Atomic-tuplet fallback (~line 421), after:
```
								if ((mev[\slur] ? "") != "") { applySlur.(mev[\slur], measures.size, mts) };
```
  add:
```
								if ((mev[\hairpin] ? "") != "") { applyHairpin.(mev[\hairpin], measures.size, mts) };
```

  (f) Normal note placement (~line 436), after:
```
							if ((ev[\slur] ? "") != "") { applySlur.(ev[\slur], measures.size, pos + 1) };
```
  add:
```
							if ((ev[\hairpin] ? "") != "") { applyHairpin.(ev[\hairpin], measures.size, pos + 1) };
```

- [ ] **Step 7: Unclosed warning + return value**

Near the end of `voiceToMeasures` (~lines 463–464), current:
```
				if (openSlur.notNil) { "PanolaMEI: unclosed slur at the end of a voice; dropped".warn };
				( measures: measures, dynams: dynams, slurs: slurs );
```
change to:
```
				if (openSlur.notNil) { "PanolaMEI: unclosed slur at the end of a voice; dropped".warn };
				if (openHairpin.notNil) { "PanolaMEI: unclosed hairpin at the end of a voice; dropped".warn };
				( measures: measures, dynams: dynams, slurs: slurs, hairpins: hairpins );
```

- [ ] **Step 8: Output — emit `<hairpin>` per start measure**

In the output loop, immediately after the slur `perVoice.do({ ... "<slur ..." });` block (~line 645, shown in the Reference above) and before `body = body ++ "</measure>";`, insert the parallel hairpin block:

```
			perVoice.do({ |v, s|
				(v[\hairpins] ? []).select({ |hp| hp[\startMeasure] == (i+1) }).do({ |hp|
					var t1 = hp[\startTstamp], t2 = hp[\endTstamp], dm = hp[\endMeasure] - hp[\startMeasure];
					var t1s = (t1.frac < 1e-6).if({ t1.asInteger.asString }, { t1.round(0.0001).asString });
					var t2s = (t2.frac < 1e-6).if({ t2.asInteger.asString }, { t2.round(0.0001).asString });
					body = body ++ "<hairpin form=\"" ++ hp[\form] ++ "\" tstamp=\"" ++ t1s ++ "\" tstamp2=\"" ++ dm ++ "m+" ++ t2s ++ "\" staff=\"" ++ (s+1) ++ "\"/>";
				});
			});
```

- [ ] **Step 9: Run the hairpin tests — verify PASS**

Run: `py -m pytest tools/panola_mei/test_hairpins.py -q`
Expected: all pass (both the count test and `test_hairpins`).

- [ ] **Step 10: Verify tabs/CRLF and run the full suite (regression)**

Verify the edited region uses tabs + CRLF (spot-check, e.g. with a byte check that the new `applyHairpin`/emit lines end with `\r` and start with tabs). Then:

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass — the slur/dyn/tuplet tests must be unchanged (hairpins are additive; `slurs`-returning voices are byte-identical because `hairpins` is a new key).

- [ ] **Step 11: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
feat(panola_mei): hairpins (@hairpin cresc/dim/end/endcresc/enddim)

Track @hairpin like slurs (one open at a time, endcresc/enddim = messa di
voce) and emit <hairpin form="cres|dim" tstamp tstamp2 staff/> in the start
measure. Threaded through every slur call site; notation only.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/panola_mei/test_hairpins.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): @hairpin renders <hairpin> (within/dim/crossbar/messa/coexist/twovoice)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Docs — document `@hairpin` and regenerate schelp

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaMEI.sc` (the `[general]` doc-comment)
- Regenerate: `HelpSource\Classes\PanolaMEI.schelp`

- [ ] **Step 1: Add prose to the `[general]` block**

The current slur sentence (~line 30) reads:

```
teletype::@slur^start^:: ... teletype::@slur^end^:: spans become slurs.
```

Immediately after it (same paragraph), append a hairpin sentence:

```
 A per-note teletype::@hairpin^cresc^:: (or teletype::dim::) ... teletype::@hairpin^end^:: span becomes a
crescendo/decrescendo strong::<hairpin>::; teletype::@hairpin^endcresc^:: / teletype::@hairpin^enddim^:: close the
open hairpin and open the opposite one at that note (messa di voce). One hairpin at a time, like slurs.
```

- [ ] **Step 2: Regenerate schelp**

Run: from the panola quark root, run `gendoc.bat`. (If Git Bash `cd` + `cmd //c gendoc.bat` fails to resolve, run it via PowerShell: `Set-Location` to the quark dir then `.\gendoc.bat`.)
Expected: output ends with `Done.`, no `ERROR`.

- [ ] **Step 3: Verify the schelp got it**

Run: `grep -n "hairpin" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMEI.schelp"`
Expected: at least one match.

- [ ] **Step 4: Confirm the class still compiles**

Run: `py -m pytest tools/panola_mei/test_hairpins.py::test_hairpins -q`
Expected: PASS (a fresh sclang compile of the edited `PanolaMEI.sc` succeeds).

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
docs(panola_mei): document @hairpin; regenerate schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: SuperCollider example — showcase hairpins

**Files:**
- Modify: `D:\Projects\MusicScene\examples\supercollider\example_panola_score.scd`

- [ ] **Step 1: Add a crescendo + diminuendo to the right-hand voice**

Read the file. The right-hand voice string currently begins:

```
			"(c5_4@dyn^mf^@art^staccato+accent^ e5@art^staccato+accent^ g5_4. c6_8@slur^start^ g5_4 e5 c5_8@slur^endstart^ d5 e5_8*2/3@art[stacc:on] f@slur^end^ g5_16*2/3 g-5 f5_4@art[stacc:off] a5_8*2/3@slur^start^ c6 a5 c6_4@slur^end^ a5 g5_2 c5_2)*4",   // right hand (treble)
```

Add a *messa di voce* over the opening third-beat phrase: put `@hairpin^cresc^` on the `g5_4.` (beat 3) note and `@hairpin^enddim^` on the `g5_4` after the `c6_8`, and `@hairpin^end^` on the `e5` two notes later. Concretely, change `g5_4. c6_8@slur^start^ g5_4 e5` to:

```
g5_4.@hairpin^cresc^ c6_8@slur^start^ g5_4@hairpin^enddim^ e5@hairpin^end^
```

so the full RH line becomes:

```
			"(c5_4@dyn^mf^@art^staccato+accent^ e5@art^staccato+accent^ g5_4.@hairpin^cresc^ c6_8@slur^start^ g5_4@hairpin^enddim^ e5@hairpin^end^ c5_8@slur^endstart^ d5 e5_8*2/3@art[stacc:on] f@slur^end^ g5_16*2/3 g-5 f5_4@art[stacc:off] a5_8*2/3@slur^start^ c6 a5 c6_4@slur^end^ a5 g5_2 c5_2)*4",   // right hand (treble)
```

- [ ] **Step 2: Add a header note**

In the intro comment block, after the articulation sentence ("A single note can carry SEVERAL articulations..."), add:

```
//
// A crescendo/decrescendo is a spanning "hairpin": `@hairpin^cresc^` (or `dim`) opens it and
// `@hairpin^end^` closes it; `@hairpin^endcresc^` / `@hairpin^enddim^` chain a messa di voce (< >).
```

- [ ] **Step 3: Verify the example renders both hairpins**

Render the RH voice via sclang and grep the MEI (mirror the article-showcase verification):

Run (Git Bash) — write the RH+LH strings from the example into a scratch `.scd`, call `Panola.scoreAsMEI([...], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble, \bass], [[1, 2]])`, write the MEI, then:
```
grep -c 'form="cres"' <mei>   # expect >= 4  (once per (...)*4 repeat)
grep -c 'form="dim"'  <mei>   # expect >= 4
```
And run `py tools/panola_mei/render_check.py <mei>` — expect `'ok': True`.
Expected: both hairpin forms present and the score renders.

- [ ] **Step 4: Commit**

```bash
git -C "D:/Projects/MusicScene" add examples/supercollider/example_panola_score.scd
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs(examples): showcase a hairpin (messa di voce) in example_panola_score

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: CHANGELOG + BACKLOG + finish

**Files:**
- Modify: `D:\Projects\MusicScene\CHANGELOG.md`, `D:\Projects\MusicScene\docs\superpowers\BACKLOG.md`

- [ ] **Step 1: CHANGELOG entry**

Add a new top entry above `## [0.16.0]`:

```
## [0.17.0] — 2026-07-08

### Added
- **Hairpins (crescendo / decrescendo) in Panola notation.** A `@hairpin` property renders a spanning
  MEI `<hairpin>`: `@hairpin^cresc^` (or `dim`) opens and `@hairpin^end^` closes it; `@hairpin^endcresc^`
  / `@hairpin^enddim^` close the open one and open the opposite at that note (messa di voce, `< >`). One
  hairpin at a time, tracked like slurs (crosses barlines/systems). Notation only. Shown in
  `examples/supercollider/example_panola_score.scd`. (PanolaMEI in the Panola quark.)
```

- [ ] **Step 2: Mark hairpins done in BACKLOG**

In `docs/superpowers/BACKLOG.md`, remove the `**Hairpins (cresc./decresc.)**` bullet from "Panola notation" (it shipped).

- [ ] **Step 3: Full suite green**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass.

- [ ] **Step 4: Commit docs**

```bash
git -C "D:/Projects/MusicScene" add CHANGELOG.md docs/superpowers/BACKLOG.md docs/superpowers/specs/2026-07-08-panola-hairpins-design.md docs/superpowers/plans/2026-07-08-panola-hairpins.md
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs: CHANGELOG 0.17.0 (hairpins); mark backlog done; spec + plan

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Finish the branch**

Use **superpowers:finishing-a-development-branch** for MusicScene `feature/panola-hairpins`. Then, if the user wants a release: bump `Panola.quark` (0.6.0 → 0.7.0) + tag; bump `MSScore.quark` dependency + version + tag; bump MusicScene `plugin.cfg` + `MS_VERSION` (0.16.0 → 0.17.0) and tag `v0.17.0` — per the [[release-doc-version-consistency]] checklist. (Pushing the quarks stays the user's responsibility.)

---

## Self-review

**Spec coverage:**
- `@hairpin` values cresc/dim/end/endcresc/enddim + synonyms → Task 2 Steps 5 (`applyHairpin`/`formOf`). ✓
- Spanning-mark tracking mirroring slurs at every call site → Task 2 Step 6 (a–f). ✓
- One-open-at-a-time / unclosed / unmatched warnings → Task 2 Steps 5, 7; tested by `unmatched` case. ✓
- Independent of @dyn/@slur (all three on one note) → `coexist` case. ✓
- MEI output `<hairpin form tstamp tstamp2 staff>` in start measure → Task 2 Step 8. ✓
- render_check count → Task 1. ✓
- Tests (within/dim/crossbar/messa/coexist/unmatched/twovoice) → Task 1 + Task 2 Step 1. ✓
- Docs + schelp → Task 3. ✓ Example → Task 4. ✓ CHANGELOG/BACKLOG → Task 5. ✓
- No parser change needed (values are plain words) — confirmed; no task touches PanolaParser. ✓

**Placeholder scan:** No TBD/TODO/"similar to". All code shown in full; commands concrete with expected output.

**Type/name consistency:** `ev[\hairpin]`/`mev[\hairpin]`/`dev[\hairpin]`, `openHairpin`, `hairpins`, `applyHairpin`, `pendHairpin`, `hp[\form]`/`hp[\startMeasure]`/`hp[\startTstamp]`/`hp[\endMeasure]`/`hp[\endTstamp]` used consistently. The record fields written in `applyHairpin` (Step 5) exactly match those read in the output block (Step 8) and the `hairpins` key matches the return (Step 7) and the test/ render_check (`<hairpin `). Expected tstamps (`0m+4`, `1m+1`, `0m+3` + `3`/`1m+1`) mirror the verified slur test values for the identical note layouts.
