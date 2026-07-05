# Panola per-note expression → MEI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notate per-note dynamics (`@dyn^mf^` → `<dynam>`) and articulation (`@art[stacc:on]`, `@art^acc^` → note `artic`) from Panola strings.

**Architecture:** All in the Panola quark. **Part A** teaches Panola's property grammar to accept word values and makes `asPbind` robust to them; **Part B** maps the `dyn`/`art` properties to MEI in `PanolaMEI` (articulation = a running set + one-shot bare names; dynamics = a measure-level `<dynam>` emitted on change). Every edited quark class keeps whelk-style doc comments and `HelpSource/` is regenerated.

**Tech stack:** SuperCollider (Panola quark: `PanolaParser.sc`, `Panola.sc`, `PanolaMEI.sc`), scparco parser combinators, MEI + Verovio (`addons/musicscene/tools/verovio_render.py`), Python pytest (`tools/panola_mei/`). Full TDD via headless sclang.

**Spec:** `docs/superpowers/specs/2026-07-05-panola-expression-design.md`

**Two repos.**
- MusicScene (`D:\Projects\MusicScene`, branch `feature/panola-expression`): the Python tests + docs.
- Panola quark (`C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola`, its own git repo): the `.sc` sources. Commit those there.

**Conventions.**
- sclang: `"C:\Program Files\SuperCollider-3.14.1\sclang.exe" <script.scd>`; end scripts with `0.exit;`. Editing any `.sc` recompiles the class library on the next run, so a syntax error surfaces immediately.
- Verovio wrapper: `py addons/musicscene/tools/verovio_render.py <in.mei> <out.svg> --page 1`.
- Panola property forms: `@name{v}` animated, `@name[v]` static (persists), `@name^v^` one-shot (that note).
- **whelk docs:** after editing a quark class, keep its `[general]`/`[classmethod]`/`[method]` comments current (mirror `Panola.sc`), then run `gendoc.bat` (whelk) and eyeball the `.schelp`. Avoid `link::Classes/X#-m::` inline anchors (whelk drops `#-`; use `teletype::m::`).

---

## File structure

| File | Repo | Responsibility |
|---|---|---|
| `Classes/PanolaParser.sc` | Panola | property value grammar: word value alongside float |
| `Classes/Panola.sc` | Panola | `asPbind` passes string-valued custom properties through without arithmetic (+ doc note) |
| `Classes/PanolaMEI.sc` | Panola | read `dyn`/`art`; articulation set + `artic`; measure-level `<dynam>`; whelk docs |
| `tools/panola_mei/render_check.py` | MusicScene | count `<dynam` and expose `artic` presence |
| `tools/panola_mei/test_expression.py` | MusicScene | new pytest: sclang → MEI → render + assert |
| `CHANGELOG.md` | MusicScene | document the feature |

**Event dict** gains: `art` (String), `dyn` (String), and (after the annotate pass) `articStr` (String, space-separated MEI codes) + `dynMark` (String mark to emit, or nil).

---

# Part A — Panola string property values

## Task A1: property grammar accepts word values

**Files:** Modify `Classes/PanolaParser.sc`; Test `Classes/tests/test_expression.scd` (Panola repo, scratch) via sclang.

- [ ] **Step 1: Write a failing check** — a scratch `.scd` (run with sclang) that currently errors:

```supercollider
(
"A: ".post; Panola("c4@art[stacc:on] d4 e4@art[stacc:off] f4").customPropertyPattern("art", "-").asStream.all.postln;
"B: ".post; Panola("c4@dyn^mf^ d4").customPropertyPattern("dyn", "-").asStream.all.postln;
"C: ".post; Panola("c4@vol[0.9] d4").volumePattern.asStream.all.postln;   // numeric still works
0.exit;
)
```

- [ ] **Step 2: Run to verify it fails.** Run the script via sclang. Expected: line A/B print an `ERROR: ...parse panola...` (word value rejected) then a fallback default; line C is fine.

- [ ] **Step 3: Add a word-value alternative** in `Classes/PanolaParser.sc`. In `propertiesParser`, each of the three `ScpSequenceOf` forms currently has `ScpParserFactory.makeFloatParser` as the value. Replace **each** of those three occurrences with a choice of float-or-word:

```supercollider
					ScpChoice([ScpParserFactory.makeFloatParser, ScpRegexParser("[a-zA-Z][a-zA-Z0-9:]*")]),
```

So each form reads (example for the static `[...]` form; do the same in the `{...}` and `^...^` forms):

```supercollider
				ScpSequenceOf([
					propertynameParser,
					ScpStrParser("["),
					ScpChoice([ScpParserFactory.makeFloatParser, ScpRegexParser("[a-zA-Z][a-zA-Z0-9:]*")]),
					ScpStrParser("]")
				]).map({|result| (\propertyname: result[0][\value], \type: \staticproperty, \value: result[2])}),
```

(`ScpChoice`, `ScpRegexParser`, `ScpSequenceOf`, `ScpStrParser` are already imported/used in this file. `result[2]` is now a Float when numeric, a String when a word — the `.map` is unchanged.)

- [ ] **Step 4: Run to verify it passes.** Re-run the Step-1 script. Expected:
  - A: `[-, stacc:on, stacc:on, stacc:off]` (persists),
  - B: `[mf, -]` (one-shot, single note),
  - C: `[0.9, 0.9]` (numeric unchanged).

- [ ] **Step 5: Commit** (Panola repo)

```bash
git -C "<panola>" add Classes/PanolaParser.sc
git -C "<panola>" commit -m "feat: property values may be words (e.g. @dyn^mf^, @art[stacc:on]), not only numbers"
```

## Task A2: `asPbind` tolerates string-valued custom properties

**Files:** Modify `Classes/Panola.sc`; Test `Classes/tests/*.scd` via sclang.

- [ ] **Step 1: Write the failing check** — scratch `.scd`:

```supercollider
(
var p = Panola("c4@dyn^mf^ d4@art[stacc:on] e4 f4");
var pb = p.asPbind(\default, include_tempo: false);
// materializing the pattern must not raise a String-arithmetic error:
pb.asStream.nextN(4, ()).postln;
"ASPBIND-OK".postln; 0.exit;
)
```

- [ ] **Step 2: Run to verify it fails.** Expected: an error like `doesNotUnderstand '*'` (a String/Symbol times a Float) — `asPbind` did `customPropertyPattern(...) * scale` on the `dyn`/`art` values.

- [ ] **Step 3: Handle string properties in `asPbind`.** In `Classes/Panola.sc`, inside the `this.customProperties.keysValuesDo({ |stringproperty, pbindkey| ... })` loop, replace the body under `if (exclude_property.not) { ... }` so string-valued properties bypass the arithmetic:

```supercollider
				if (exclude_property.not) {
					// a custom property whose values are words (e.g. notation @dyn/@art) can't be scaled;
					// pass it through as a Pseq of Symbols so the voice still plays.
					if (this.customPropertyPattern(stringproperty, 0.0).asStream.all.any({ |v| v.isKindOf(String) })) {
						mapped_props = mapped_props.add([pbindkey,
							Pseq(this.customPropertyPattern(stringproperty, "").asStream.all.collect({ |v| v.asSymbol })) ]);
					} {
						if (custom_property_defaults.notNil) {
							if (custom_property_defaults[stringproperty].notNil) {
								default_val = custom_property_defaults[stringproperty];
							};
						};
						if (translate_std_keys) {
							if (stringproperty.compare("tempo") == 0) { scale = (1/(60.0)); };
							if (pbindkey.asString.compare("vol") == 0) { pbindkey = \amp; };
							if (pbindkey.asString.compare("pdur") == 0) { pbindkey = \legato; };
						};
						mapped_props = mapped_props.add([pbindkey, this.customPropertyPattern(stringproperty, default_val)*scale]);
					};
				};
```

(This preserves the existing numeric branch exactly; only string-valued properties take the new branch.)

- [ ] **Step 4: Update the `asPbind` whelk doc.** In the `/* [method.asPbind] ... */` block above the method, extend the `description` to note: `"Custom properties whose values are words (e.g. notation properties like @dyn/@art) are passed through as symbols rather than scaled numerically."`

- [ ] **Step 5: Run to verify it passes.** Re-run the Step-1 script → `ASPBIND-OK`, no error, and the printed events contain `dyn`/`art` symbols.

- [ ] **Step 6: Regenerate docs + commit.** Run `gendoc.bat` (Panola repo) to refresh `HelpSource/Classes/Panola.schelp`; confirm no whelk error.

```bash
git -C "<panola>" add Classes/Panola.sc HelpSource/Classes/Panola.schelp
git -C "<panola>" commit -m "fix: asPbind passes word-valued custom properties through as symbols (no arithmetic)"
```

---

# Part B — dynamics + articulation → MEI (`PanolaMEI.sc`)

## Task B1: harness counts dynamics + exposes artic

**Files:** Modify `tools/panola_mei/render_check.py`; Test `tools/panola_mei/test_expression.py` (new).

- [ ] **Step 1: Write the failing test** (`tools/panola_mei/test_expression.py`):

```python
"""Per-note expression (dynamics + articulation) tests for Panola.scoreAsMEI (PanolaMEI).
Runs sclang to generate MEI, renders via Verovio, and asserts expression structure.
Run:  py -m pytest tools/panola_mei/test_expression.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

MINIMAL = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<note dur="4" oct="5" pname="c" artic="stacc"/><note dur="4" oct="5" pname="d"/>'
  '<note dur="2" oct="5" pname="e"/></layer></staff>'
  '<dynam tstamp="1" staff="1">mf</dynam></measure></section></score></mdiv></body></music></mei>')

def test_render_props_counts_dynam_and_artic():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["dynam"] == 1
    assert p["artics"] == 1
```

- [ ] **Step 2: Run to verify it fails.** Run: `py -m pytest tools/panola_mei/test_expression.py -q`. Expected: FAIL — `KeyError: 'dynam'`.

- [ ] **Step 3: Add the props** — in `tools/panola_mei/render_check.py`, add to the returned dict (before the closing `}`):

```python
        "dynam": mei.count("<dynam "), "artics": mei.count(' artic="'),
```

- [ ] **Step 4: Run to verify it passes.** Same command → PASS.

- [ ] **Step 5: Commit** (MusicScene repo)

```bash
git add tools/panola_mei/render_check.py tools/panola_mei/test_expression.py
git commit -m "test(panola-mei): count <dynam> + artic in the render harness"
```

## Task B2: articulation → note `artic`

**Files:** Modify `Classes/PanolaMEI.sc`; Test `tools/panola_mei/test_expression.py`.

- [ ] **Step 1: Write the failing test** — append to `test_expression.py`:

```python
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

ART = {
  "oneshot":  r'Panola.scoreAsMEI([Panola("c5_4@art^staccato^ d5 e5 c5_4")], "4/4", \Cmajor, [\treble], nil)',
  "passage":  r'Panola.scoreAsMEI([Panola("c5_4@art[stacc:on] d5 e5 f5@art[stacc:off] g5 a5 b5 c6")], "4/4", \Cmajor, [\treble], nil)',
  "layered":  r'Panola.scoreAsMEI([Panola("c5_4@art[acc:on] d5@art[stacc:on] e5@art[acc:off] f5")], "4/4", \Cmajor, [\treble], nil)',
}

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_articulation():
    outdir = tempfile.mkdtemp(prefix="panola_expr_")
    try:
        _dump(outdir, ART)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in ART}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    # one-shot: exactly one note has artic (the first)
    assert meis["oneshot"].count(' artic="stacc"') == 1
    # passage: first four notes staccato, last four none
    assert meis["passage"].count(' artic="stacc"') == 4
    # layered: acc, then acc+stacc, then stacc (acc dropped)
    assert 'artic="acc"' in meis["layered"] and 'artic="acc stacc"' in meis["layered"] and 'artic="stacc"' in meis["layered"]
```

- [ ] **Step 2: Run to verify it fails.** Run: `py -m pytest tools/panola_mei/test_expression.py::test_articulation -q`. Expected: FAIL — no `artic` yet.

- [ ] **Step 3: Read `art`/`dyn` in `eventsOf`.** In `Classes/PanolaMEI.sc`, extend `eventsOf` to fetch the two expression patterns and attach them per event:

```supercollider
		var eventsOf = { |panola|
			var names = panola.notationnotePattern.asStream.all;
			var durs = panola.notationdurationPattern.asStream.all;
			var beats = panola.durationPattern.asStream.all;
			var dyns = panola.customPropertyPattern("dyn", "").asStream.all;
			var arts = panola.customPropertyPattern("art", "").asStream.all;
			names.collect({ |nm, i|
				var e = parseName.(nm), d = parseDur.(durs[i]);
				e[\meidur] = d[0]; e[\dots] = d[1]; e[\mult] = d[2]; e[\div] = d[3]; e[\beats] = beats[i];
				e[\dyn] = dyns[i].asString; e[\art] = arts[i].asString;
				e;
			});
		};
```

- [ ] **Step 4: Add the articulation map + annotate pass** in `Classes/PanolaMEI.sc`, near the other helper `var`s (e.g. after `parseDur`):

```supercollider
		var artCode = { |name|
			IdentityDictionary[
				\staccato->"stacc", \stacc->"stacc", \staccatissimo->"stacciss", \stacciss->"stacciss",
				\accent->"acc", \acc->"acc", \tenuto->"ten", \ten->"ten",
				\marcato->"marc", \marc->"marc", \spiccato->"spicc", \spicc->"spicc"
			][name.asString.asSymbol];
		};
		// per event: articStr (space-separated MEI artic codes) + dynMark (dynamic to emit here, or nil).
		// articulation set: "name:on"/"name:off" toggles it on change; a bare name adds to this note only.
		var annotateExpression = { |events|
			var artSet = Set[], prevArt = "", prevDyn = "";
			events.do({ |ev|
				var art = ev[\art] ? "", dyn = ev[\dyn] ? "", noteSet;
				if ((art != prevArt) and: { art.includes($:) }) {
					var parts = art.split($:), code = artCode.(parts[0]);
					if (code.notNil) {
						(parts[1] == "on").if({ artSet = artSet.add(code) }, { artSet.remove(code) });
					} { ("PanolaMEI: unknown articulation '" ++ parts[0] ++ "'").warn };
				};
				prevArt = art;
				noteSet = artSet.copy;
				if ((art != "") and: { art.includes($:).not }) {
					var code = artCode.(art);
					if (code.notNil) { noteSet = noteSet.add(code) } { ("PanolaMEI: unknown articulation '" ++ art ++ "'").warn };
				};
				ev[\articStr] = noteSet.asArray.sort.join(" ");
				ev[\dynMark] = ((dyn != prevDyn) and: { dyn != "" }).if({ dyn }, { nil });
				prevDyn = dyn;
			});
			events;
		};
```

- [ ] **Step 5: Emit `artic` in `meiElement`.** In `Classes/PanolaMEI.sc`, add an `artic` attribute (only on a whole note or the first tied fragment) inside `meiElement`. Change its opening lines to compute `aa` and thread it into the note/chord:

```supercollider
		var meiElement = { |ev, md, dt, tie, k|
			var ts = tie.notNil.if({ " tie=\"" ++ tie ++ "\"" }, {""});
			var aa = (((ev[\articStr] ? "") != "") and: { tie.isNil or: { tie == "i" } }).if({ " artic=\"" ++ ev[\articStr] ++ "\"" }, { "" });
			if (ev[\rest]) { "<rest" ++ durAttrs.(md,dt) ++ "/>" } {
				if (ev[\pnames].size == 1) {
					"<note" ++ durAttrs.(md,dt) ++ aa ++ " oct=\"" ++ ev[\octs][0] ++ "\" pname=\"" ++ ev[\pnames][0] ++ "\"" ++ accidS.(accidInKey.(ev[\pnames][0], ev[\accids][0], k)) ++ ts ++ "/>"
				} {
					var inner = "";
					ev[\pnames].size.do({ |c| inner = inner ++ "<note oct=\"" ++ ev[\octs][c] ++ "\" pname=\"" ++ ev[\pnames][c] ++ "\"" ++ accidS.(accidInKey.(ev[\pnames][c], ev[\accids][c], k)) ++ ts ++ "/>" });
					"<chord" ++ durAttrs.(md,dt) ++ aa ++ ">" ++ inner ++ "</chord>"
				}
			}
		};
```

- [ ] **Step 6: Run `annotateExpression` per voice.** In `scoreAsMEI`'s body, annotate each voice's events before binning. Change the `perVoice` line:

```supercollider
		perVoice = voices.collect({ |p| voiceToMeasures.(annotateExpression.(eventsOf.(p)), bb, key) });
```

- [ ] **Step 7: Run to verify it passes.** Run: `py -m pytest tools/panola_mei/test_expression.py::test_articulation -q`. Expected: PASS (one-shot 1, passage 4, layered acc / acc stacc / stacc). If `layered` fails, check `artSet.asArray.sort.join(" ")` yields `"acc stacc"` (alphabetical) and the `:off` removes only `acc`.

- [ ] **Step 8: Commit** (Panola repo)

```bash
git -C "<panola>" add Classes/PanolaMEI.sc
git -C "<panola>" commit -m "feat: articulation (@art[name:on/off] set + @art^name^) -> note artic"
```

## Task B3: dynamics → measure-level `<dynam>`

**Files:** Modify `Classes/PanolaMEI.sc`; Test `tools/panola_mei/test_expression.py`.

- [ ] **Step 1: Write the failing test** — add cases + a test to `test_expression.py`:

```python
DYN = {
  "oneshot": r'Panola.scoreAsMEI([Panola("c5_4@dyn^p^ d5 e5@dyn^f^ g5")], "4/4", \Cmajor, [\treble], nil)',
  "norepeat": r'Panola.scoreAsMEI([Panola("c5_4@dyn^mf^ d5 e5 g5")], "4/4", \Cmajor, [\treble], nil)',
}

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dynamics():
    outdir = tempfile.mkdtemp(prefix="panola_expr_")
    try:
        _dump(outdir, DYN)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in DYN}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert props["oneshot"]["dynam"] == 2                    # p then f
    assert '<dynam tstamp="1" staff="1">p</dynam>' in meis["oneshot"]
    assert '<dynam tstamp="3" staff="1">f</dynam>' in meis["oneshot"]
    assert props["norepeat"]["dynam"] == 1                   # one-shot mf is NOT repeated
```

- [ ] **Step 2: Run to verify it fails.** Run: `py -m pytest tools/panola_mei/test_expression.py::test_dynamics -q`. Expected: FAIL — `dynam == 0`.

- [ ] **Step 3: Collect dynam markers in `voiceToMeasures`.** In `Classes/PanolaMEI.sc`, make `voiceToMeasures` return both the measures and a list of `(measure, tstamp, mark)` markers. Add a `dynams` accumulator and record a marker when a placed note carries a `dynMark`, then return an `IdentityDictionary`. Concretely: at the top add `var dynams = [];`; in the **normal**-note branch, immediately before the `while { remaining > eps }` loop add:

```supercollider
					if (ev[\dynMark].notNil) { dynams = dynams.add(( measure: measures.size, tstamp: pos + 1, mark: ev[\dynMark] )) };
```

  and in the **tuplet** branch, immediately after computing `tbeats`, add (marks any tuplet member with a dynamic at the tuplet's onset):

```supercollider
					unit[\members].do({ |mev| if (mev[\dynMark].notNil) { dynams = dynams.add(( measure: measures.size, tstamp: pos + 1, mark: mev[\dynMark] )) } };
```

  and change the final `measures;` return to:

```supercollider
			( measures: measures, dynams: dynams );
```

- [ ] **Step 4: Consume the new return + emit `<dynam>`.** In `scoreAsMEI`, `perVoice` now holds dicts. Update the assembly:

```supercollider
		perVoice = voices.collect({ |p| voiceToMeasures.(annotateExpression.(eventsOf.(p)), bb, key) });
		nm = perVoice.collect({ |v| v[\measures].size }).maxItem;
		perVoice = perVoice.collect({ |v| while { v[\measures].size < nm } { v[\measures] = v[\measures].add(emptyRest.(bb)) }; v });
		nm.do({ |i|
			body = body ++ "<measure n=\"" ++ (i+1) ++ "\">";
			perVoice.do({ |v, s| body = body ++ "<staff n=\"" ++ (s+1) ++ "\"><layer n=\"1\">" ++ beamMeasure.(v[\measures][i], groupBeats) ++ "</layer></staff>" });
			perVoice.do({ |v, s|
				v[\dynams].select({ |dm| dm[\measure] == (i+1) }).do({ |dm|
					body = body ++ "<dynam tstamp=\"" ++ dm[\tstamp] ++ "\" staff=\"" ++ (s+1) ++ "\">" ++ dm[\mark] ++ "</dynam>";
				});
			});
			body = body ++ "</measure>";
		});
```

  (Note the two `perVoice.do` inside the measure loop: first the staves, then the `<dynam>` siblings, matching MEI ordering. `dm[\measure]` is 1-based because `measures.size` at record time equals the current measure's 1-based index.)

- [ ] **Step 5: Run to verify it passes.** Run: `py -m pytest tools/panola_mei/test_expression.py::test_dynamics -q`. Expected: PASS (oneshot 2 marks at tstamp 1 and 3; norepeat 1). If a tstamp is off, recall `tstamp = pos + 1` where `pos` is the note's beat offset in the measure (0-based) → 1-based MEI tstamp.

- [ ] **Step 6: Commit** (Panola repo)

```bash
git -C "<panola>" add Classes/PanolaMEI.sc
git -C "<panola>" commit -m "feat: dynamics (@dyn^mark^) -> measure-level <dynam> on change"
```

## Task B4: whelk docs on PanolaMEI + regenerate

**Files:** Modify `Classes/PanolaMEI.sc` (Panola repo); regenerate `HelpSource/`.

- [ ] **Step 1: Add whelk doc comments.** `PanolaMEI.sc` currently has a plain header comment and no whelk blocks. Replace the top `/* ... */` header with a `[general]` block, and add a `[classmethod.scoreAsMEI]` block before `*scoreAsMEI`, mirroring `Panola.sc`:

```supercollider
/*
[general]
title = "PanolaMEI"
summary = "render Panola voice(s) to an MEI music-notation document"
categories = "Notation, Utils"
related = "Classes/Panola, Classes/MSScore"
description = '''
Pure transform from Panola voice(s) + score preferences (time signature, key, clef per staff, brace
grouping) to an MEI document, usable by any MEI renderer (Verovio, ...). Panola has no notion of
barlines / key / clef, so those are supplied here; notes crossing a barline are split and tied,
eighths-and-shorter are auto-beamed per beat, tuplets become teletype::<tuplet>:: groups, and per-note
teletype::@dyn::/teletype::@art:: properties become dynamics and articulation. Reachable as
teletype::aPanola.asMEI(meter, key, clef):: (see link::Classes/Panola::).
'''
*/
PanolaMEI {
	/*
	[classmethod.scoreAsMEI]
	description = "render several Panola voices as one multi-staff MEI score (one voice per staff, top first), including ties, beaming, tuplets, and per-note dynamics/articulation."
	[classmethod.scoreAsMEI.args]
	voices = "an Array of Panola instances"
	meter = "time signature String, e.g. \"4/4\""
	key = "key Symbol, e.g. \\Cmajor"
	clefs = "an Array of clef symbols, one per staff (defaults to all \\treble)"
	braces = "an Array of [firstStaff, lastStaff] 1-based ranges to brace together"
	[classmethod.scoreAsMEI.returns]
	what = "an MEI document (a String)"
	*/
	*scoreAsMEI {
```

  (Keep the method body unchanged; only add the two doc comments.)

- [ ] **Step 2: Regenerate + eyeball.** Run `gendoc.bat` (Panola repo). Expected: `... PanolaMEI.sc => ... PanolaMEI.schelp`, no error. Confirm `HelpSource/Classes/PanolaMEI.schelp` starts with `TITLE:: PanolaMEI` and has a `METHOD:: scoreAsMEI` with its argument table.

- [ ] **Step 3: Commit** (Panola repo)

```bash
git -C "<panola>" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "<panola>" commit -m "docs: whelk doc comments for PanolaMEI + generated HelpSource"
```

## Task B5: full regression + docs

**Files:** `tools/panola_mei/`, `CHANGELOG.md` (MusicScene).

- [ ] **Step 1: Run the whole suite** to confirm no regression:

Run: `py -m pytest tools/panola_mei/ -q`
Expected: PASS (all of `test_asmei.py` + `test_tuplets.py` + `test_expression.py`). The existing non-expression cases prove plain/tuplet MEI is unchanged.

- [ ] **Step 2: CHANGELOG entry** — under `## [Unreleased]` → `### Added` in `CHANGELOG.md`:

```markdown
- **Per-note expression in Panola notation.** `Panola.scoreAsMEI` / `MSScore` now render dynamics and
  articulation: `@dyn^mf^` → a `<dynam>` mark (on change), and `@art[stacc:on]` / `@art[stacc:off]`
  (layered passage) or `@art^acc^` (one note) → note `artic`. Enabled by a new Panola feature — property
  values may be words, not only numbers (`asPbind` passes word-valued properties through as symbols).
  (PanolaMEI + Panola in the Panola quark.)
```

- [ ] **Step 3: Commit** (MusicScene repo)

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): Panola per-note expression (dynamics + articulation)"
```

---

## Self-review

- **Spec coverage:** grammar word values (A1); `asPbind` passthrough (A2); harness (B1); articulation set + one-shot + friendly mapping (B2); dynamics on-change measure-level `<dynam>` with tstamp/staff (B3); whelk docs on PanolaMEI + Panola + regenerate (A2 step 4/6, B4); regression + CHANGELOG (B5). All spec sections covered.
- **Type consistency:** event keys `art/dyn/articStr/dynMark` used identically across `eventsOf`→`annotateExpression`→`meiElement`/`voiceToMeasures`; `voiceToMeasures` returns `(measures:, dynams:)` and `scoreAsMEI` consumes `v[\measures]`/`v[\dynams]` consistently; marker keys `measure/tstamp/mark`. `artCode` used in both toggle and bare-name branches.
- **Placeholder scan:** no TBD/TODO; every code step shows complete SC/Python; the whelk-doc and regenerate steps are explicit commands.
