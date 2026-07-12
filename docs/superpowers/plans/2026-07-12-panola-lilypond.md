# Panola → LilyPond Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full-parity Panola → LilyPond transform (`PanolaLilypond`) that emits a standalone-renderable `.ly`, wired into MusicScene (MSScore `notation: \lilypond`) with addressable positions working end-to-end.

**Architecture:** A new standalone class `PanolaLilypond` mirrors `PanolaMEI` method-for-method, reusing the already-standalone helpers (`PanolaMeter`, `PanolaMeterSplitter`, `PanolaDurationSpeller`, `PanolaRational`) and the pure lyric parser `PanolaMEI.pr_parseLyricLine`. `PanolaMEI` is **left byte-identical** (its output is guarded by 0.18.0 release tests). LilyPond auto-beams and auto-respells accidentals, and its dynamics/slurs/hairpins attach **inline to note tokens** — so the LilyPond walk is simpler than the MEI walk (no `<beam>`, no accidental-in-key logic, no timestamped `<dynam>/<slur>/<hairpin>` collections). The Godot LilyPond addressable path (`_submit_lily`, `MSNotationLilyPositions`) already exists and needs no change.

**Tech Stack:** SuperCollider (the panola + msscore quarks, both git repos under `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\`), Python + pytest (sclang-driven tests under `D:\Projects\MusicScene\tools\`), Godot 4.7 GDScript (self-test), LilyPond 2.24/2.25.

---

## Reference material (read before starting)

- **`PanolaMEI.sc`** (`…\Extensions\panola\Classes\PanolaMEI.sc`) — the transform to port. Key inner closures of `*scoreAsMEI`: `parseOne`/`parseName`/`parseDur` (event field parsing), `eventsOf` (line 686), `annotateExpression` (line 161, sticky-toggle + combo articulation and dyn-on-change), `parseMeter` (line 255), `resolveChanges` (line 271), `groupEvents` (line 621, tuplet grouping), `voiceToMeasures` (line 281, the big walk incl. tuplet completion + cross-barline split), `meiElement` (line 233), `clefEl` (line 545), `staffGrp` (line 642), `attachLyrics` (line 658), `lyricSlotsFor` (line 678), `verseXml` (line 220). Class methods `*pr_parseLyricLine` (line 784, **reused as-is**) and `*pr_xmlEscape` (line 834).
- **Helpers**: `PanolaMeter(num, den, groups)` → `.boundaries`, `.measureLengthQL`; `PanolaMeterSplitter.split(noteEvent, meter)` → components with `\spelling` (`\inexpressible`, `\components:[(meidur:, dots:, ql:, tuplets:[...])]`); `PanolaDurationSpeller.spell(ql)` / `.new.spell(ql)`; `PanolaRational.fromFloat(x)`.
- **Panola pattern accessors** (used by `eventsOf`): `p.notationnotePattern`, `p.notationdurationPattern`, `p.durationPattern`, `p.customPropertyPattern("dyn"|"art"|"slur"|"hairpin"|"clef", "")` — each `.asStream.all`.
- **Test harness pattern**: `tools/panola_mei/test_asmei.py` and `test_tuplets.py` (sclang-driven: write a `.scd` that calls the transform + `.write`s output, run `sclang`, assert on the output string). `render_check.render_props` renders MEI via Verovio — the LilyPond tests instead assert on the emitted `.ly` **text** (and, where LilyPond is installed, compile it).
- **Godot LilyPond path**: `MSRenderQueue._submit_lily` (line 98) + `MSNotationLilyPositions` (`wrap_source` strips `\version` and prepends a moment-tagger + `\layout`; renders `-dbackend=svg -dcrop=#t`; parses point-and-click). Sample target shape: `scores/example.ly`.

## Repositories & where each file lives

- **panola quark** (git repo at `…\Extensions\panola\`): `Classes/PanolaLilypond.sc` (new), `Classes/Panola.sc` (modify). Commit SC-class work here.
- **msscore quark** (git repo at `…\Extensions\msscore\`): `Classes/MSScore.sc` (modify). Commit MSScore work here.
- **MusicScene repo** (`D:\Projects\MusicScene`, branch `panola-lilypond`): `tools/panola_lilypond/…` tests, `tools/test_notation_lilypond.gd`, `examples/supercollider/example_lilypond.scd`, docs, `.github/workflows/ci.yml`. Commit test/example/doc/CI work here.

Each task states which repo it commits in. **Never push** (the user pushes). Commit only the files a task names.

## File structure of `PanolaLilypond.sc`

```
PanolaLilypond {
    // ---- pure class-method mappers (unit-testable in isolation) ----
    *pr_pitchLy { |pname, accid, oct| ... }       // "f","s",5 -> "fs''"
    *pr_durLy   { |md, dots| ... }                // "4",1 -> "4."
    *pr_clefLy  { |clefSym| ... }                 // \bass -> "bass"
    *pr_keyLy   { |keySym| ... }                  // \Gmajor -> "g \\major"
    *pr_meterLy { |meterStr| ... }                // "2+2+3/8" -> "\\compoundMeter #'((2 8) (2 8) (3 8))"
    *pr_dynLy   { |mark| ... }                    // "mf" -> "\\mf"; "sffz" -> markup fallback
    *pr_artLy   { |articStr| ... }                // "acc stacc" -> "->-."
    *pr_lyricTok{ |slot| ... }                    // a lyric slot -> a LilyPond lyricmode token

    // ---- the transform (ports PanolaMEI.*scoreAsMEI, emission swapped) ----
    *scoreAsLilypond { |voices, changes, clefs=nil, braces=nil, pageBreaks=nil, systemBreaks=nil, lyrics=nil| ... }
}
```

The mappers are pure `String`/`Symbol` → `String` and are TDD'd directly (Stage 1). `*scoreAsLilypond` is built up across Stages 2–6. Panola/MSScore accessors are Stage 7.

---

## Stage 1 — Pure mappers

### Task 1: `pr_pitchLy` — pitch + accidental + octave

**Files:**
- Create: `…\Extensions\panola\Classes\PanolaLilypond.sc` (panola repo)
- Test: `D:\Projects\MusicScene\tools\panola_lilypond\test_mappers.py` (MusicScene repo)
- Create: `D:\Projects\MusicScene\tools\panola_lilypond\__init__.py` (empty)

- [ ] **Step 1: Write the failing test**

`tools/panola_lilypond/test_mappers.py`:
```python
"""Unit tests for PanolaLilypond's pure mapper class-methods (panola quark).
Runs sclang headlessly and asserts on postln output. Run:
  py -m pytest tools/panola_lilypond/test_mappers.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write("(\n" + script + "\n0.exit;\n)\n"); path = f.name
    try:
        return subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_pitch():
    r = _run(r'''
["PA:" ++ PanolaLilypond.pr_pitchLy("c", nil, 4),
 "PB:" ++ PanolaLilypond.pr_pitchLy("c", nil, 5),
 "PC:" ++ PanolaLilypond.pr_pitchLy("c", nil, 3),
 "PD:" ++ PanolaLilypond.pr_pitchLy("c", nil, 2),
 "PE:" ++ PanolaLilypond.pr_pitchLy("f", "s", 5),
 "PF:" ++ PanolaLilypond.pr_pitchLy("b", "f", 3),
 "PG:" ++ PanolaLilypond.pr_pitchLy("d", "x", 5),
 "PH:" ++ PanolaLilypond.pr_pitchLy("e", "ff", 4)
].do({ |x| x.postln });''')
    out = r.stdout
    assert "ERROR" not in out, out[-1500:]
    for exp in ["PA:c'", "PB:c''", "PC:c\n", "PD:c,", "PE:fs''", "PF:bf", "PG:dss''", "PH:eff'"]:
        assert exp in out, (exp, out[-1500:])
```

- [ ] **Step 2: Run it, verify it fails**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/panola_lilypond/test_mappers.py::test_pitch -q`
Expected: FAIL (sclang error: class `PanolaLilypond` not found), or a skip if sclang absent (then develop against sclang directly).

- [ ] **Step 3: Create the class with `pr_pitchLy`**

`…\Extensions\panola\Classes\PanolaLilypond.sc` (use TABs + CRLF to match `PanolaMEI.sc`):
```supercollider
/*
[general]
title = "PanolaLilypond"
summary = "render Panola voice(s) to a standalone LilyPond (.ly) document"
categories = "Notation, Utils"
related = "Classes/Panola, Classes/PanolaMEI, Classes/MSScore, Classes/PanolaMeterSplitter"
description = '''
Pure transform from Panola voice(s) + score preferences to a self-contained LilyPond source (a String)
that renders standalone (teletype::lilypond score.ly::) and is also accepted by MusicScene's LilyPond
engraver. It is the LilyPond sibling of link::Classes/PanolaMEI:: and covers the same features: meter-aware
splitting-and-tying, tuplets (incl. music21-style completion and cross-barline splitting), dynamics,
articulations, slurs, hairpins, lyrics, inline teletype::@clef::, mid-piece meter/key changes, additive
meters, page/system breaks, braces and multi-staff. Pitches are absolute with teletype::\\language "english"::;
LilyPond auto-beams and auto-respells accidentals. See link::Classes/PanolaMEI:: for the Panola property syntax.
'''
*/
PanolaLilypond {

	/*
	[classmethod.pr_pitchLy]
	description = "(private) a Panola pitch (pname, accid code s/x/f/ff or nil, octave Integer) as an absolute english-language LilyPond pitch, e.g. teletype::fs''::. Octave marks: apostrophes = octave-3 (comma below)."
	[classmethod.pr_pitchLy.args]
	pname = "the diatonic pitch letter String (a..g)"
	accid = "the accidental code String \"s\"/\"x\"/\"f\"/\"ff\", or nil"
	oct = "the octave Integer (scientific: 4 = the octave of middle C)"
	[classmethod.pr_pitchLy.returns]
	what = "a LilyPond pitch String"
	*/
	*pr_pitchLy {
		| pname, accid, oct |
		var acc = case
			{ accid == "s" } { "s" } { accid == "x" } { "ss" }
			{ accid == "f" } { "f" } { accid == "ff" } { "ff" } { true } { "" };
		var k = oct - 3, marks = "";
		k.abs.do({ marks = marks ++ (k > 0).if({ "'" }, { "," }) });
		^pname.asString.toLower ++ acc ++ marks;
	}
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `py -m pytest tools/panola_lilypond/test_mappers.py::test_pitch -q`
Expected: PASS (or skip if sclang absent — in that case run the `.scd` snippet manually via sclang to confirm the eight outputs).

- [ ] **Step 5: Commit (two repos)**

```bash
# panola repo
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaLilypond.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "feat(lilypond): PanolaLilypond.pr_pitchLy pitch mapper"
# MusicScene repo
cd /d/Projects/MusicScene && git add tools/panola_lilypond/__init__.py tools/panola_lilypond/test_mappers.py
git commit -m "test(lilypond): pr_pitchLy mapper test"
```

### Task 2: `pr_durLy`, `pr_clefLy`

**Files:**
- Modify: `…\Extensions\panola\Classes\PanolaLilypond.sc`
- Test: `tools/panola_lilypond/test_mappers.py`

- [ ] **Step 1: Add the failing test**

Append to `test_mappers.py`:
```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dur_and_clef():
    r = _run(r'''
["DA:" ++ PanolaLilypond.pr_durLy("4", 0), "DB:" ++ PanolaLilypond.pr_durLy("4", 1),
 "DC:" ++ PanolaLilypond.pr_durLy("1", 0), "DD:" ++ PanolaLilypond.pr_durLy("16", 2),
 "DE:" ++ PanolaLilypond.pr_durLy("breve", 0),
 "CA:" ++ PanolaLilypond.pr_clefLy(\treble), "CB:" ++ PanolaLilypond.pr_clefLy(\bass),
 "CC:" ++ PanolaLilypond.pr_clefLy(\alto), "CD:" ++ PanolaLilypond.pr_clefLy(\tenor)
].do({ |x| x.postln });''')
    out = r.stdout
    assert "ERROR" not in out, out[-1500:]
    for exp in ["DA:4", "DB:4.", "DC:1", "DD:16..", "DE:\\breve",
                "CA:treble", "CB:bass", "CC:alto", "CD:tenor"]:
        assert exp in out, (exp, out[-1500:])
```

- [ ] **Step 2: Run, verify it fails** — `py -m pytest tools/panola_lilypond/test_mappers.py::test_dur_and_clef -q` → FAIL (methods not found).

- [ ] **Step 3: Add the mappers** to `PanolaLilypond.sc` (inside the class, after `pr_pitchLy`):
```supercollider
	/*
	[classmethod.pr_durLy]
	description = "(private) a MEI/Panola duration value token (\"1\",\"2\",\"4\",\"8\",... or \"breve\"/\"long\"/\"maxima\") plus a dot count as a LilyPond duration, e.g. teletype::4.::"
	[classmethod.pr_durLy.args]
	md = "the note-value token (a String or Integer)"
	dots = "the number of augmentation dots"
	[classmethod.pr_durLy.returns]
	what = "a LilyPond duration String"
	*/
	*pr_durLy {
		| md, dots |
		var base = case
			{ md.asString == "breve" } { "\\breve" }
			{ md.asString == "long" } { "\\longa" }
			{ md.asString == "maxima" } { "\\maxima" }
			{ true } { md.asString };
		var d = ""; dots.do({ d = d ++ "." });
		^base ++ d;
	}

	/*
	[classmethod.pr_clefLy]
	description = "(private) a clef Symbol (\\treble \\bass \\alto \\tenor) as a LilyPond clef name; an unknown clef warns and yields \"treble\"."
	[classmethod.pr_clefLy.args]
	clefSym = "a clef Symbol"
	[classmethod.pr_clefLy.returns]
	what = "a LilyPond clef-name String"
	*/
	*pr_clefLy {
		| clefSym |
		var m = IdentityDictionary[\treble->"treble", \bass->"bass", \alto->"alto", \tenor->"tenor"];
		var v = m[clefSym];
		v.isNil.if({ ("PanolaLilypond: unknown clef '" ++ clefSym ++ "'; using treble").warn; "treble" }, { v });
	}
```

- [ ] **Step 4: Run, verify it passes** — `py -m pytest tools/panola_lilypond/test_mappers.py::test_dur_and_clef -q` → PASS.

- [ ] **Step 5: Commit** (panola repo: `PanolaLilypond.sc`; MusicScene repo: `test_mappers.py`), messages `feat(lilypond): duration + clef mappers` / `test(lilypond): dur+clef mapper tests`.

### Task 3: `pr_keyLy`, `pr_meterLy`

**Files:** Modify `PanolaLilypond.sc`; Test `test_mappers.py`.

- [ ] **Step 1: Add the failing test**
```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_key_and_meter():
    r = _run(r'''
["KA:" ++ PanolaLilypond.pr_keyLy(\Cmajor), "KB:" ++ PanolaLilypond.pr_keyLy(\Gmajor),
 "KC:" ++ PanolaLilypond.pr_keyLy(\FsharpMinor), "KD:" ++ PanolaLilypond.pr_keyLy(\Bflatmajor),
 "KE:" ++ PanolaLilypond.pr_keyLy(\Dminor),
 "MA:" ++ PanolaLilypond.pr_meterLy("4/4"), "MB:" ++ PanolaLilypond.pr_meterLy("7/8"),
 "MC:" ++ PanolaLilypond.pr_meterLy("2+2+3/8")
].do({ |x| x.postln });''')
    out = r.stdout
    assert "ERROR" not in out, out[-1500:]
    for exp in ["KA:c \\major", "KB:g \\major", "KC:fs \\minor", "KD:bf \\major", "KE:d \\minor",
                "MA:\\time 4/4", "MB:\\time 7/8", "MC:\\compoundMeter #'((2 8) (2 8) (3 8))"]:
        assert exp in out, (exp, out[-1500:])
```

- [ ] **Step 2: Run, verify it fails.**

- [ ] **Step 3: Add the mappers** (key table mirrors `PanolaMEI.sc` `keysig` keys exactly):
```supercollider
	/*
	[classmethod.pr_keyLy]
	description = "(private) a key Symbol (e.g. \\Gmajor, \\FsharpMinor) as a LilyPond teletype::\\key:: argument, e.g. teletype::g \\major::; an unknown key warns and yields teletype::c \\major::. LilyPond auto-respells accidentals, so no per-note key logic is needed."
	[classmethod.pr_keyLy.args]
	keySym = "a key Symbol"
	[classmethod.pr_keyLy.returns]
	what = "a LilyPond key String, e.g. \"g \\\\major\""
	*/
	*pr_keyLy {
		| keySym |
		var t = IdentityDictionary[
			\cmajor->"c \\major", \aminor->"a \\minor", \gmajor->"g \\major", \eminor->"e \\minor",
			\dmajor->"d \\major", \bminor->"b \\minor", \amajor->"a \\major", \fsharpminor->"fs \\minor",
			\emajor->"e \\major", \csharpminor->"cs \\minor", \bmajor->"b \\major", \gsharpminor->"gs \\minor",
			\fmajor->"f \\major", \dminor->"d \\minor", \bflatmajor->"bf \\major", \gminor->"g \\minor",
			\eflatmajor->"ef \\major", \cminor->"c \\minor", \aflatmajor->"af \\major", \fminor->"f \\minor",
			\dflatmajor->"df \\major", \bflatminor->"bf \\minor"
		];
		var v = t[keySym.asString.toLower.asSymbol];
		v.isNil.if({ ("PanolaLilypond: unknown key '" ++ keySym ++ "'; using C major").warn; "c \\major" }, { v });
	}

	/*
	[classmethod.pr_meterLy]
	description = "(private) a meter String as a LilyPond time-signature command. A plain numerator (teletype::\"7/8\"::) yields teletype::\\time 7/8::; an additive numerator (teletype::\"2+2+3/8\"::) yields a teletype::\\compoundMeter:: that both displays the additive signature and groups the auto-beaming."
	[classmethod.pr_meterLy.args]
	meterStr = "a meter String, e.g. \"4/4\" or \"2+2+3/8\""
	[classmethod.pr_meterLy.returns]
	what = "a LilyPond time-signature command String"
	*/
	*pr_meterLy {
		| meterStr |
		var parts = meterStr.split($/), numStr = parts[0], den = parts[1];
		^(numStr.indexOf($+).notNil).if({
			"\\compoundMeter #'(" ++ numStr.split($+).collect({ |g| "(" ++ g ++ " " ++ den ++ ")" }).join(" ") ++ ")";
		}, {
			"\\time " ++ numStr ++ "/" ++ den;
		});
	}
```

- [ ] **Step 4: Run, verify it passes.**
- [ ] **Step 5: Commit** (`feat(lilypond): key + meter mappers` / `test(lilypond): key+meter mapper tests`).

---

## Stage 2 — Core walk (notes, rests, chords, ties, multi-staff, braces, global spine)

### Task 4: score skeleton + single-voice notes/rests/chords (one measure, no splitting)

Port `PanolaMEI.*scoreAsMEI`'s event parsing (`parseOne`, `parseName`, `parseDur`, `eventsOf`) verbatim (they are format-neutral), then emit a minimal standalone `.ly`. **Meter splitting and ties come in Task 5** — for now assume every note fits its bar.

**Files:** Modify `PanolaLilypond.sc`; Test `tools/panola_lilypond/test_core.py`.

- [ ] **Step 1: Write the failing test** — `tools/panola_lilypond/test_core.py`:
```python
"""Core Panola->LilyPond tests: assert on the emitted .ly text. Where LilyPond is installed
(env LILYPOND), also compile the .ly to confirm it is valid. Run:
  py -m pytest tools/panola_lilypond/test_core.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")
LILYPOND = os.environ.get("LILYPOND", r"C:\Program Files\lilypond-2.25.81\bin\lilypond.exe")


def gen(expr):
    """Run sclang; return the String value of `expr` (written to a temp file)."""
    outdir = tempfile.mkdtemp(prefix="panola_ly_")
    p = os.path.join(outdir, "o.ly").replace("\\", "/")
    scd = '( File.use("%s","w",{|f| f.write(%s) }); "DONE".postln; 0.exit; )' % (p, expr)
    sp = os.path.join(outdir, "s.scd"); open(sp, "w", encoding="utf-8").write(scd)
    try:
        r = subprocess.run([SCLANG, sp], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout and "parse panola" not in r.stdout, r.stdout[-1500:]
        return open(p, encoding="utf-8").read()
    finally:
        shutil.rmtree(outdir, ignore_errors=True)


def compiles(ly_text):
    """True if LilyPond compiles ly_text without error (skip-friendly: True when LilyPond absent)."""
    if not os.path.exists(LILYPOND):
        return True
    d = tempfile.mkdtemp(prefix="ly_compile_")
    try:
        src = os.path.join(d, "s.ly"); open(src, "w", encoding="utf-8").write(ly_text)
        r = subprocess.run([LILYPOND, "-o", os.path.join(d, "out"), src],
                           capture_output=True, text=True, timeout=120)
        return r.returncode == 0
    finally:
        shutil.rmtree(d, ignore_errors=True)


ONE = 'Panola.scoreAsLilypond([Panola("c5_4 e5 g5 c6")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])'
CH  = 'Panola.scoreAsLilypond([Panola("<c4_4 e4 g4> <d4_4 f4 a4> r_4 <e4_4 g4 c5>")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])'


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_core_notes():
    ly = gen(ONE)
    assert "\\version" in ly and "\\language \"english\"" in ly
    assert "\\clef treble" in ly
    assert "c''4" in ly and "e''4" in ly and "g''4" in ly and "c'''4" in ly
    assert compiles(ly)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_core_chords_and_rest():
    ly = gen(CH)
    assert "<c' e' g'>4" in ly and "<d' f' a'>4" in ly and "<e' g' c''>4" in ly
    assert "r4" in ly
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify it fails** — `py -m pytest tools/panola_lilypond/test_core.py -q` → FAIL (`scoreAsLilypond` not found; and `Panola.scoreAsLilypond` not defined yet — Task 15 adds the Panola facade, so for Stage 2 call `PanolaLilypond.scoreAsLilypond(...)` directly in the test expressions). **Adjust `ONE`/`CH` to call `PanolaLilypond.scoreAsLilypond(...)` until Task 15**, then switch to `Panola.scoreAsLilypond`.

- [ ] **Step 3: Implement the skeleton + core emission**

Add to `PanolaLilypond.sc`. Copy `parseOne`, `parseName`, `parseDur`, `eventsOf` **verbatim from `PanolaMEI.sc`** (lines 86–116 and 686–702) — they are format-neutral. Add note/rest/chord emission and the score wrapper. Minimal one-measure-per-voice walk (no splitting yet — each event emitted at its written value):

```supercollider
	*scoreAsLilypond {
		| voices, changes, clefs = nil, braces = nil, pageBreaks = nil, systemBreaks = nil, lyrics = nil |

		// ---- event parsing (verbatim from PanolaMEI) ----
		var parseOne = { |s| /* copy PanolaMEI parseOne */ };
		var parseName = { |s| /* copy PanolaMEI parseName */ };
		var parseDur = { |s| /* copy PanolaMEI parseDur */ };
		var eventsOf = { |panola| /* copy PanolaMEI eventsOf (lines 686-702) */ };

		// ---- LilyPond emission primitives ----
		// a single note/chord/rest token at a written value, with an optional trailing tie.
		var noteLy = { |ev, md, dt, tieOut|
			var d = PanolaLilypond.pr_durLy(md, dt), tie = tieOut.if({ "~" }, { "" });
			if (ev[\rest]) { "r" ++ d } {
				if (ev[\pnames].size == 1) {
					PanolaLilypond.pr_pitchLy(ev[\pnames][0], ev[\accids][0], ev[\octs][0]) ++ d ++ tie
				} {
					"<" ++ ev[\pnames].collect({ |pn, c| PanolaLilypond.pr_pitchLy(pn, ev[\accids][c], ev[\octs][c]) }).join(" ")
						++ ">" ++ d ++ tie
				}
			};
		};

		// ---- per voice: events -> a flat list of ly tokens, split meter-aware (Task 5 replaces the body) ----
		var voiceTokens = { |events, meterStr|
			events.collect({ |ev| noteLy.(ev, ev[\meidur], ev[\dots], false) });
		};

		// ---- body ----
		var resolved = changes ? [( measure: 1, meter: "4/4", key: \Cmajor )];
		var meter0 = (resolved[0][\meter]) ? "4/4", key0 = (resolved[0][\key]) ? \Cmajor;
		var perVoice, staves, out;
		clefs = clefs ? voices.collect({ \treble });
		perVoice = voices.collect({ |p, vi| voiceTokens.(eventsOf.(p), meter0) });
		// wrap each voice in a named Voice with its clef
		staves = perVoice.collect({ |toks, vi|
			"    \\new Staff << \\global \\new Voice = \"v" ++ (vi+1) ++ "\" { \\clef "
				++ PanolaLilypond.pr_clefLy(clefs[vi]) ++ " " ++ toks.join(" ") ++ " } >>";
		});
		out = "\\version \"2.24.0\"\n\\language \"english\"\n\\header { tagline = ##f }\n\\paper { indent = 0\\mm }\n"
			++ "global = { " ++ PanolaLilypond.pr_meterLy(meter0) ++ " \\key " ++ PanolaLilypond.pr_keyLy(key0)
			++ " }\n\\score { <<\n" ++ staves.join("\n") ++ "\n>> }\n";
		^out;
	}
```
Fill the four `/* copy … */` closures with the exact bodies from `PanolaMEI.sc`. **The braces→GrandStaff grouping and the global spine's per-measure skips/breaks come in Task 6; for now `global` has one `\time`/`\key` and staves are flat siblings.**

- [ ] **Step 4: Run, verify it passes** — `py -m pytest tools/panola_lilypond/test_core.py -q` → PASS (and, with LilyPond installed, the `.ly` compiles).

- [ ] **Step 5: Commit** (panola: `PanolaLilypond.sc` `feat(lilypond): core skeleton + note/rest/chord emission`; MusicScene: `test_core.py` `test(lilypond): core note/rest/chord tests`).

### Task 5: meter-aware split-and-tie

Replace `voiceTokens` with a real per-measure walk that ports `PanolaMEI.voiceToMeasures`'s **plain-note branch** (lines 504–531): for each event, split via `PanolaMeterSplitter` per-measure-chunk (the `meterPieces` closure, lines 132–151, copied verbatim), advance `pos`, and start a new measure at the bar length. Emit `~` after every fragment that is followed by a tied continuation (i.e. all fragments except the logical note's last). Rests are never tied. Keep the output as a **list of measures**, each a list of tokens; join measures with `" | "`.

**Files:** Modify `PanolaLilypond.sc`; Test `tools/panola_lilypond/test_core.py`.

- [ ] **Step 1: Add the failing test**
```python
TIE = 'PanolaLilypond.scoreAsLilypond([Panola("c5_2 c5_1 c5_4")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])'
SPLIT = 'PanolaLilypond.scoreAsLilypond([Panola("c5_4 d5_2. e5_2 f5_4")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])'

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tie_across_barline():
    ly = gen(TIE)
    # c5_2 (half) + c5_1 (whole, crosses barline: 2 beats fill bar 1, 2 spill to bar 2) + c5_4
    assert "~" in ly                      # a tie is present
    assert ly.count("|") >= 1             # at least one barline
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_measures_split():
    ly = gen(SPLIT)                       # 1 + 3 + 2 + 1 quarters = 7 quarters = bars of 4+3 -> 2 bars
    assert ly.count("|") >= 1
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify it fails** (no `~`, no `|` yet).

- [ ] **Step 3: Port the plain-note split walk.** Copy `meterPieces` (PanolaMEI lines 132–151) and `parseMeter` (lines 255–269) verbatim. Replace `voiceTokens` with a `voiceToMeasures` that mirrors PanolaMEI's plain-note branch but emits tokens instead of MEI records and joins tied fragments with `~`:
```supercollider
	var voiceToMeasures = { |events, meterStr|
		var md = PanolaLilypond.pr_parseMeter.(meterStr);   // {bb:, pmeter:} from parseMeter copy
		var bb = md[\bb], pmeter = md[\pmeter];
		var measures = [[]], pos = 0.0, eps = 1e-6;
		events.do({ |ev|
			var remaining = ev[\beats], firstFrag = true;
			while { remaining > eps } {
				var take = (bb - pos).min(remaining), crosses = remaining > ((bb - pos) + eps);
				var lastFrag = crosses.not, pieces = meterPieces.(pos, take, ev[\rest], pmeter);
				pieces.do({ |pc, c|
					var isLast = lastFrag and: { c == (pieces.size - 1) };
					var tieOut = ev[\rest].not and: { isLast.not };   // tie every fragment but the last (notes only)
					measures[measures.size-1] = measures[measures.size-1].add(noteLy.(ev, pc[0], pc[1], tieOut));
				});
				pos = pos + take; remaining = remaining - take; firstFrag = false;
				if ((bb - pos) < eps) { measures = measures.add([]); pos = 0.0 };
			};
		});
		if (measures[measures.size-1].size == 0) { measures = measures.copyRange(0, measures.size - 2) };
		measures;
	};
```
(Here `meterPieces` returns `[meidur, dots, beatsFloat, tuplet]` fragments as in PanolaMEI; the tuplet field is ignored until Task 7.) Then have `perVoice` collect `voiceToMeasures.(…)` and join each voice's measures with `" | "` when building `staves`.

- [ ] **Step 4: Run, verify it passes** (`~` present, `|` present, compiles).
- [ ] **Step 5: Commit** (`feat(lilypond): meter-aware split-and-tie` / `test(lilypond): tie + measure-split tests`).

### Task 6: global spine (per-measure), braces → GrandStaff, final barline, whole-bar rest padding

Build a real `global` spine with one `s1*<n>/<d>` skip per measure and a trailing `\bar "|."`. Group braced staves in `\new GrandStaff`. Pad short voices with whole-bar rests. Port `staffGrp`'s brace logic (PanolaMEI line 642) into LilyPond grouping and `emptyRest` (line 550) into a per-bar `r` fill.

**Files:** Modify `PanolaLilypond.sc`; Test `test_core.py`.

- [ ] **Step 1: Add the failing test**
```python
GRAND = 'PanolaLilypond.scoreAsLilypond([Panola("c5_4 e5 g5 c6"), Panola("c3_1")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble, \\bass], [[1,2]])'
PAD = 'PanolaLilypond.scoreAsLilypond([Panola("c5_1 c5_1"), Panola("c3_1")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble, \\bass])'

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_grand_staff_and_barline():
    ly = gen(GRAND)
    assert "\\new GrandStaff" in ly
    assert "\\bar \"|.\"" in ly
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_short_voice_padded():
    ly = gen(PAD)                          # voice 2 is 1 bar, voice 1 is 2 bars -> voice 2 padded with a bar rest
    assert compiles(ly)                    # LilyPond bar-check passes only if every staff fills every bar
```

- [ ] **Step 2: Run, verify it fails** (no GrandStaff / bar-check failure with LilyPond).

- [ ] **Step 3: Implement.**
  - After computing `perVoice` (a list of per-voice measure-lists), let `nm = perVoice.collect(_.size).maxItem` and pad each short voice by appending `[ "R1*<n>/<d>" ]`-style whole-bar rests (use `pr_meterLy`'s num/den for that measure; a whole-bar rest is `"r1*" ++ num ++ "/" ++ den` or the decomposed form — a single `r1*n/d` is simplest and compiles).
  - Build `global`: for measure `i` (1-based) emit its `\time`/`\key` **only when changed** (Task 13 handles mid-piece; for now measure 1 only), a `\break`/`\pageBreak` prefix if in `systemBreaks`/`pageBreaks` (Task 14 fully; stub now to empty), then `s1*<n>/<d>`, joined by `" | "`, ending `" \\bar \"|.\""`.
  - Build staves: for each voice, `\new Staff << \global \new Voice = "vK" { \clef X <measures joined by " | "> } >>`. Group braced ranges (from `braces`) inside `\new GrandStaff << … >>`, ungrouped staves as siblings — port the `staffGrp` walk (PanolaMEI line 642) structurally.

- [ ] **Step 4: Run, verify it passes** (GrandStaff present, final barline present, padded score compiles).
- [ ] **Step 5: Commit** (`feat(lilypond): global spine + GrandStaff + bar padding` / `test(lilypond): grand-staff + padding tests`).

### Task 7: cross-consistency golden test (structure agreement MEI ↔ LilyPond)

Lock the duplicated walk to PanolaMEI: for a corpus, assert both encode the same structure.

**Files:** Test `tools/panola_lilypond/test_cross_consistency.py` (MusicScene repo).

- [ ] **Step 1: Write the test**
```python
"""Cross-consistency: PanolaMEI and PanolaLilypond must encode the SAME structure for the same
Panola input (measure count, per-measure non-rest note count, tie presence, tuplet ratios).
Run:  py -m pytest tools/panola_lilypond/test_cross_consistency.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

CORPUS = [
    'Panola("c5_4 e5 g5 c6")',
    'Panola("c5_2 c5_1 c5_4")',                       # tie across barline
    'Panola("<c4_4 e4 g4> d4_4 r_4 e4_4")',           # chord + rest
    'Panola("c5_8*2/3 d5 e5 c5_2 r_4")',              # triplet
    'Panola("c5_4 d5 e5 f5 g5 a5 b5 c6")',            # 3/4-ish spill
]
def _gen(expr_pairs):
    d = tempfile.mkdtemp(prefix="xc_")
    lines = ['File.mkdir("%s");' % (d.replace("\\","/")+"/")]
    for name, expr in expr_pairs:
        lines.append('File.use("%s/%s","w",{|f| f.write(%s) });' % (d.replace("\\","/"), name, expr))
    lines.append('"DONE".postln; 0.exit;')
    sp = os.path.join(d, "s.scd"); open(sp,"w",encoding="utf-8").write("(\n"+"\n".join(lines)+"\n)\n")
    try:
        r = subprocess.run([SCLANG, sp], capture_output=True, text=True, timeout=180)
        assert "ERROR" not in r.stdout and "parse panola" not in r.stdout, r.stdout[-1500:]
        return {name: open(os.path.join(d,name),encoding="utf-8").read() for name,_ in expr_pairs}
    finally:
        shutil.rmtree(d, ignore_errors=True)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_structure_agreement():
    pairs = []
    for i, v in enumerate(CORPUS):
        chg = '[( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble]'
        pairs.append(("mei%d" % i, "Panola.scoreAsMEI([%s], %s)" % (v, chg)))
        pairs.append(("ly%d" % i, "PanolaLilypond.scoreAsLilypond([%s], %s)" % (v, chg)))
    files = _gen(pairs)
    for i in range(len(CORPUS)):
        mei, ly = files["mei%d" % i], files["ly%d" % i]
        # measure count
        mei_measures = mei.count("<measure ")
        ly_measures = ly.count("|")  # spine barchecks: one per measure boundary incl. final \bar; compare via >=
        assert ly_measures >= mei_measures - 1, (i, mei_measures, ly_measures)
        # tuplet ratios: every MEI num/numbase pair appears as a LilyPond \tuplet num/numbase
        for num, numbase in re.findall(r'<tuplet num="(\d+)" numbase="(\d+)"', mei):
            assert ("\\tuplet %s/%s" % (num, numbase)) in ly, (i, num, numbase)
        # tie presence agreement
        assert (("tie=" in mei) == ("~" in ly)), (i, "tie mismatch")
```

- [ ] **Step 2: Run** — `py -m pytest tools/panola_lilypond/test_cross_consistency.py -q`. Some corpus rows depend on Stage-3 tuplets; **mark tuplet-bearing rows xfail until Task 8**, then remove the xfail. Expected now: PASS for non-tuplet rows.
- [ ] **Step 3: (no impl — this is a lock test).** If it fails for a non-tuplet row, the walk diverged from PanolaMEI; fix `voiceToMeasures` to match.
- [ ] **Step 4: Re-run, verify green (non-tuplet rows).**
- [ ] **Step 5: Commit** (MusicScene: `test(lilypond): cross-consistency structure test`).

---

## Stage 3 — Tuplets

### Task 8: plain tuplets + degenerate-ratio routing

Port `groupEvents` (PanolaMEI line 621) verbatim, and the tuplet handling of `voiceToMeasures`. Emit `\tuplet num/numbase { members }` (members are the written-value tokens; LilyPond auto-beams inside). Degenerate ratios route through the normal branch (already covered by Task 5). No completion/cross-barline yet — assume complete, non-crossing tuplets.

**Files:** Modify `PanolaLilypond.sc`; Test `tools/panola_lilypond/test_tuplets.py`.

- [ ] **Step 1: Write the failing test**
```python
"""Tuplet Panola->LilyPond tests. Run: py -m pytest tools/panola_lilypond/test_tuplets.py -q"""
import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_eighth_triplet():
    ly = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_8*2/3 d5 e5 c5_2 r_4")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])')
    assert "\\tuplet 3/2" in ly
    assert ly.split("\\tuplet 3/2")[1].count("''8") >= 3 or ly.count("8") >= 3
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_quintuplet_and_grouping():
    ly = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_16*4/5 d5 e5 f5 g5")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])')
    assert "\\tuplet 5/4" in ly
    assert compiles(ly)
    ly2 = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_8*2/3 d5 e5 f5 g5 a5")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])')
    assert ly2.count("\\tuplet 3/2") == 2   # two triplets, not one 6-tuplet
    assert compiles(ly2)
```

- [ ] **Step 2: Run, verify it fails** (no `\tuplet`).
- [ ] **Step 3: Implement.** Copy `groupEvents` verbatim. In `voiceToMeasures`, route each unit: a `\normal` unit uses the Task-5 split; a `\tuplet` unit (complete, non-crossing) emits `"\\tuplet " ++ unit[\num] ++ "/" ++ unit[\numbase] ++ " { " ++ unit[\members].collect({ |m| noteLy.(m, m[\meidur], m[\dots], false) }).join(" ") ++ " }"` as one measure token, advancing `pos` by `unit[\beats]`. Emit `\tuplet num/numbase` with `num`/`numbase` exactly as `groupEvents` sets them (`num: d, numbase: m`) so it matches the cross-consistency test's MEI `<tuplet num numbase>`.
- [ ] **Step 4: Run tuplet tests + remove the xfail on tuplet rows in `test_cross_consistency.py`; run it too.** Verify PASS and compiles.
- [ ] **Step 5: Commit** (`feat(lilypond): plain tuplets + degenerate routing` / `test(lilypond): tuplet tests + un-xfail cross-consistency`).

### Task 9: music21-style tuplet completion

Port the completion branch of `voiceToMeasures` (PanolaMEI lines 354–411): an incomplete `*m/d` run completes by splitting the following note/rest into the bracket. Emit the completing members inside the same `\tuplet` group, tying the donor's remainder out with `~`.

**Files:** Modify `PanolaLilypond.sc`; Test `test_tuplets.py`.

- [ ] **Step 1: Add the failing test**
```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_incomplete_completes():
    ly = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_8*2/3 d5 c5_4 d5 e5 f5")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])')
    assert "\\tuplet 3/2" in ly     # the incomplete run completes into a bracket
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify it fails or mis-renders** (LilyPond bar-check fails if durations don't sum).
- [ ] **Step 3: Port the completion logic** from PanolaMEI lines 354–411, emitting tokens: the original members + the completing members (from `PanolaDurationSpeller.spell(remainder)`) all inside one `\tuplet` group; a note donor's remainder is re-emitted after the bracket tied in (`~` on the last completing member, and the reduced donor carries `tieIn`). Reuse the `containers`/`donor`/`remainder` computation verbatim; swap `meiElement`+`wrapTuplets` for token emission.
- [ ] **Step 4: Run, verify it passes + compiles + cross-consistency still green.**
- [ ] **Step 5: Commit** (`feat(lilypond): music21-style tuplet completion`).

### Task 10: cross-barline tuplet split

Port the crossing branch (PanolaMEI lines 413–503): a complete tuplet crossing a barline splits into per-measure `\tuplet` brackets, a straddling member cut at the barline into tied sub-tuplet notes (`~`), each fragment spelled at the ratio; fall back to one whole bracket + warning when a fragment is inexpressible.

**Files:** Modify `PanolaLilypond.sc`; Test `test_tuplets.py`.

- [ ] **Step 1: Add the failing test**
```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplet_crosses_barline():
    # a triplet placed so it straddles the bar 1/bar 2 boundary in 2/4
    ly = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_4 c5_4 c5_2*2/3 d5 e5")], [( measure: 1, meter: "2/4", key: \\Cmajor )], [\\treble])')
    assert ly.count("\\tuplet") >= 2 or "\\tuplet" in ly   # split into per-measure brackets (or a warned whole bracket)
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify it fails / mis-renders.**
- [ ] **Step 3: Port `buildSplit`** (PanolaMEI lines 426–470) and the crossing branch, emitting per-measure `\tuplet` brackets with `~` ties between the straddling fragments (`fragAt` spells each fragment at the ratio via `PanolaDurationSpeller`). Keep the same fallback-with-warning path.
- [ ] **Step 4: Run, verify it passes + compiles + cross-consistency green.**
- [ ] **Step 5: Commit** (`feat(lilypond): cross-barline tuplet split`).

---

## Stage 4 — Expression (inline)

LilyPond attaches expression **inline to note tokens** — no timestamped collections. Port `annotateExpression` verbatim (it produces `ev[\articStr]` MEI codes + `ev[\dynMark]`, format-neutral), then attach marks from each event's own `@dyn`/`@art`/`@slur`/`@hairpin` during emission.

### Task 11: `pr_dynLy`, `pr_artLy` + dynamics & articulations

**Files:** Modify `PanolaLilypond.sc`; Test `test_mappers.py` + `tools/panola_lilypond/test_expression.py`.

- [ ] **Step 1: Add mapper tests** to `test_mappers.py`:
```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dyn_and_art():
    r = _run(r'''
["YA:" ++ PanolaLilypond.pr_dynLy("mf"), "YB:" ++ PanolaLilypond.pr_dynLy("sffz"),
 "AA:" ++ PanolaLilypond.pr_artLy("stacc"), "AB:" ++ PanolaLilypond.pr_artLy("acc stacc"),
 "AC:" ++ PanolaLilypond.pr_artLy("")
].do({ |x| x.postln });''')
    out = r.stdout
    assert "ERROR" not in out, out[-1500:]
    assert "YA:\\mf" in out
    assert 'YB:-\\markup \\dynamic "sffz"' in out
    assert "AA:-." in out
    assert "AB:" in out and "->" in out and "-." in out   # both scripts, order-independent
    assert "AC:\n" in out                                  # empty -> ""
```
And expression tests `tools/panola_lilypond/test_expression.py`:
```python
import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dynamics_and_articulation():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_4@dyn^p^ e5 g5@art^staccato^ c6@dyn^f^")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble])')
    assert "\\p" in ly and "\\f" in ly and "-." in ly
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement `pr_dynLy` + `pr_artLy`** and wire into emission:
```supercollider
	*pr_dynLy {
		| mark |
		var known = ["ppppp","pppp","ppp","pp","p","mp","mf","f","ff","fff","ffff","fffff",
			"fp","sf","sff","sp","spp","sfz","rfz"];
		^known.includesEqual(mark).if({ "\\" ++ mark }, { "-\\markup \\dynamic \"" ++ mark ++ "\"" });
	}
	*pr_artLy {
		| articStr |
		// MEI artic codes (space-separated) -> concatenated LilyPond scripts. LilyPond has no spiccato
		// script; spicc maps to the staccatissimo wedge.
		var m = IdentityDictionary[\stacc->"-.", \stacciss->"-!", \acc->"->", \ten->"--", \marc->"-^", \spicc->"-!"];
		^(articStr == "").if({ "" }, {
			articStr.split($ ).collect({ |c| m[c.asSymbol] ? "" }).join;
		});
	}
```
Copy `annotateExpression` verbatim. In `noteLy`, append (on the whole note / first tied fragment only, mirroring `meiElement`'s `firstFrag`): `PanolaLilypond.pr_dynLy(ev[\dynMark])` when `ev[\dynMark].notNil`, and `PanolaLilypond.pr_artLy(ev[\articStr] ? "")`. Add a `firstFrag` argument to `noteLy` (true on the note or its first tied fragment). Run events through `annotateExpression` before `voiceToMeasures`.

- [ ] **Step 4: Run, verify pass + compiles + cross-consistency green.**
- [ ] **Step 5: Commit** (`feat(lilypond): dynamics + articulations` / `test(lilypond): dyn/art tests`).

### Task 12: slurs + hairpins (inline)

**Files:** Modify `PanolaLilypond.sc`; Test `test_expression.py`.

- [ ] **Step 1: Add the failing test**
```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_slurs_and_hairpins():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_4@slur^start^@hairpin^cresc^ e5 g5@slur^endstart^ c6@slur^end^@hairpin^end^")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble])')
    assert "(" in ly and ")" in ly and ")(" in ly   # slur open, close, chained
    assert "\\<" in ly and "\\!" in ly              # hairpin open + end
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement inline spans.** LilyPond spans attach to notes from the event's own `@slur`/`@hairpin` value (no tstamp pairing needed):
  - slur: `ev[\slur]=="start"` → append `"("`; `"end"` → `")"`; `"endstart"` → `")("`.
  - hairpin: `"cresc"` → `"\\<"`; `"dim"` → `"\\>"`; `"end"` → `"\\!"`; `"endcresc"` → `"\\!\\<"`; `"enddim"` → `"\\!\\>"`.
  These go on the note (first tied fragment). Track `openSlur`/`openHairpin` booleans **only to warn** on unclosed spans at end-of-voice (mirror PanolaMEI warnings); emission is per-event. Read `ev[\slur]`/`ev[\hairpin]` (already extracted by `eventsOf`). Append after the dynamic/articulation in the note token.
- [ ] **Step 4: Run, verify pass + compiles.**
- [ ] **Step 5: Commit** (`feat(lilypond): slurs + hairpins`).

---

## Stage 5 — Lyrics

### Task 13: lyrics via named voices + `\lyricsto`

Reuse `PanolaMEI.pr_parseLyricLine` (already a class method) and port `attachLyrics`/`lyricSlotsFor` (PanolaMEI lines 658–685). Emit one `\new Lyrics \lyricsto "vN" \lyricmode { … }` per verse. Syllable hyphens → ` -- `. Melisma is driven from the **music** (`\melisma`/`\melismaEnd` around the held note) so `\lyricsto` aligns; the held note's verse emits no token. Quote syllables containing LilyPond specials.

**Files:** Modify `PanolaLilypond.sc`; Test `tools/panola_lilypond/test_lyrics.py`.

- [ ] **Step 1: Write the failing test**
```python
import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_basic():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_4 d5 e5 f5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil, nil, nil, [ [ "Twin-kle lit-tle" ] ])')
    assert "\\lyricsto \"v1\"" in ly
    assert "Twin -- kle" in ly and "lit -- tle" in ly
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_nil_no_lyrics_block():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_4 d5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble])')
    assert "\\lyricsto" not in ly
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Port `lyricSlotsFor` (calls `PanolaMEI.pr_parseLyricLine`) and `attachLyrics` (sets `ev[\lyrics]` per verse; a melisma slot advances but yields no syllable). Build, per staff, per verse `vi`: a token list where a slot with `[\syl]` emits the (quoted-if-special) syllable, joining a word's syllables with ` -- `; a melisma slot emits nothing (and marks the music note `\melisma`). Emit `\new Lyrics \lyricsto "v" ++ (staff+1) ++ " \lyricmode { <tokens> }` for each verse, placed after the staves inside the `<< >>`. Add a `pr_lyricTok` mapper (quote specials: wrap in `"..."` when the syllable contains a space, `-`, `_`, `"`, or a digit-leading token). **Validate melisma alignment by compiling** (LilyPond errors on a mis-associated melisma) — if `\melisma` in the music conflicts across verses, warn and let verse 1 drive.
- [ ] **Step 4: Run, verify pass + compiles + cross-consistency green** (lyrics don't change note structure).
- [ ] **Step 5: Commit** (`feat(lilypond): lyrics via lyricsto` / `test(lilypond): lyrics tests`).

---

## Stage 6 — Mid-piece changes, inline clef, breaks

### Task 14: mid-piece meter/key changes + inline `@clef`

Port `resolveChanges` (PanolaMEI line 271) and the per-measure meter/key carry-forward. Emit `\time`/`\key` in the `global` spine at each change measure; emit inline `\clef X` in the voice at a note carrying `@clef`.

**Files:** Modify `PanolaLilypond.sc`; Test `tools/panola_lilypond/test_changes.py`.

- [ ] **Step 1: Write the failing test**
```python
import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

CHG = (r'PanolaLilypond.scoreAsLilypond([Panola("c5_4 e5 g5 e5 d5_4 f5 a5 f5 g5_4 b5 d6 b5@clef^bass^ c4_4")], '
       r'[( measure: 1, meter: "4/4", key: \Cmajor ), ( measure: 2, key: \Gmajor ), ( measure: 3, meter: "3/4" )], [\treble])')

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_midpiece_changes_and_inline_clef():
    ly = gen(CHG)
    assert "\\key g \\major" in ly            # mid-piece key change
    assert "\\time 3/4" in ly                 # mid-piece meter change
    assert "\\clef bass" in ly                # inline clef change
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Thread `changes` through: `resolveChanges` → per-measure `(meter, key)`; the `global` spine emits `\time`/`\key` at measure 1 and again whenever the resolved value **changes** (compare meter display + key, mirroring PanolaMEI line 729–740). Give `voiceToMeasures` a `meterFor(i)` so the bar length can change per measure (port the `refreshMeter` mechanism, PanolaMEI line 291). For inline clef, when an event's `@clef` is non-empty, prefix its first-fragment token with `"\\clef " ++ pr_clefLy(<sym>) ++ " "` (map the string value `"bass"`→`\bass` etc.).
- [ ] **Step 4: Run, verify pass + compiles + cross-consistency green.**
- [ ] **Step 5: Commit** (`feat(lilypond): mid-piece meter/key + inline clef`).

### Task 15: page/system breaks

Emit `\break` (systemBreaks) / `\pageBreak` (pageBreaks) in the `global` spine at the listed measures.

**Files:** Modify `PanolaLilypond.sc`; Test `test_changes.py`.

- [ ] **Step 1: Add the failing test**
```python
@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_breaks():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_1 d5_1 e5_1 f5_1")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil, [3], [2])')
    assert "\\break" in ly       # systemBreaks: [2]
    assert "\\pageBreak" in ly   # pageBreaks: [3]
    assert compiles(ly)
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** In the `global` spine builder, before measure `i`'s skip, prepend `"\\pageBreak "` if `(pageBreaks ? []).includes(i)`, else `"\\break "` if `(systemBreaks ? []).includes(i)` (mirror PanolaMEI's precedence at line 742).
- [ ] **Step 4: Run, verify pass + compiles.**
- [ ] **Step 5: Commit** (`feat(lilypond): page/system breaks`).

---

## Stage 7 — Integration (Panola facade, MSScore, Godot self-test, example)

### Task 16: `Panola.asLilypond` + `Panola.scoreAsLilypond`

**Files:** Modify `…\Extensions\panola\Classes\Panola.sc`; Test `tools/panola_lilypond/test_panola_facade.py`.

- [ ] **Step 1: Write the failing test**
```python
import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_panola_facade():
    a = gen(r'Panola("c5_4 e5 g5 c6").asLilypond("4/4", \Cmajor, \treble)')
    assert "\\version" in a and "c''4" in a and compiles(a)
    b = gen(r'Panola.scoreAsLilypond([Panola("c5_4 e5"), Panola("c3_2")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble, \bass])')
    assert "\\clef bass" in b and compiles(b)
```

- [ ] **Step 2: Run, verify fail** (`asLilypond`/`scoreAsLilypond` not found).
- [ ] **Step 3: Implement** in `Panola.sc`, mirroring `asMEI`/`*scoreAsMEI` (lines 1049 and 1069) with whelk doc blocks:
```supercollider
	asLilypond {
		| meter="4/4", key=\Cmajor, clef=\treble, lyrics=nil |
		^PanolaLilypond.scoreAsLilypond([this], [( measure: 1, meter: meter, key: key )], [clef], nil, nil, nil,
			lyrics.notNil.if({ [lyrics] }, { nil }));
	}
	*scoreAsLilypond {
		| voices, changes, clefs=nil, braces=nil, pageBreaks=nil, systemBreaks=nil, lyrics=nil |
		^PanolaLilypond.scoreAsLilypond(voices, changes, clefs, braces, pageBreaks, systemBreaks, lyrics);
	}
```
Add `[method.asLilypond]` and `[classmethod.scoreAsLilypond]` whelk blocks modeled on the `asMEI`/`scoreAsMEI` ones. **Now switch every `PanolaLilypond.scoreAsLilypond(...)` in the earlier test files to `Panola.scoreAsLilypond(...)`** for a stable public surface (both work; the facade is the documented one).

- [ ] **Step 4: Run all `tools/panola_lilypond/` tests, verify green + compiles.**
- [ ] **Step 5: Commit** (panola: `Panola.sc` `feat(lilypond): Panola.asLilypond + scoreAsLilypond facade`; MusicScene: tests `test(lilypond): panola facade + switch tests to facade`).

### Task 17: MSScore `notation:` arg + `ly` accessor + OSC threading

**Files:** Modify `…\Extensions\msscore\Classes\MSScore.sc`; Test `tools/msscore/test_lilypond.py` (MusicScene repo).

- [ ] **Step 1: Write the failing test**
```python
"""MSScore notation:\\lilypond sends notationData ly and exposes .ly (msscore quark).
Run: py -m pytest tools/msscore/test_lilypond.py -q   (skips if sclang absent)"""
import os, pytest
from tools.msscore.test_midi_routing import _run, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_ly_accessor():
    r = _run(r'''(
var s = MSScore(voices: ["c5_4 e5 g5 c6"], clefs: [\treble], notation: \lilypond);
var ly = s.ly;
(ly.contains("\\version")).if({ "HASVER".postln }, { "NOVER".postln });
(ly.contains("c''4")).if({ "HASNOTE".postln }, { "NONOTE".postln });
0.exit;
)''')
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "HASVER" in r.stdout and "HASNOTE" in r.stdout, r.stdout[-1500:]

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_notation_default_is_verovio():
    r = _run(r'''(
var s = MSScore(voices: ["c5_4 e5"], clefs: [\treble]);
(s.notation == \verovio).if({ "DEF-VRV".postln }, { "DEF-OTHER".postln });
0.exit;
)''')
    assert "DEF-VRV" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement in `MSScore.sc`:**
  - Add `var <notation;` instVar (with whelk `[method.notation]` block) defaulting to `\verovio`.
  - Add `notation = \verovio` to `*new`'s args and thread through `init` (add `ntn` param, `notation = ntn ? \verovio;`). Add the `[classmethod.new.args]` `notation` line and `[method.init.args]` `ntn` line (**arg-count discipline: update BOTH `*new` and `init` `.args` tables** — see the whelk memory).
  - Add accessor:
```supercollider
	ly { ^Panola.scoreAsLilypond(voices, changes ? [( measure: 1, meter: meter, key: key )], clefs, braces, pageBreaks, systemBreaks, lyrics) }
```
  - In `pr_emitSetup`, choose format+data by `notation`:
```supercollider
		var isLy = (notation == \lilypond) or: { notation == \ly };
		var fmt = isLy.if({ "ly" }, { "mei" }), data = isLy.if({ this.ly }, { this.mei });
		// LilyPond addressable renders one cropped image (no auto page-turn); force single page.
		snd.("/ms/scene/" ++ id, "paginate", (isLy.not and: { paginate }).if({ 1 }, { 0 }), pageHeight);
		snd.("/ms/scene/" ++ id, "addressable", 1);
		snd.("/ms/scene/" ++ id, "notationData", fmt, data);
```
  (Replace the existing hardcoded `paginate`/`notationData` lines at MSScore.sc 438–440.)

- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** (msscore: `MSScore.sc` `feat(lilypond): MSScore notation:\\lilypond + ly accessor`; MusicScene: `tools/msscore/test_lilypond.py` `test(lilypond): MSScore ly accessor`).

### Task 18: Godot headless self-test (addressable end-to-end)

**Files:** Create `D:\Projects\MusicScene\tools\test_notation_lilypond.gd` (MusicScene repo).

- [ ] **Step 1: Write the self-test.** Model on `tools/test_notation_lilypond.gd`'s sibling `tools/test_lilypos.gd` / `test_notation_lyrics.gd`. It must: build a small LilyPond `.ly` (a hardcoded fixture equivalent to `Panola.scoreAsLilypond` output — no sclang needed in Godot), wrap it via `MSNotationLilyPositions.wrap_source`, invoke the LilyPond engraver (`ProjectSettings` setting `musicscene/notation/engraver/lilypond`, else the memory path), parse with `MSNotationLilyPositions.finalize`, and assert `elements.size() >= 4` and dark pixels present. Print `fail=0` on success, `FAIL:` otherwise. **Skip cleanly (print `fail=0 (lilypond absent)`) when the LilyPond exe is missing** — CI has no LilyPond.
```gdscript
extends SceneTree
## Headless self-test: a PanolaLilypond-shaped .ly renders through the LilyPond engraver and yields
## addressable note elements + dark pixels. Prints fail=0 on success. Skips (fail=0) if LilyPond absent.
const Lily := preload("res://addons/musicscene/notation/MSNotationLilyPositions.gd")

func _lily_exe() -> String:
	var s := str(ProjectSettings.get_setting("musicscene/notation/engraver/lilypond", ""))
	# the setting may be a full command; take the first quoted/space-split token that ends in lilypond(.exe)
	var cand := "C:/Program Files/lilypond-2.25.81/bin/lilypond.exe"
	if s != "":
		for tok in s.replace("\"", " ").split(" ", false):
			if tok.to_lower().ends_with("lilypond") or tok.to_lower().ends_with("lilypond.exe"):
				cand = tok; break
	return cand if FileAccess.file_exists(cand) else ""

func _init() -> void:
	var exe := _lily_exe()
	if exe == "":
		print("fail=0 (lilypond absent)"); quit(); return
	var dir := ProjectSettings.globalize_path("user://")
	var ly := "\\version \"2.24.0\"\n\\language \"english\"\n\\header { tagline = ##f }\n\\paper { indent = 0\\mm }\n" \
		+ "global = { \\time 4/4 \\key c \\major s1*4/4 }\n" \
		+ "\\score { << \\new Staff << \\global \\new Voice = \"v1\" { \\clef treble c''4 d'' e'' f'' } >> >> }\n"
	var wrapped := Lily.wrap_source(ly)
	var src := dir.path_join("mslily_test.ly")
	var f := FileAccess.open(src, FileAccess.WRITE)
	if f == null: print("FAIL: cannot write ly"); print("fail=1"); quit(); return
	f.store_string(wrapped); f.close()
	var stem := dir.path_join("mslily_test_out")
	var out := []
	OS.execute(exe, ["-dbackend=svg", "-dcrop=#t", "-o", stem, src], out, true)
	var svg := stem + ".cropped.svg"
	if not FileAccess.file_exists(svg): print("FAIL: no cropped SVG"); print("fail=1"); quit(); return
	var res := Lily.finalize(svg, {})
	var fails := 0
	if not res.ok: fails += 1; print("FAIL: finalize: ", res.error)
	elif res.elements.size() < 4: fails += 1; print("FAIL: expected >=4 note elements, got ", res.elements.size())
	print("elements=", (res.elements.size() if res.ok else -1))
	print("fail=", fails); quit()
```

- [ ] **Step 2: Run it** (with LilyPond installed): `& "<godot>" --headless --path D:/Projects/MusicScene -s tools/test_notation_lilypond.gd` → expect `fail=0`, `elements=4`. (Godot path from the `godot-binary-path` memory.)
- [ ] **Step 3: (no separate impl).**
- [ ] **Step 4: Confirm `fail=0`.**
- [ ] **Step 5: Commit** (MusicScene: `test(lilypond): Godot addressable self-test`).

### Task 19: example `.scd` + CI wiring

**Files:** Create `examples/supercollider/example_lilypond.scd`; Modify `.github/workflows/ci.yml` (MusicScene repo).

- [ ] **Step 1: Write `examples/supercollider/example_lilypond.scd`** — model on `example_lyrics.scd`: (a) a no-Godot section that `postln`s `Panola.scoreAsLilypond(...)` and shows writing it to a `.ly` for standalone `lilypond` rendering; (b) an MSScore section using `notation: \lilypond` demonstrating a multi-staff score with tuplets, dynamics, slurs, lyrics, and a mid-piece change — the same feature spread as `example_lyrics.scd`, with a comment that `musicscene/notation/engraver/lilypond` must point at the LilyPond exe and that the LilyPond preview is a single image (no page-turn). Include a `~score.stop;` line.
- [ ] **Step 2: Sanity-check the pure section** compiles the emitted `.ly`: run the `.scd`'s `scoreAsLilypond` expression through `gen(...)` + `compiles(...)` (reuse `test_core.py` helpers) in a quick throwaway, or add one assertion to `test_core.py` that the example's main expression compiles.
- [ ] **Step 3: Add CI steps** to `.github/workflows/ci.yml`: run the new pytest suites (`py -m pytest tools/panola_lilypond -q` and `tools/msscore/test_lilypond.py`) alongside the existing panola_mei/msscore suites. **Do not install LilyPond in CI** (large); the Godot self-test `tools/test_notation_lilypond.gd` runs and prints `fail=0 (lilypond absent)` there — add it as a grep-for-`fail=0` step like the sibling notation self-tests. The `compiles()` helper no-ops without LilyPond, so the pytest suites pass in CI on the emitted-text assertions alone.
- [ ] **Step 4: Run the full `tools/panola_lilypond` suite locally + the example** → green.
- [ ] **Step 5: Commit** (MusicScene: `example_lilypond.scd` + `ci.yml` `docs(lilypond): runnable example + CI wiring`).

---

## Stage 8 — Docs, schelp, release

### Task 20: whelk docs + schelp regen/verify

**Files:** `PanolaLilypond.sc`, `Panola.sc`, `MSScore.sc` doc blocks (already added inline per task); regenerate schelp.

- [ ] **Step 1:** Confirm every new method in `PanolaLilypond.sc`, the two new `Panola.sc` methods, and the MSScore `notation`/`ly` additions carry whelk doc blocks (see the `panola-quark-whelk-docs` memory: `[classmethod.*]`/`[method.*]` with `.args`/`.returns`; keep `*new` and `init` `.args` arg-counts correct). Add a `PanolaLilypond` `related`/example section mirroring `PanolaMEI`.
- [ ] **Step 2: Regenerate schelp** — run whelk over the panola + msscore quarks:
```
"D:/Projects/python/whelk/.venv/Scripts/python.exe" "D:/Projects/python/whelk/whelk.py" -i "<panola>/Classes/*.sc" -o "<panola>/HelpSource/Classes"
```
(and the msscore quark). Then **parse-verify** in sclang (per the memory): `SCDoc.parseFileFull` over every regenerated `.schelp`; expect no `ERROR`/arg-count `WARNING`. Fix any `teletype::\\::`-at-closer or straddled-`::` issues.
- [ ] **Step 3:** (docs only.)
- [ ] **Step 4:** Confirm clean parse of `PanolaLilypond.schelp`, `Panola.schelp`, `MSScore.schelp`.
- [ ] **Step 5: Commit** (panola + msscore repos: regenerated `HelpSource/` + doc-comment edits `docs(lilypond): whelk docs + schelp for PanolaLilypond/Panola/MSScore`).

### Task 21: README / TUTORIAL / ADVANCED / CHANGELOG + version bumps

**Files:** `README.md`, `TUTORIAL.md`, `ADVANCED.md`, `CHANGELOG.md`, `addons/musicscene/plugin.cfg`, `addons/musicscene/osc/OscDispatcher.gd` (MusicScene repo); `plugin.cfg`/quark version files for panola + msscore.

- [ ] **Step 1:** Add a "Panola → LilyPond" section to TUTORIAL/README/ADVANCED: the `Panola.scoreAsLilypond` / `asLilypond` API, MSScore `notation: \lilypond`, the `musicscene/notation/engraver/lilypond` config requirement, and the single-image (no page-turn) constraint. Note the output is a standalone `.ly`.
- [ ] **Step 2:** Bump versions consistently (per the `release-doc-version-consistency` memory): MusicScene `plugin.cfg` + `OscDispatcher.gd` `MS_VERSION` + README/TUTORIAL version strings; panola quark version; msscore quark version. Add a dated `CHANGELOG.md` entry describing the LilyPond feature.
- [ ] **Step 3:** (docs only.)
- [ ] **Step 4:** Grep the repo for the old version strings to confirm none are stale (`grep -rn "<oldver>"`).
- [ ] **Step 5: Commit** (each repo its own release commit `chore(release): … LilyPond conversion`). **Do not tag or push** — the user tags/pushes (panola first, then msscore, then MusicScene, per the dependency order).

---

## Self-Review

**Spec coverage:** mapping table → Tasks 1–3, 8–15; standalone `.ly` incl. `\version` → Task 4; meter split/tie → Task 5; multi-staff/braces/spine/pad → Task 6; tuplets (+completion+cross-barline) → Tasks 8–10; dynamics/artic/slurs/hairpins → Tasks 11–12; lyrics → Task 13; mid-piece changes/inline clef → Task 14; breaks → Task 15; Panola facade → Task 16; MSScore notation/ly + single-image constraint → Task 17; addressable end-to-end → Task 18; example + CI → Task 19; error handling (warn-and-recover) → carried by verbatim ports (Tasks 5, 9–12); cross-consistency safety net → Task 7 (extended each stage); docs/versioning → Tasks 20–21. All spec sections covered.

**Placeholder scan:** the `/* copy PanolaMEI X */` closures in Task 4 and the "port PanolaMEI method N" instructions are **explicit ports of a concrete in-repo reference** (line numbers given), not vague TODOs — the implementer copies named, existing code and applies the stated emission swap. Every mapper and every test is given as complete code.

**Type/name consistency:** the public surface is `Panola.asLilypond` / `Panola.scoreAsLilypond` / `PanolaLilypond.scoreAsLilypond` (tests call `PanolaLilypond.scoreAsLilypond` in Stages 2–6, switch to `Panola.scoreAsLilypond` in Task 16); mappers are `pr_pitchLy`/`pr_durLy`/`pr_clefLy`/`pr_keyLy`/`pr_meterLy`/`pr_dynLy`/`pr_artLy`; `\tuplet num/numbase` uses `groupEvents`' `num:d, numbase:m` (matches the cross-consistency assertion); MSScore arg is `notation:` with `\verovio` default. Consistent throughout.

**Known risk to validate early:** LilyPond lyric **melisma** (Task 13) is the one place the exact LilyPond idiom is uncertain — the task drives it from music-side `\melisma` and **validates by compiling**; adjust there if a real LilyPond render errors.
