# Multiple Articulations Per Note — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one Panola note/chord carry several articulations at once via `@art^staccato+accent^`, rendering to MEI `artic="acc stacc"`.

**Architecture:** Two surgical changes in the Panola quark. (1) The property-value grammar in `PanolaParser.sc` gains `+` as a legal value character, so `staccato+accent` parses as one `@art` value (flowing untouched through the existing property→pattern layer — no last-wins collapse). (2) `annotateExpression` in `PanolaMEI.sc` splits `ev[\art]` on `+` and routes each part through the *existing* accumulate-into-a-`Set` logic (a `:`-part is a sticky `:on`/`:off` toggle; a bare part adds to this note only), then sorts and space-joins as it already does. Playback and MSScore are untouched.

**Tech Stack:** SuperCollider (`.sc` quark classes), Python + pytest + sclang + Verovio for the tests (`tools/panola_mei/`), whelk/`gendoc.bat` for schelp docs.

---

## Repos, branches & conventions

Two git repos are involved:

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch `master`). Holds the `.sc` classes and `HelpSource` schelp. Prior work commits the quark directly on `master`.
- **MusicScene** — `D:\Projects\MusicScene` (branch `main`). Holds the Python tests and the spec/plan docs. Create a feature branch `feature/panola-multiple-articulations` here before editing (never implement on `main`); finish with the finishing-a-development-branch skill.

Conventions to honor:
- **`.sc` files are TAB-indented.** Every code block below that edits a `.sc` file must be pasted with real tabs, matching the surrounding lines. An `Edit` `old_string` must match the file's tabs exactly.
- **Commit only when the user asks.** The Step "Commit" actions below are written out, but only run them once the user confirms (executing this plan is such a confirmation; if in doubt, ask). End every commit message with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- The Python tests spawn a fresh `sclang` per run, which recompiles the class library, so **no manual IDE recompile is needed** for the tests to see `.sc` edits.
- Run the suite one sclang at a time (the tests already serialize; do not parallelize `-n`).

---

## Task 1: Parser — allow `+` inside a property value

Makes `@art^staccato+accent^` parse as a single value. Verified in isolation via `asPbind` (the combined string must reach `ev[\art]` as the symbol `'staccato+accent'`), independent of the MEI change in Task 2.

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaParser.sc` (three identical value-regex occurrences at lines 263, 269, 275)
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_expression.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/panola_mei/test_expression.py`:

```python
# A '+'-combined @art value must PARSE as one property value and reach the Pbind intact
# (ev[\art] == 'staccato+accent'). This exercises the PanolaParser value-regex change alone;
# the MEI split-on-'+' is Task 2.
PLUS_PARSE_SCRIPT = r'''(
var st, e0;
st = Panola("c5_4@art^staccato+accent^ d5").asPbind(\default, include_tempo:false).asStream;
e0 = st.next(());
(e0[\art] == 'staccato+accent').if(
    { "PLUS-OK".postln },
    { ("PLUS-BAD e0=" ++ e0[\art].asString).postln });
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_plus_value_parses():
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(PLUS_PARSE_SCRIPT)
        path = f.name
    try:
        r = subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    assert "PLUS-OK" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `py -m pytest tools/panola_mei/test_expression.py::test_plus_value_parses -q`
Expected: FAIL — before the regex change, `staccato+accent` stops the value parser at `+`, the note fails to parse, and `PLUS-OK` never prints (stdout shows a parse error, not `PLUS-OK`).

- [ ] **Step 3: Make the change (three occurrences)**

In `PanolaParser.sc`, each of the three property forms (animated `{}`, static `[]`, one-shot `^^`) parses its value with the same regex. Change the character class from `[a-zA-Z][a-zA-Z0-9:]*` to `[a-zA-Z][a-zA-Z0-9:+]*` in all three. The three current lines (263, 269, 275) are byte-identical:

```
					ScpChoice([ScpParserFactory.makeFloatParser, ScpRegexParser("[a-zA-Z][a-zA-Z0-9:]*")]),
```

become:

```
					ScpChoice([ScpParserFactory.makeFloatParser, ScpRegexParser("[a-zA-Z][a-zA-Z0-9:+]*")]),
```

Use `Edit` with `replace_all: true` on the exact string `ScpRegexParser("[a-zA-Z][a-zA-Z0-9:]*")` → `ScpRegexParser("[a-zA-Z][a-zA-Z0-9:+]*")` (it appears exactly three times, all the value regex). The value parser tries `makeFloatParser` first, so numeric values like `@amp{0.5}` are unaffected — `+` only ever matches inside a letter-initial value.

- [ ] **Step 4: Run the test to verify it passes**

Run: `py -m pytest tools/panola_mei/test_expression.py::test_plus_value_parses -q`
Expected: PASS (`PLUS-OK` printed).

- [ ] **Step 5: Guard against regressions in the rest of the expression suite**

Run: `py -m pytest tools/panola_mei/test_expression.py -q`
Expected: all tests pass (existing `test_articulation`, `test_dynamics`, `test_aspbind_materializes_with_expression`, `test_oneshot_property_readable`, plus the new one).

- [ ] **Step 6: Commit (panola repo — only when the user has confirmed committing)**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaParser.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
feat(parser): allow '+' in @-property values (enables combined @art)

Extend the property-value regex so a value like "staccato+accent" parses
as one token. Flows through customPropertyPattern untouched to ev[\art].

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

Also commit the new test in the MusicScene repo (feature branch):

```bash
git -C "D:/Projects/MusicScene" add tools/panola_mei/test_expression.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): '+'-combined @art value parses to ev[\art]

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: MEI — combine articulations on one note by splitting on `+`

With Task 1 in place, `@art^staccato+accent^` reaches `annotateExpression` as `ev[\art] = "staccato+accent"`, but the current code hands the whole string to `artCode` (which returns `nil` → an "unknown articulation" warning and no `artic`). This task splits on `+` and routes each part through the existing accumulate logic.

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaMEI.sc:141-162` (the `annotateExpression` closure)
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_expression.py`

- [ ] **Step 1: Write the failing tests**

Append to `tools/panola_mei/test_expression.py`:

```python
COMBINED = {
  # one-shot combo: both codes on the first note only
  "combo":       r'Panola.scoreAsMEI([Panola("c5_4@art^staccato+accent^ d5 e5 f5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  # combo where one part is a sticky :on -> staccato passage, accent this-note-only
  "combosticky": r'Panola.scoreAsMEI([Panola("c5_4@art^staccato:on+accent^ d5 e5 f5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  # order independence: output is sorted regardless of input order
  "order":       r'Panola.scoreAsMEI([Panola("c5_4@art^accent+staccato^ d5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_combined_articulation():
    outdir = tempfile.mkdtemp(prefix="panola_expr_")
    try:
        _dump(outdir, COMBINED)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in COMBINED}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    # one-shot combo: exactly one note carries both codes; the other three carry no artic
    assert meis["combo"].count('artic="acc stacc"') == 1
    assert meis["combo"].count(' artic="') == 1
    # combo + sticky: first note has both; the staccato passage persists on notes 2-4 (accent does not)
    assert meis["combosticky"].count('artic="acc stacc"') == 1
    assert meis["combosticky"].count(' artic="stacc"') == 3
    # order independence: sorted output ("acc stacc") regardless of "accent+staccato" input
    assert 'artic="acc stacc"' in meis["order"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `py -m pytest tools/panola_mei/test_expression.py::test_combined_articulation -q`
Expected: FAIL — the combined string is treated as one unknown articulation, so no `artic="acc stacc"` is emitted (assertions on the counts fail). sclang stderr/stdout also shows a `PanolaMEI: unknown articulation 'staccato+accent'` warning.

- [ ] **Step 3: Replace the `annotateExpression` closure**

In `PanolaMEI.sc`, the current block (lines 141-162) is:

```
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

Replace it with (note: **real tabs**, matching the file's indentation — the closure body is indented with 3 tabs, its inner lines with 4/5 tabs):

```
			var annotateExpression = { |events|
				var artSet = Set[], prevArt = "", prevDyn = "";
				events.do({ |ev|
					var art = ev[\art] ? "", dyn = ev[\dyn] ? "", noteSet, parts;
					// one @art value may combine several articulations with '+' (e.g. "staccato+accent");
					// each part is either a sticky "name:on"/"name:off" toggle or a bare per-note name.
					parts = (art == "").if({ [] }, { art.split($+) });
					// sticky toggles change the carried-forward set; apply only when the whole art value
					// CHANGES (a static [] value carries forward, so re-applying every note would be
					// redundant, and re-applying ":off" would be wrong).
					if (art != prevArt) {
						parts.do({ |p|
							if (p.includes($:)) {
								var seg = p.split($:), code = artCode.(seg[0]);
								if (code.notNil) {
									(seg[1] == "on").if({ artSet = artSet.add(code) }, { artSet.remove(code) });
								} { ("PanolaMEI: unknown articulation '" ++ seg[0] ++ "'").warn };
							};
						});
					};
					prevArt = art;
					noteSet = artSet.copy;
					// bare names (no :on/:off) add to THIS note only
					parts.do({ |p|
						if ((p != "") and: { p.includes($:).not }) {
							var code = artCode.(p);
							if (code.notNil) { noteSet = noteSet.add(code) } { ("PanolaMEI: unknown articulation '" ++ p ++ "'").warn };
						};
					});
					ev[\articStr] = noteSet.asArray.sort.join(" ");
					ev[\dynMark] = ((dyn != prevDyn) and: { dyn != "" }).if({ dyn }, { nil });
					prevDyn = dyn;
				});
				events;
			};
```

Behavior preserved for the single-articulation cases: an empty `art` yields `parts=[]` (nothing added); a pure sticky `stacc:on` (one part, has `:`) toggles `artSet` only on change; a pure bare `staccato` (one part, no `:`) adds to the note's set only. New behavior: multiple `+`-separated parts each route the same way.

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `py -m pytest tools/panola_mei/test_expression.py::test_combined_articulation -q`
Expected: PASS.

- [ ] **Step 5: Run the whole expression suite (regression guard)**

Run: `py -m pytest tools/panola_mei/test_expression.py -q`
Expected: all pass — especially `test_articulation` (the `oneshot` / `passage` / `layered` assertions), confirming the refactor kept single-articulation and sticky-range behavior identical.

- [ ] **Step 6: Run the full Panola/MSScore suites**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass (no collection of the argv-reading `tools/osc_test.py`; run only these two packages).

- [ ] **Step 7: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
feat(panola_mei): combine multiple articulations on one note via '+'

annotateExpression splits @art on '+' and routes each part through the
existing set-accumulation: a ':'-part is a sticky on/off toggle, a bare
part adds to this note only. Emits sorted space-separated artic="acc stacc".

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/panola_mei/test_expression.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): combined @art^a+b^ renders artic="acc stacc" (one-shot, sticky, sorted)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Docs — document the `+` combine syntax and regenerate schelp

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaMEI.sc` (the `[general]` doc-comment block, around line 30)
- Regenerate: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\HelpSource\Classes\PanolaMEI.schelp` (via `gendoc.bat`)

- [ ] **Step 1: Add the `+` articulation prose to the `[general]` block**

The current lines 28-30 of `PanolaMEI.sc` read:

```
are auto-beamed per beat, same-ratio runs become teletype::<tuplet>:: groups, and per-note
teletype::@dyn:: / teletype::@art:: properties become dynamics and articulation, while
teletype::@slur^start^:: ... teletype::@slur^end^:: spans become slurs.
```

Immediately after the `...spans become slurs.` line (line 30), insert this new paragraph (blank line before it, real content — whelk-safe prose using only `teletype::`/`strong::`):

```

A single teletype::@art:: may strong::combine several articulations:: with teletype::+::, e.g.
teletype::@art^staccato+accent^::, rendering them together as one space-separated teletype::artic::
list (teletype::artic="acc stacc"::). Each teletype::+:: part may itself be a strong::sticky::
toggle: teletype::@art^staccato:on+accent^:: begins a staccato passage strong::and:: accents just
that note. The list is order-independent and de-duplicated.
```

- [ ] **Step 2: Regenerate the schelp**

Run `gendoc.bat` from the panola quark root:

Run: `cmd //c "cd /d C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola && gendoc.bat"`
Expected: output ends with `Done.` and contains no `ERROR`. (If it reports an error, the doc-comment prose introduced a schelp-illegal token — fix the prose and rerun.)

- [ ] **Step 3: Verify the regenerated schelp mentions the new syntax**

Run: `grep -n "staccato+accent\|combine several articulations" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMEI.schelp"`
Expected: at least one match (the paragraph rendered into the `.schelp`).

- [ ] **Step 4: Sanity-check the doc-carrying class still compiles**

Run: `py -m pytest tools/panola_mei/test_expression.py::test_combined_articulation -q`
Expected: PASS (a fresh sclang compile of the edited `PanolaMEI.sc` succeeds — a broken doc comment would surface as a class-library compile error here).

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc HelpSource/Classes/PanolaMEI.schelp
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
docs(panola_mei): document '+'-combined articulations; regenerate schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Finish the branch

- [ ] **Step 1: Full suite green**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass.

- [ ] **Step 2: Commit the spec + plan docs (MusicScene repo)**

```bash
git -C "D:/Projects/MusicScene" add docs/superpowers/specs/2026-07-08-panola-multiple-articulations-design.md docs/superpowers/plans/2026-07-08-panola-multiple-articulations.md
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs(superpowers): spec + plan for multiple articulations per note

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Complete the development branch**

Use the **superpowers:finishing-a-development-branch** skill for the MusicScene `feature/panola-multiple-articulations` branch (verify tests → present merge/PR/keep/discard options → execute the user's choice). The panola quark commits live on its own `master`; note that pushing the quark repo remains the user's responsibility, and a version bump/tag of the panola quark (if the user wants a release) is a separate follow-up, not part of this plan.

---

## Self-review

**Spec coverage:**
- Parser `+` in value (3 regex sites) → Task 1. ✓
- MEI `annotateExpression` split-on-`+` with sticky/bare routing → Task 2. ✓
- Semantics table (one-shot combo, combo+sticky, order-independence, dedup) → Task 2 tests (`combo`, `combosticky`, `order`; dedup is inherent to the `Set` and covered by `order`'s sorted single-pair output). ✓
- Existing single-articulation behavior preserved → Task 2 Step 5 (regression on `test_articulation`). ✓
- Playback unchanged / MSScore unchanged → no code touches those paths; Task 2 Step 6 runs `tools/msscore/` as a guard. ✓
- Docs + schelp regen → Task 3. ✓

**Placeholder scan:** No TBD/TODO/"similar to"/"handle edge cases". All code shown in full; all commands concrete with expected output.

**Type/name consistency:** `ev[\art]`, `ev[\articStr]`, `artSet`, `artCode`, `noteSet`, `parts`, `seg` used consistently across Task 2. Test symbols (`'staccato+accent'`), MEI substrings (`artic="acc stacc"`, ` artic="stacc"`), and dict keys (`combo`/`combosticky`/`order`) match between the test code and the assertions. The regex string `ScpRegexParser("[a-zA-Z][a-zA-Z0-9:]*")` in Task 1 matches the three real occurrences verified in the source.
