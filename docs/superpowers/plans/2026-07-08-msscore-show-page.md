# MSScore showPage / page navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `MSScore.showPage(n)` (display a page — no cursor, no playback) plus `page(n)` / `nextPage` / `prevPage` navigation, with no Godot-side change.

**Architecture:** `show`'s OSC-setup body is extracted into a private `pr_emitSetup(cursorOn)` so `show` stays byte-identical while `showPage` reuses it with the cursor forced off, then sends the existing `/ms/scene/<id> page n` verb after a render-settle wait. Nav methods are one-line synchronous OSC sends over the verbs the Godot `MSNotationObject` already handles (`page`/`nextpage`/`prevpage`, 1-based, clamped).

**Tech Stack:** SuperCollider (`MSScore.sc`), Python + pytest + sclang with `OSCdef`-capture (no Godot/audio server), whelk/`gendoc.bat`, a `.scd` example.

---

## Repos, branches & conventions

- **MSScore quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore` (branch `main`). `.sc` + `HelpSource` schelp.
- **MusicScene** — `D:\Projects\MusicScene` (create branch `feature/msscore-show-page`; never work on `main`). Python tests, example, CHANGELOG.
- `.sc` files: check whether they are LF or CRLF before editing and match exactly (read the anchor first; if an `Edit` literal won't match, use a byte-anchored replacement and verify).
- Python tests spawn a fresh `sclang` per run. Use `py` (not `python`). Bash = Git Bash. Run only `tools/msscore/ tools/panola_mei/`.
- **Commit only after the user confirms** (executing this plan is such confirmation). End commit messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

Reference — the current `show` method in `MSScore.sc` (~lines 386–399), whose body Task 2 extracts:

```
	show {
		var m = this.mei;
		Routine({
			var snd = { |... a| engine.sendMsg(*a); 0.02.wait };
			snd.("/ms/scene/" ++ id, "new", "notation");
			snd.("/ms/scene/" ++ id, "background", "white");
			snd.("/ms/scene/" ++ id, "scale", scale);
			if (space == "3d") { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0, 0.0) } { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0) };
			snd.("/ms/scene/" ++ id ++ "/cursor", "show", showCursor.if({ 1 }, { 0 }));
			snd.("/ms/scene/" ++ id, "paginate", paginate.if({ 1 }, { 0 }), pageHeight);
			snd.("/ms/scene/" ++ id, "addressable", 1);
			snd.("/ms/scene/" ++ id, "notationData", "mei", m);
		}).play;
	}
```

---

## Task 1: Page-navigation methods (`page` / `nextPage` / `prevPage`)

Simple synchronous OSC sends over the verbs `MSNotationObject` already handles. `showPage` (Task 2) reuses `page`.

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore\Classes\MSScore.sc`
- Create: `D:\Projects\MusicScene\tools\msscore\test_show_page.py`

- [ ] **Step 1: Write the failing test**

Create `tools/msscore/test_show_page.py`:

```python
"""MSScore page navigation + showPage tests (msscore quark).
OSCdef-captures the OSC MSScore emits (engine points at NetAddr.langPort) -- no Godot, no audio.
Run:  py -m pytest tools/msscore/test_show_page.py -q   (skips if sclang absent)
"""
import os, pytest
from tools.msscore.test_midi_routing import _run, SCLANG

NAV_SCRIPT = r'''(
var s, got = List.new;
OSCdef(\capN, { |msg| got.add(msg) }, '/ms/scene/scoreNav');
Routine({
    s = MSScore(voices: ["c5_4 e5 g5 c6"], id: "scoreNav", host: "127.0.0.1", listenPort: NetAddr.langPort);
    s.page(4); 0.1.wait;
    s.nextPage; 0.1.wait;
    s.prevPage; 0.1.wait;
    got.do({ |m|
        if (m[1] == \page) { ("PAGE:" ++ m[2].asString).postln };
        if (m[1] == \nextpage) { "NEXT".postln };
        if (m[1] == \prevpage) { "PREV".postln };
    });
    OSCdef(\capN).free;
    0.exit;
}).play;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_page_navigation():
    r = _run(NAV_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "PAGE:4" in r.stdout, r.stdout[-1500:]
    assert "NEXT" in r.stdout, r.stdout[-1500:]
    assert "PREV" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/msscore/test_show_page.py::test_page_navigation -q`
Expected: FAIL — `page`/`nextPage`/`prevPage` don't exist, so sclang prints an error (`doesNotUnderstand`) and `PAGE:4` never appears. If SKIPPED (sclang absent), STOP and report BLOCKED.

- [ ] **Step 3: Add the three methods**

In `MSScore.sc`, immediately after the `stop { ... }` method (it ends `		engine.sendMsg("/ms/scene", "clear");` then `	}`), add the whelk-documented navigation methods (match the file's existing indentation — methods are one tab in; the doc comments use the `/* [method.NAME] ... */` form seen elsewhere in the file):

```
	/*
	[method.page]
	description = "on an already-shown score, jump to a 1-based page (MusicScene clamps out-of-range). Distinct pages need a paginated score (the default); otherwise MusicScene re-renders that page."
	[method.page.args]
	pageNumber = "the 1-based page to show"
	*/
	page { | pageNumber = 1 | engine.sendMsg("/ms/scene/" ++ id, "page", pageNumber); }

	/*
	[method.nextPage]
	description = "flip the shown score forward one page"
	*/
	nextPage { engine.sendMsg("/ms/scene/" ++ id, "nextpage"); }

	/*
	[method.prevPage]
	description = "flip the shown score back one page"
	*/
	prevPage { engine.sendMsg("/ms/scene/" ++ id, "prevpage"); }
```

- [ ] **Step 4: Run to verify it passes**

Run: `py -m pytest tools/msscore/test_show_page.py::test_page_navigation -q`
Expected: PASS (`PAGE:4`, `NEXT`, `PREV` all printed).

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "$(cat <<'EOF'
feat(msscore): page/nextPage/prevPage navigation methods

Thin wrappers over the /ms/scene/<id> page|nextpage|prevpage OSC verbs.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/msscore/test_show_page.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(msscore): page/nextPage/prevPage emit the right OSC verbs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `showPage` + byte-safe `show` refactor

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore\Classes\MSScore.sc`
- Test: `D:\Projects\MusicScene\tools\msscore\test_show_page.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/msscore/test_show_page.py`:

```python
# showPage: display-only. It emits the same notation setup as show() but with the cursor forced
# OFF, then (after showDelay) a `page n`. It starts NO playback (player/clock stay nil).
# showDelay is set to 0.1 so the test is quick.
SHOWPAGE_SCRIPT = r'''(
var s, got = List.new, cur = List.new;
OSCdef(\capP, { |msg| got.add(msg) }, '/ms/scene/scorePage');
OSCdef(\capPc, { |msg| cur.add(msg) }, '/ms/scene/scorePage/cursor');
Routine({
    s = MSScore(voices: ["c5_4 e5 g5 c6 d5 f5 a5 c6"], id: "scorePage", showDelay: 0.1,
                host: "127.0.0.1", listenPort: NetAddr.langPort);
    s.showPage(2);
    0.6.wait;   // > showDelay, so the deferred `page 2` has been sent
    got.do({ |m| if (m[1] == \page) { ("PAGE:" ++ m[2].asString).postln } });
    cur.do({ |m| if (m[1] == \show) { ("CURSOR:" ++ m[2].asString).postln } });
    ("PLAYER_NIL:" ++ s.player.isNil.asString).postln;
    ("CLOCK_NIL:" ++ s.clock.isNil.asString).postln;
    OSCdef(\capP).free; OSCdef(\capPc).free;
    0.exit;
}).play;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_show_page_display_only():
    r = _run(SHOWPAGE_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "PAGE:2" in r.stdout, r.stdout[-1500:]      # navigated to the requested page
    assert "CURSOR:0" in r.stdout, r.stdout[-1500:]    # cursor forced off
    assert "PLAYER_NIL:true" in r.stdout, r.stdout[-1500:]   # no playback started
    assert "CLOCK_NIL:true" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/msscore/test_show_page.py::test_show_page_display_only -q`
Expected: FAIL — `showPage` doesn't exist (`doesNotUnderstand`), so `PAGE:2` never prints.

- [ ] **Step 3: Refactor `show` into `pr_emitSetup` + add `showPage`**

Replace the whole current `show { ... }` method (the Reference block at the top of this plan) with a private emitter plus a thin `show`, and add `showPage` right after. Match the file's tab indentation exactly:

```
	/*
	[method.pr_emitSetup]
	description = "(private) emit the notation-display OSC setup (create node, background, scale, pos, cursor, paginate, addressable, notationData). Runs INSIDE a Routine (uses waits). cursorOn draws the cursor line or not."
	[method.pr_emitSetup.args]
	cursorOn = "true to draw the cursor line, false to hide it"
	*/
	pr_emitSetup { | cursorOn |
		var m = this.mei;
		var snd = { |... a| engine.sendMsg(*a); 0.02.wait };
		snd.("/ms/scene/" ++ id, "new", "notation");
		snd.("/ms/scene/" ++ id, "background", "white");
		snd.("/ms/scene/" ++ id, "scale", scale);
		if (space == "3d") { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0, 0.0) } { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0) };
		snd.("/ms/scene/" ++ id ++ "/cursor", "show", cursorOn.if({ 1 }, { 0 }));
		snd.("/ms/scene/" ++ id, "paginate", paginate.if({ 1 }, { 0 }), pageHeight);
		snd.("/ms/scene/" ++ id, "addressable", 1);
		snd.("/ms/scene/" ++ id, "notationData", "mei", m);
	}

	/*
	[method.show]
	description = "display the notation in MusicScene, made addressable so note positions are known for the follow cursor. Non-blocking (sends the OSC setup from a Routine)."
	*/
	show {
		Routine({ this.pr_emitSetup(showCursor); }).play;
	}

	/*
	[method.showPage]
	description = "display the notation and show a given page, with NO cursor and NO playback (display only). Non-blocking. Distinct pages need a paginated score (the default). See link::Classes/MSScore#-page::, link::Classes/MSScore#-nextPage::, link::Classes/MSScore#-prevPage::."
	[method.showPage.args]
	pageNumber = "the 1-based page to show (default 1)"
	*/
	showPage { | pageNumber = 1 |
		Routine({ this.pr_emitSetup(false); showDelay.wait; this.page(pageNumber); }).play;
	}
```

(The `cursor show` value now comes from `cursorOn`; `show` passes `showCursor`, so its emitted messages are byte-identical to before.)

- [ ] **Step 4: Run to verify it passes**

Run: `py -m pytest tools/msscore/test_show_page.py::test_show_page_display_only -q`
Expected: PASS (`PAGE:2`, `CURSOR:0`, `PLAYER_NIL:true`, `CLOCK_NIL:true`).

- [ ] **Step 5: Prove the `show` refactor is byte-identical**

Run: `py -m pytest tools/msscore/test_midi_routing.py::test_show_cursor_hidden tools/msscore/test_midi_routing.py::test_show_cursor_default -q`
Expected: both PASS — `show` still emits `cursor show 0` (when `showCursor:false`) and `cursor show 1` (default), confirming the extraction changed nothing observable.

- [ ] **Step 6: Full suite**

Run: `py -m pytest tools/msscore/ tools/panola_mei/ -q`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "$(cat <<'EOF'
feat(msscore): showPage(n) — display a page, no cursor, no playback

Extract show's OSC setup into pr_emitSetup(cursorOn) (show stays byte-
identical); showPage emits it with the cursor off, then a deferred page n.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/msscore/test_show_page.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(msscore): showPage(2) shows the page, cursor off, no playback

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Docs — whelk + schelp regen

**Files:**
- Modify: `Classes\MSScore.sc` (the `[general]` doc-comment — mention display-only)
- Regenerate: `HelpSource\Classes\MSScore.schelp`

- [ ] **Step 1: Add a line to the `[general]` description**

In the `[general]` `description` block (top of `MSScore.sc`), after the `code::` usage example that ends with `~score.stop;` and `::` (~line 30), add a short paragraph:

```
strong::Display only:: — to show the notation without playing it or drawing a cursor, use
teletype::showPage(n):: (page teletype::n::, 1-based; default 1). Once shown, teletype::page(n)::,
teletype::nextPage:: and teletype::prevPage:: flip between pages. Distinct pages need a paginated
score (the default).
```

- [ ] **Step 2: Regenerate schelp**

Run `gendoc.bat` from the msscore quark root (via PowerShell if Git Bash `cd` fails: `Set-Location "C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore"; .\gendoc.bat`).
Expected: ends with `Done.`, no `ERROR`.

- [ ] **Step 3: Verify schelp got the methods**

Run: `grep -nE "showPage|nextPage|prevPage" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore/HelpSource/Classes/MSScore.schelp"`
Expected: matches for each (METHOD:: entries + the general paragraph).

- [ ] **Step 4: Confirm the class still compiles**

Run: `py -m pytest tools/msscore/test_show_page.py -q`
Expected: PASS (a fresh sclang compile of the edited `MSScore.sc` succeeds).

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc HelpSource/Classes/MSScore.schelp
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "$(cat <<'EOF'
docs(msscore): document showPage/page/nextPage/prevPage; regenerate schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: SuperCollider example

**Files:**
- Create: `D:\Projects\MusicScene\examples\supercollider\example_show_page.scd`

- [ ] **Step 1: Write the example**

Create `examples/supercollider/example_show_page.scd` — a multi-page score shown at a chosen page, display-only. Use a long single voice + small `pageHeight` so it paginates, and `showPage(2)`:

```supercollider
// =============================================================================
// MSScore display-only: show a GIVEN page of the notation — no cursor, no playback.
//
// `showPage(n)` engraves the score and shows page n (1-based) with the cursor line OFF and no
// audio. Once shown, `page(n)`, `nextPage` and `prevPage` flip between the pre-rendered pages.
// Contrast with `play` (which shows, plays, and follows with a cursor).
//
// REQUIRES: the MSScore quark (Quarks.install), MusicScene running with Verovio.
// USAGE: run the Godot project (one instance), set ~space to match musicscene/space, then put the
//        cursor in the ( ... ) block and press Ctrl+Enter.
// =============================================================================

(
// A long melody so the score spans several pages (small pageHeight => more pages).
~long = (1..48).collect({ |i| ["c5", "e5", "g5", "a5", "f5", "d5"].wrapAt(i) ++ "_8" }).join(" ");

~score = MSScore(
	voices:  [~long],
	clefs:   [\treble],
	meter:   "4/4", key: \Cmajor, tempo: 96,
	scale:   1.0,
	paginate: true, pageHeight: 700,   // small page => several pages
	space:   "3d"                      // match your project's musicscene/space
);

~score.showPage(2);   // DISPLAY page 2 only — no cursor, no sound
"Showing page 2 (display only). Evaluate ~score.nextPage / ~score.prevPage / ~score.page(1) to flip.".postln;
)


// Flip pages (evaluate a line at a time):
// ~score.nextPage;
// ~score.prevPage;
// ~score.page(1);

// Clear the scene when done:
// ~score.stop;
```

- [ ] **Step 2: Verify the example parses in sclang**

Run (Git Bash), a parse-only check that the class calls resolve (no server/Godot needed — build the MEI and confirm it paginates conceptually by checking the voice builds):
```
"C:/Program Files/SuperCollider-3.14.1/sclang.exe" -D examples/supercollider/example_show_page.scd
```
is not suitable (it would try to talk OSC). Instead, verify the Panola voice + MSScore construct without error by running a scratch script that builds `~score.mei` and asserts it is a non-empty MEI string:
```
(
var long = (1..48).collect({ |i| ["c5","e5","g5","a5","f5","d5"].wrapAt(i) ++ "_8" }).join(" ");
var s = MSScore(voices: [long], clefs: [\treble], meter: "4/4", key: \Cmajor, paginate: true, pageHeight: 700);
var m = s.mei;
((m.size > 100) and: { m.contains("<measure ") }).if({ "EXAMPLE-OK".postln }, { "EXAMPLE-BAD".postln });
0.exit;
)
```
Run it with sclang. Expected: `EXAMPLE-OK` and no `ERROR`.

- [ ] **Step 3: Commit**

```bash
git -C "D:/Projects/MusicScene" add examples/supercollider/example_show_page.scd
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs(examples): example_show_page.scd — display a given page (no cursor/playback)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: CHANGELOG + finish

- [ ] **Step 1: CHANGELOG entry**

In `D:\Projects\MusicScene\CHANGELOG.md`, add an `### Added` bullet under the current top version entry `## [0.17.0] — 2026-07-08` (this ships alongside the hairpins release), OR a new heading if the user has already cut 0.17.0 — check the top of the file and place it under the unreleased/top entry:

```
- **MSScore display-only page view.** `MSScore.showPage(n)` engraves the score and shows page `n`
  (1-based) with no cursor and no playback; `page(n)` / `nextPage` / `prevPage` flip between pages.
  Uses the existing MusicScene page verbs (no Godot change). Example:
  `examples/supercollider/example_show_page.scd`. (MSScore quark.)
```

- [ ] **Step 2: Full suite green**

Run: `py -m pytest tools/msscore/ tools/panola_mei/ -q`
Expected: all pass.

- [ ] **Step 3: Commit docs (incl. spec + plan)**

```bash
git -C "D:/Projects/MusicScene" add CHANGELOG.md docs/superpowers/specs/2026-07-08-msscore-show-page-design.md docs/superpowers/plans/2026-07-08-msscore-show-page.md
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs: CHANGELOG + spec + plan for MSScore showPage / page navigation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Finish the branch**

Use **superpowers:finishing-a-development-branch** for MusicScene `feature/msscore-show-page`. The MSScore quark commits are on its own `main`. A release (MSScore version bump + tag; MusicScene `plugin.cfg`/`MS_VERSION` + tag) is a separate step per [[release-doc-version-consistency]], only if the user asks.

---

## Self-review

**Spec coverage:**
- `showPage(n)` display-only, cursor off, no playback → Task 2 (impl + test asserts PAGE/CURSOR:0/PLAYER_NIL/CLOCK_NIL). ✓
- `page`/`nextPage`/`prevPage` nav → Task 1. ✓
- Byte-safe `show` refactor via `pr_emitSetup` → Task 2 Step 3 + Step 5 guard (existing cursor tests). ✓
- 1-based, clamped, no Godot change → uses existing verbs; noted, not re-implemented. ✓
- Docs + schelp → Task 3. Example → Task 4. CHANGELOG → Task 5. ✓
- Test seam (OSCdef capture, NetAddr.langPort) → Task 1/2 tests. ✓

**Placeholder scan:** No TBD/TODO/"similar to". All code shown; commands concrete with expected output.

**Type/name consistency:** `pr_emitSetup(cursorOn)`, `showPage(pageNumber=1)`, `page(pageNumber=1)`, `nextPage`, `prevPage` used consistently across tasks; OSC verbs (`page`/`nextpage`/`prevpage`) match the Godot `MSNotationObject` handler labels; test symbols (`\page`, `\show`, `PAGE:`/`CURSOR:`/`PLAYER_NIL:`/`CLOCK_NIL:`) match between the SC scripts and the Python asserts.

---

## NOTE — separate follow-up feature (not in this plan)

The user also asked for **a way to force a new page mid-score** (a manual page break). That is a
distinct *notation-authoring* feature (not display navigation): it means emitting a forced break
in the MEI (`<pb/>`/`<sb/>`) at a chosen point AND rendering with a Verovio break mode that honors
encoded breaks (the current `verovio_render.py` uses `breaks:auto`, which ignores them). It needs
its own brainstorm → spec → plan. Do **not** fold it into this plan.
