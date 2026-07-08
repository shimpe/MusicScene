# Forced page & system breaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let authors force page and line breaks via `MSScore(pageBreaks: [...], systemBreaks: [...])`, emitting MEI `<pb/>`/`<sb/>` that the Verovio wrapper honors by auto-selecting its breaks mode.

**Architecture:** Three localized pieces: (1) `Panola.scoreAsMEI` emits `<pb/>`/`<sb/>` before listed measures; (2) MSScore forwards two lists; (3) `verovio_render.py` picks `encoded` (page breaks present), `line` (only system breaks), or `auto` (neither) from the MEI content. No Godot/GDScript change — the MEI is self-describing.

**Tech Stack:** SuperCollider (`.sc`), Python + pytest + sclang + Verovio (`tools/`), whelk/`gendoc.bat`, a `.scd` example.

---

## Repos, branches & conventions

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch `master`). `.sc` classes are **CRLF, TAB-indented** — read each anchor and match exactly; if an `Edit` literal won't match, use a byte-anchored replacement and verify tabs/CRLF with `cat -A`.
- **MSScore quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore` (branch `main`). `.sc` is **LF, TAB-indented**.
- **MusicScene** — `D:\Projects\MusicScene` (create branch `feature/panola-forced-breaks`; never work on `main`). Python tests, the Verovio wrapper (`addons/musicscene/tools/verovio_render.py`), the example, CHANGELOG.
- Python tests spawn a fresh `sclang` per run (auto-picks-up `.sc` edits). Use `py` (not `python`). Bash = Git Bash. Run only `tools/panola_mei/ tools/msscore/`.
- **Commit only after the user confirms** (executing this plan is such confirmation). End commit messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## Task 1: Panola `scoreAsMEI` emits `<pb/>` / `<sb/>`

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaMEI.sc` (`*scoreAsMEI` — the real implementation)
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\Panola.sc` (the public `*scoreAsMEI` **wrapper** at ~lines 1064-1067 that forwards to `PanolaMEI.scoreAsMEI`; it must accept + forward the two new args, exactly as it already forwards `changes`)
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_page_breaks.py` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/panola_mei/test_page_breaks.py`:

```python
"""Forced page/system break tests: Panola.scoreAsMEI emission + the Verovio wrapper's breaks-mode
auto-detection. Run:  py -m pytest tools/panola_mei/test_page_breaks.py -q  (sclang parts skip if absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.test_expression import _dump, SCLANG

# a 6-bar single voice (24 quarters in 4/4); breaks at measures 3 (page) and 5 (system)
SIXBAR = "c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5"
EMIT = {
  "brk":   r'Panola.scoreAsMEI([Panola("%s")], nil, [\treble], nil, [3], [5])' % SIXBAR,
  "nobrk": r'Panola.scoreAsMEI([Panola("%s")], nil, [\treble], nil, nil, nil)' % SIXBAR,
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_scoreasmei_emits_breaks():
    outdir = tempfile.mkdtemp(prefix="panola_brk_")
    try:
        _dump(outdir, EMIT)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in EMIT}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    assert '<pb/><measure n="3"' in meis["brk"], meis["brk"][:400]
    assert '<sb/><measure n="5"' in meis["brk"], meis["brk"][:400]
    # a call with nil lists emits no break milestones (byte-identical to before this feature)
    assert "<pb/>" not in meis["nobrk"]
    assert "<sb/>" not in meis["nobrk"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/panola_mei/test_page_breaks.py::test_scoreasmei_emits_breaks -q`
Expected: FAIL — `scoreAsMEI` ignores the two extra args (a SC keyword-arg warning) and emits no `<pb/>`/`<sb/>`. If SKIPPED (sclang absent), STOP and report BLOCKED.

- [ ] **Step 3: Add the two args to the `scoreAsMEI` signature**

In `PanolaMEI.sc`, the signature (~line 70) is:

```
		| voices, changes, clefs = nil, braces = nil |
```

Change it to:

```
		| voices, changes, clefs = nil, braces = nil, pageBreaks = nil, systemBreaks = nil |
```

- [ ] **Step 4: Emit the break before each listed measure**

In the measure-emitting loop `nm.do({ |i| ... })`, find this line (~673):

```
			body = body ++ "<measure n=\"" ++ (i+1) ++ "\">";
```

Immediately BEFORE it, insert (real tabs — same 3-tab indent as that line):

```
			if (i > 0) {
				if ((pageBreaks ? []).includes(i + 1)) { body = body ++ "<pb/>" }
				{ if ((systemBreaks ? []).includes(i + 1)) { body = body ++ "<sb/>" } };
			};
```

(`i` is 0-based, so `i + 1` is the 1-based measure number; `i > 0` skips a redundant break before measure 1. A `<pb/>` supersedes a `<sb/>` on the same measure. A `nil` list becomes `[]`, so a break-free score is byte-identical.)

- [ ] **Step 5: Run to verify it passes**

Run: `py -m pytest tools/panola_mei/test_page_breaks.py::test_scoreasmei_emits_breaks -q`
Expected: PASS.

- [ ] **Step 6: Regression — full panola_mei suite (byte-identity for break-free scores)**

Run: `py -m pytest tools/panola_mei/ -q`
Expected: all pass (existing scores emit no `<pb/>`/`<sb/>`, unchanged).

- [ ] **Step 7: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
feat(panola_mei): scoreAsMEI emits <pb/>/<sb/> from pageBreaks/systemBreaks

New trailing args pageBreaks/systemBreaks (1-based measure numbers) prepend a
page/system break milestone before those measures. nil lists = byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/panola_mei/test_page_breaks.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): scoreAsMEI emits <pb/> before m3 / <sb/> before m5

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `verovio_render.py` — pick the breaks mode from the MEI

**Files:**
- Modify: `D:\Projects\MusicScene\addons\musicscene\tools\verovio_render.py`
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_page_breaks.py`

- [ ] **Step 1: Write the failing tests**

Append to `tools/panola_mei/test_page_breaks.py`:

```python
_WRAP = os.path.join(os.path.dirname(__file__), "..", "..", "addons", "musicscene", "tools", "verovio_render.py")


def _mei(pb=False, sb=False):
    inner = ""
    for n in range(1, 7):
        brk = ("<pb/>" if (pb and n == 3) else "") + ("<sb/>" if (sb and n == 3) else "")
        inner += (brk + '<measure n="%d"><staff n="1"><layer n="1">'
                  '<note dur="1" oct="5" pname="c"/></layer></staff></measure>' % n)
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0">'
            '<music><body><mdiv><score>'
            '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
            '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
            '<section>' + inner + '</section></score></mdiv></body></music></mei>')


def _run_wrap(mei, height=700):
    d = tempfile.mkdtemp(prefix="brk_wrap_")
    try:
        inp = os.path.join(d, "s.mei")
        open(inp, "w", encoding="utf-8").write(mei)
        r = subprocess.run(["py", _WRAP, inp, os.path.join(d, "s.svg"),
                            "--paginate", "--page-height", str(height)],
                           capture_output=True, text=True)
        if "verovio not installed" in (r.stdout + r.stderr):
            pytest.skip("verovio not installed")
        return r.stdout + r.stderr
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_wrapper_detects_encoded_for_pb():
    assert "breaks=encoded" in _run_wrap(_mei(pb=True))


def test_wrapper_detects_line_for_sb_only():
    assert "breaks=line" in _run_wrap(_mei(sb=True))


def test_wrapper_auto_without_breaks():
    assert "breaks=auto" in _run_wrap(_mei())
```

- [ ] **Step 2: Run to verify they fail**

Run: `py -m pytest tools/panola_mei/test_page_breaks.py -k wrapper -q`
Expected: FAIL — the wrapper never prints `breaks=...` yet, and its default mode is `auto` regardless of content.

- [ ] **Step 3: Change the `--breaks` default to `detect`**

In `verovio_render.py`, the arg (~line 47) is:

```python
    ap.add_argument("--breaks", default="auto")  # "none" = single system strip
```

Change the default to `detect`:

```python
    ap.add_argument("--breaks", default="detect")  # detect: encoded if <pb>, line if <sb>, else auto
```

- [ ] **Step 4: Resolve the mode before `setOptions`**

Immediately AFTER `a = ap.parse_args()` and BEFORE `tk = verovio.toolkit()` (~line 53-55), insert:

```python
    breaks = a.breaks
    if breaks == "detect":
        try:
            _src = open(a.input, encoding="utf-8", errors="ignore").read()
        except OSError:
            _src = ""
        breaks = "encoded" if "<pb" in _src else ("line" if "<sb" in _src else "auto")
```

- [ ] **Step 5: Use the resolved `breaks` in both `setOptions` calls**

There are two `"breaks": a.breaks,` lines (the paginate branch ~line 62 and the else branch ~line 68). Change BOTH `a.breaks` to `breaks`:

```python
            "breaks": breaks, "scale": a.scale, "header": "none", "footer": "none",
```

- [ ] **Step 6: Report the resolved mode in both stdout prints**

The paginate print (~line 81):

```python
        print("verovio: wrote %d page(s) %s-N.svg%s" % (n, stem, " + timemap" if a.timemap else ""))
```

becomes:

```python
        print("verovio: wrote %d page(s) %s-N.svg%s (breaks=%s)" % (n, stem, " + timemap" if a.timemap else "", breaks))
```

The single-page print (~line 88):

```python
    print("verovio: wrote " + a.output + (" + timemap" if a.timemap else ""))
```

becomes:

```python
    print("verovio: wrote " + a.output + (" + timemap" if a.timemap else "") + (" (breaks=%s)" % breaks))
```

- [ ] **Step 7: Run to verify the wrapper tests pass**

Run: `py -m pytest tools/panola_mei/test_page_breaks.py -k wrapper -q`
Expected: PASS (`breaks=encoded` for `<pb>`, `breaks=line` for `<sb>`-only, `breaks=auto` for neither).

- [ ] **Step 8: Regression — full panola_mei suite**

Run: `py -m pytest tools/panola_mei/ -q`
Expected: all pass — existing break-free renders now resolve `detect → auto`, i.e. unchanged output.

- [ ] **Step 9: Commit**

```bash
git -C "D:/Projects/MusicScene" add addons/musicscene/tools/verovio_render.py tools/panola_mei/test_page_breaks.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
feat(verovio): auto-select breaks mode from the MEI (encoded/line/auto)

--breaks defaults to `detect`: encoded when the MEI carries <pb>, line when it
carries only <sb>, else auto (unchanged). Reports the resolved mode on stdout.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: MSScore `pageBreaks` / `systemBreaks` args

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore\Classes\MSScore.sc`
- Test: `D:\Projects\MusicScene\tools\msscore\test_page_breaks.py` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/msscore/test_page_breaks.py`:

```python
"""MSScore forwards pageBreaks/systemBreaks into the MEI it builds (msscore quark).
Run:  py -m pytest tools/msscore/test_page_breaks.py -q  (skips if sclang absent)
"""
import os, pytest
from tools.msscore.test_midi_routing import _run, SCLANG

SIXBAR = "c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5"
SCRIPT = r'''(
var s = MSScore(voices: ["%s"], pageBreaks: [3], systemBreaks: [5]);
var m = s.mei;
(m.contains("<pb/><measure n=\"3\"")).if({ "PB-OK".postln }, { "PB-BAD".postln });
(m.contains("<sb/><measure n=\"5\"")).if({ "SB-OK".postln }, { "SB-BAD".postln });
0.exit;
)''' % SIXBAR


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_msscore_forwards_breaks():
    r = _run(SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "PB-OK" in r.stdout, r.stdout[-1500:]
    assert "SB-OK" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/msscore/test_page_breaks.py -q`
Expected: FAIL — MSScore doesn't know `pageBreaks`/`systemBreaks` (SC keyword-arg warning, args ignored), so `mei` emits no breaks → `PB-BAD`/`SB-BAD`.

- [ ] **Step 3: Add instance vars (with whelk docs)**

In `MSScore.sc`, find `var <changes;` (~line 123). Immediately after it, add:

```
	/*
	[method.pageBreaks]
	description = "list of 1-based measure numbers where a new PAGE starts (nil for none). Emits MEI <pb/> and switches the render to manual pagination — you control every page boundary and auto page-fill is off (Verovio limitation). Use with paginate:true; pageHeight sets the page size."
	[method.pageBreaks.returns]
	what = "an Array of measure numbers, or nil"
	*/
	var <pageBreaks;

	/*
	[method.systemBreaks]
	description = "list of 1-based measure numbers where a new SYSTEM (line) starts (nil for none). Emits MEI <sb/>; unlike pageBreaks, auto pagination is kept (pages still fill by pageHeight)."
	[method.systemBreaks.returns]
	what = "an Array of measure numbers, or nil"
	*/
	var <systemBreaks;
```

- [ ] **Step 4: Add the args to `*new` and the `super.new.init` call**

The `*new` signature (~lines 287-290) ends with `... listenPort = 7400, changes |`. Change the last line to append the two args:

```
		showCursor = true, host = "127.0.0.1", listenPort = 7400, changes, pageBreaks, systemBreaks |
```

The `super.new.init(...)` call (~line 291) ends `... listenPort, changes);`. Change it to:

```
		^super.new.init(voices, clefs, meter, key, braces, tempo, instruments, backends, midiOut, channels, wrap, id, space, scale, showDelay, paginate, pageHeight, showCursor, host, listenPort, changes, pageBreaks, systemBreaks);
```

- [ ] **Step 5: Add the params to `init` and assign them**

The `init` signature (~line 320) ends `... lport, chg |`. Change to:

```
	init { | v, cl, m, k, br, t, instr, bk, mo, ch, wr, i, sp, sc, sd, pg, ph, scr, host, lport, chg, pgbr, sysbr |
```

Find the `changes = chg;` line (~line 324) and add the two assignments after it:

```
		pageBreaks = pgbr;                                 // nil -> no forced page breaks (auto-pagination)
		systemBreaks = sysbr;                              // nil -> no forced system/line breaks
```

- [ ] **Step 6: Forward them in the `mei` method**

The `mei` method (~line 385) is:

```
	mei { ^Panola.scoreAsMEI(voices, changes ? [( measure: 1, meter: meter, key: key )], clefs, braces) }
```

Change it to:

```
	mei { ^Panola.scoreAsMEI(voices, changes ? [( measure: 1, meter: meter, key: key )], clefs, braces, pageBreaks, systemBreaks) }
```

- [ ] **Step 7: Run to verify it passes**

Run: `py -m pytest tools/msscore/test_page_breaks.py -q`
Expected: PASS (`PB-OK`, `SB-OK`).

- [ ] **Step 8: Full Panola + MSScore suites (regression)**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass (existing MSScore scores pass `nil`/`nil`, byte-identical).

- [ ] **Step 9: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "$(cat <<'EOF'
feat(msscore): pageBreaks / systemBreaks args (forced page & line breaks)

Two optional lists of 1-based measure numbers forwarded to scoreAsMEI, which
emits <pb/>/<sb/>. nil defaults keep today's auto-pagination byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/msscore/test_page_breaks.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(msscore): pageBreaks/systemBreaks reach the MEI (<pb/> m3, <sb/> m5)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Docs — whelk + schelp regen (both quarks)

**Files:**
- Modify: `Classes/PanolaMEI.sc` (`scoreAsMEI` arg docs + `[general]`), `Classes/MSScore.sc` (`[general]`)
- Regenerate: both `HelpSource/Classes/*.schelp`

- [ ] **Step 1: Panola `scoreAsMEI` arg docs**

In `PanolaMEI.sc`, the `[classmethod.scoreAsMEI.args]` block documents `voices`/`changes`/`clefs`/`braces`. After the `braces = "..."` line, add:

```
	pageBreaks = "an Array of 1-based measure numbers where a new PAGE starts (nil for none), emitting a mid-section teletype::<pb/>::. Verovio then paginates strong::only:: at these marks (manual pagination — auto page-fill is off)."
	systemBreaks = "an Array of 1-based measure numbers where a new SYSTEM (line) starts (nil for none), emitting teletype::<sb/>::. Unlike pageBreaks, automatic pagination is kept."
```

- [ ] **Step 2: Panola `[general]` paragraph**

In the `PanolaMEI.sc` `[general]` description, after the `@hairpin` paragraph (search for `spans become slurs.`), add:

```
Forced breaks: pass teletype::pageBreaks:: / teletype::systemBreaks:: (Arrays of 1-based measure
numbers) to start a new strong::page:: (teletype::<pb/>::) or strong::system:: (teletype::<sb/>::)
at those measures. Page breaks switch to manual pagination (auto page-fill off); system breaks keep
auto pagination. The renderer selects the mode from the encoded breaks.
```

- [ ] **Step 3: MSScore `[general]` paragraph**

In `MSScore.sc` `[general]` description, after the display-only paragraph (search for `Display only`), add:

```
strong::Forced breaks:: — teletype::pageBreaks: [5, 9]:: starts a new page at those bars (manual
pagination: you control every page boundary, auto page-fill is off), and teletype::systemBreaks: [3]::
starts a new line while keeping auto pagination. Use with teletype::paginate: true::.
```

- [ ] **Step 4: Regenerate both schelps**

Run `gendoc.bat` at each quark root (via PowerShell if Git Bash `cd` fails: `Set-Location "<quark>"; .\gendoc.bat`):
- panola: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola`
- msscore: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore`
Expected: each ends with `Done.`, no `ERROR`.

- [ ] **Step 5: Verify + confirm classes still compile**

Run: `grep -l "pageBreaks" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMEI.schelp" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore/HelpSource/Classes/MSScore.schelp"`
Expected: both files listed.
Run: `py -m pytest tools/panola_mei/test_page_breaks.py tools/msscore/test_page_breaks.py -q`
Expected: PASS (fresh sclang compiles both edited classes).

- [ ] **Step 6: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
docs(panola_mei): document pageBreaks/systemBreaks; regenerate schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc HelpSource/Classes/MSScore.schelp
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "$(cat <<'EOF'
docs(msscore): document pageBreaks/systemBreaks; regenerate schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: SuperCollider example

**Files:**
- Create: `D:\Projects\MusicScene\examples\supercollider\example_forced_breaks.scd`

- [ ] **Step 1: Write the example**

Create `examples/supercollider/example_forced_breaks.scd`:

```supercollider
// =============================================================================
// MSScore forced page & system breaks — control where pages and lines break.
//
//   pageBreaks:   [n, ...]  -> a new PAGE starts at those bars (MEI <pb/>). This is MANUAL
//                             pagination: you control every page boundary and auto page-fill is
//                             OFF (Verovio can't mix the two). pageHeight sets the page size.
//   systemBreaks: [n, ...]  -> a new SYSTEM (line) starts at those bars (MEI <sb/>). Auto
//                             pagination is KEPT (pages still fill by pageHeight).
//
// REQUIRES: the MSScore quark (Quarks.install), MusicScene running with Verovio.
// USAGE: run the Godot project (one instance), set ~space, put the cursor in the ( ) block, Ctrl+Enter.
//        showPage(n) shows a given page; page(n)/nextPage/prevPage flip.
// =============================================================================

(
// Two 4-bar phrases (8 bars). Force a PAGE break at bar 5 (second phrase on its own page) and a
// SYSTEM break at bar 3 (so bars 1-2 and 3-4 are separate lines on page 1).
~voice = "c5_4 e5 g5 e5 d5_4 f5 a5 f5 e5_4 g5 b5 g5 f5_4 a5 c6 a5 " ++
         "g5_4 e5 c5 e5 f5_4 d5 b4 d5 e5_4 c5 g4 c5 c5_1";

~score = MSScore(
	voices:      [~voice],
	clefs:       [\treble],
	meter:       "4/4", key: \Cmajor, tempo: 92,
	scale:       1.0,
	paginate:    true, pageHeight: 900,
	pageBreaks:   [5],   // new PAGE at bar 5
	systemBreaks: [3],   // new LINE at bar 3 (page 1)
	space:       "3d"
);

~score.showPage(1);   // page 1 = bars 1-4 (two lines: 1-2 | 3-4); page 2 = bars 5-8
"Forced breaks: page break at bar 5, line break at bar 3. Try ~score.showPage(2) / nextPage.".postln;
)


// ~score.showPage(2);   // the second page (bars 5-8)
// ~score.stop;          // clear the scene
```

- [ ] **Step 2: Verify the example renders the intended layout**

Build the example's MEI via sclang and confirm the break milestones + page count. Run (Git Bash):
write a scratch `.scd` that sets `~voice` and `s = MSScore(... pageBreaks:[5], systemBreaks:[3] ...)`, writes `s.mei` to a temp file, then:
```
grep -c "<pb/><measure n=\"5\"" <mei>    # expect 1
grep -c "<sb/><measure n=\"3\"" <mei>    # expect 1
py "D:/Projects/MusicScene/addons/musicscene/tools/verovio_render.py" <mei> <out.svg> --paginate --page-height 900
# expect: "wrote 2 page(s) ... (breaks=encoded)"  (the <pb/> forces manual pagination -> 2 pages)
```
Expected: the two greps return 1, and the wrapper reports 2 pages with `breaks=encoded`.

- [ ] **Step 3: Commit**

```bash
git -C "D:/Projects/MusicScene" add examples/supercollider/example_forced_breaks.scd
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs(examples): example_forced_breaks.scd — forced page & system breaks

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: CHANGELOG + finish

- [ ] **Step 1: CHANGELOG entry**

In `CHANGELOG.md`, add an `### Added` bullet under the top `## [0.17.0] — 2026-07-08` entry (still unreleased):

```
- **Forced page & system breaks in Panola notation.** `MSScore(pageBreaks: [5, 9], systemBreaks: [3])`
  (and `Panola.scoreAsMEI`'s new `pageBreaks`/`systemBreaks` args) emit MEI `<pb/>`/`<sb/>`. A page
  break switches to manual pagination (auto page-fill off — a Verovio constraint); a system break
  forces a line while keeping auto pagination. The bundled `verovio_render.py` auto-selects its
  breaks mode from the encoded breaks (encoded / line / auto). Example:
  `examples/supercollider/example_forced_breaks.scd`. (PanolaMEI + MSScore quarks; verovio wrapper.)
```

- [ ] **Step 2: Full suite green**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass.

- [ ] **Step 3: Commit docs (incl. spec + plan)**

```bash
git -C "D:/Projects/MusicScene" add CHANGELOG.md docs/superpowers/specs/2026-07-08-panola-forced-breaks-design.md docs/superpowers/plans/2026-07-08-panola-forced-breaks.md
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs: CHANGELOG + spec + plan for forced page & system breaks

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Finish the branch**

Use **superpowers:finishing-a-development-branch** for MusicScene `feature/panola-forced-breaks`. The Panola (`master`) and MSScore (`main`) quark commits are on their own repos. A release/tag is a separate step per [[release-doc-version-consistency]], only if the user asks.

---

## Self-review

**Spec coverage:**
- `scoreAsMEI` emits `<pb/>`/`<sb/>` from the two lists → Task 1. ✓
- MSScore `pageBreaks`/`systemBreaks` args → Task 3. ✓
- Wrapper `detect` (encoded / line / auto) → Task 2. ✓
- Manual-pagination vs auto-fill semantics → documented Task 4; enforced by the wrapper mode. ✓
- Measure 1 ignored, `<pb>` supersedes `<sb>`, nil = byte-identical → Task 1 Step 4 + regression steps. ✓
- Tests (emission, wrapper detect ×3, MSScore pass-through) → Tasks 1-3. ✓
- Docs + schelp (both quarks) → Task 4. Example → Task 5. CHANGELOG → Task 6. ✓
- No Godot change → confirmed; no task touches `.gd`. ✓

**Placeholder scan:** No TBD/TODO/"similar to". All code shown; commands concrete with expected output.

**Type/name consistency:** `pageBreaks`/`systemBreaks` used consistently across `scoreAsMEI` (Task 1), MSScore vars/args/`mei` (Task 3), and docs (Task 4). The MEI substrings asserted in tests (`<pb/><measure n="3"`, `<sb/><measure n="5"`) match the emission in Task 1 Step 4. The wrapper's `breaks` variable + `breaks=%s` stdout (Task 2) match the `-k wrapper` asserts. MSScore `init` param names (`pgbr`, `sysbr`) are assigned to the `pageBreaks`/`systemBreaks` vars and forwarded in `mei`.
