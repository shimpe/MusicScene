# Panola / MSScore Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author sung lyrics as a **separate line per staff** (`lyrics:`), aligned syllable-by-syllable to non-rest notes, and engrave them as MEI `<verse>/<syl>` — notation only, never touching sound.

**Architecture:** All lyrics semantics live in **PanolaMEI**: a pure tokenizer classmethod (`*pr_parseLyricLine`) turns a verse string into syllable/melisma *slots* (whitespace = word, `-` = syllable + hyphen, `_` = melisma, `\` escapes); an attach step binds slots to non-rest events; `meiElement` emits `<verse>` on the first tied fragment only, XML-escaping the text. `Panola.asMEI`/`*scoreAsMEI` and `MSScore` gain a trailing `lyrics` arg that passes straight through. `lyrics: nil` everywhere ⇒ byte-identical output.

**Tech Stack:** SuperCollider (`.sc`), Python + pytest driving `sclang` + Verovio (`tools/panola_mei/`, `tools/msscore/`), whelk/`gendoc.bat`, a `.scd` example.

**Spec:** `docs/superpowers/specs/2026-07-10-panola-lyrics-design.md`

---

## Repos, branches & conventions

- **Panola quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (branch `master`). `.sc` classes are **CRLF, TAB-indented** — read each anchor and match exactly; if an `Edit` literal won't match, use a byte-anchored replacement and verify tabs/CRLF with `cat -A`.
- **MSScore quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore` (branch `main`). `.sc` is **LF, TAB-indented**.
- **MusicScene** — `D:\Projects\MusicScene` (create branch `feature/panola-lyrics`; never work on `main`). Python tests, the example, CHANGELOG, README/TUTORIAL.
- Python tests spawn a fresh `sclang` per run (auto-picks-up `.sc` edits). Use `py` (not `python`). Bash = Git Bash. Run only `tools/panola_mei/ tools/msscore/`.
- **Escape-corruption trap:** never build SC source by interpolating strings that contain `\`-sequences through a shell/Python that re-interprets them (a past bug turned `\amp` into a BEL byte). Edit `.sc` with the `Edit` tool using literal anchors; keep a backup of any file you touch via a script.
- **Commit only after the user confirms** (executing this plan is such confirmation). End commit messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File structure

| File | Responsibility |
| --- | --- |
| `panola/Classes/PanolaMEI.sc` | tokenizer `*pr_parseLyricLine`, XML-escape `*pr_xmlEscape`, `verseXml`/`attachLyrics` helpers, `meiElement` verse emission, `lyrics` arg on `*scoreAsMEI` |
| `panola/Classes/Panola.sc` | pass `lyrics` through `asMEI` and `*scoreAsMEI` |
| `msscore/Classes/MSScore.sc` | `lyrics` instVar + `*new`/`init` arg + forward in `mei` |
| `MusicScene/tools/panola_mei/test_lyrics.py` | tokenizer + full-render tests |
| `MusicScene/tools/msscore/test_lyrics.py` | MSScore pass-through test |
| `MusicScene/examples/supercollider/example_lyrics.scd` | runnable example |

---

## Task 1: `*pr_parseLyricLine` tokenizer (pure classmethod)

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaMEI.sc` (add two classmethods after `*scoreAsMEI`, before the class's closing `}` at ~line 711)
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_lyrics.py` (create)

- [ ] **Step 1: Write the failing tokenizer test**

Create `tools/panola_mei/test_lyrics.py`:

```python
"""Lyrics tests for Panola.scoreAsMEI (PanolaMEI): the pure tokenizer *pr_parseLyricLine
and full MEI <verse>/<syl> emission. Run:
  py -m pytest tools/panola_mei/test_lyrics.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.test_expression import _dump, SCLANG
from tools.panola_mei.render_check import render_props


def _tok(sc_literal):
    """Run PanolaMEI.pr_parseLyricLine(<sc_literal>) and return the canonical token string.
    Each slot renders as  syl|wordpos|con  (- for a nil wordpos/con), a melisma as  _ ."""
    script = (
        "(\n"
        "~fmt = { |line| PanolaMEI.pr_parseLyricLine(line).collect({ |s|\n"
        '  (s[\\melisma] == true).if({ "_" }, { s[\\syl] ++ "|" ++ (s[\\wordpos] ? "-") ++ "|" ++ (s[\\con] ? "-") }) }).join(" ") };\n'
        '("TOK:" ++ ~fmt.(' + sc_literal + ')).postln; 0.exit;\n'
        ")\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script); path = f.name
    try:
        r = subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    line = [l for l in r.stdout.splitlines() if l.startswith("TOK:")]
    assert line, r.stdout[-1500:]
    return line[0][4:]


# each case: (SuperCollider string LITERAL, expected canonical token string)
TOK_CASES = {
    "hyphen":   (r'"Twin-kle twin-kle lit-tle star,"',
                 "Twin|i|d kle|t|- twin|i|d kle|t|- lit|i|d tle|t|- star,|-|-"),
    "melisma":  (r'"joy _ _ to the world"',
                 "joy|-|- _ _ to|-|- the|-|- world|-|-"),
    "three":    (r'"al-le-lu-ia"', "al|i|d le|m|d lu|m|d ia|t|-"),
    "escspace": (r'"two\\ words done"', "two words|-|- done|-|-"),
    "escunder": (r'"held\\_note"', "held_note|-|-"),
    "apos":     (r'"don\'t sayin\'"', "don't|-|- sayin'|-|-"),
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
@pytest.mark.parametrize("key", list(TOK_CASES))
def test_tokenizer(key):
    sc_literal, expected = TOK_CASES[key]
    assert _tok(sc_literal) == expected
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/panola_mei/test_lyrics.py -k test_tokenizer -q`
Expected: FAIL — `PanolaMEI` has no `pr_parseLyricLine` (sclang prints a `doesNotUnderstand`/`ERROR`). If SKIPPED (sclang absent), STOP and report BLOCKED.

- [ ] **Step 3: Add the tokenizer + XML-escape classmethods**

In `PanolaMEI.sc`, the class body ends:

```
			^("<?xml version=\"1.0\" encoding=\"UTF-8\"?>..." ...);
	}
}
```

Immediately BEFORE the final `}` that closes `PanolaMEI` (the last line of the file), and AFTER the closing `}` of `*scoreAsMEI`, add these two classmethods (real TABs, CRLF — match the file). Note the whelk doc comment blocks:

```
	/*
	[classmethod.pr_parseLyricLine]
	description = "(private) tokenize one lyrics verse line into an Array of slots. Whitespace separates words, teletype::-:: separates syllables within a word (a hyphen is drawn), a whole-token teletype::_:: is a melisma (the next note holds the previous syllable), and teletype::\\:: escapes the next character literally (teletype::\\ :: = a space inside a syllable, teletype::\\-::/teletype::\\_:: = a literal hyphen/underscore, teletype::\\\":: = a quote). A multi-syllable word gets wordpos i/m/t and con=d on all but its last syllable so the renderer draws the connecting hyphens."
	[classmethod.pr_parseLyricLine.args]
	line = "one verse line (a String)"
	[classmethod.pr_parseLyricLine.returns]
	what = "an Array of Events: ( syl: String, wordpos: \"i\"|\"m\"|\"t\"|nil, con: \"d\"|nil ) for a syllable, or ( melisma: true ) for a held note"
	*/
	*pr_parseLyricLine {
		| line |
		var slots = [], word = [], esc = false, flushWord;
		flushWord = {
			if (word.size > 0) {
				if ((word.size == 1) and: { word[0] == \us }) {
					slots = slots.add(( melisma: true ));
				} {
					var syls = [[]];
					word.do({ |t|
						if (t == \hy) { syls = syls.add([]) } {
							syls[syls.size-1] = syls[syls.size-1].add((t == \us).if({ $_ }, { t[1] }));
						};
					});
					syls = syls.collect({ |cs| String.newFrom(cs) });
					syls.do({ |s, idx|
						var wp = nil, con = nil;
						if (syls.size > 1) {
							wp = (idx == 0).if({ "i" }, { (idx == (syls.size-1)).if({ "t" }, { "m" }) });
							con = (idx < (syls.size-1)).if({ "d" }, { nil });
						};
						slots = slots.add(( syl: s, wordpos: wp, con: con ));
					});
				};
				word = [];
			};
		};
		line.do({ |ch|
			if (esc) { word = word.add([\ch, ch]); esc = false; } {
				case
				{ ch == $\\ } { esc = true }
				{ (ch == $ ) or: { ch == $\t } } { flushWord.value }
				{ ch == $- } { word = word.add(\hy) }
				{ ch == $_ } { word = word.add(\us) }
				{ true } { word = word.add([\ch, ch]) };
			};
		});
		if (esc) { word = word.add([\ch, $\\]) };
		flushWord.value;
		^slots;
	}

	/*
	[classmethod.pr_xmlEscape]
	description = "(private) escape the XML text-content metacharacters & < > in a String, so free-form lyric text is safe inside <syl>."
	[classmethod.pr_xmlEscape.args]
	s = "a String"
	[classmethod.pr_xmlEscape.returns]
	what = "the String with & < > replaced by &amp; &lt; &gt;"
	*/
	*pr_xmlEscape {
		| s |
		^s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
	}
```

- [ ] **Step 4: Run to verify the tokenizer tests pass**

Run: `py -m pytest tools/panola_mei/test_lyrics.py -k test_tokenizer -q`
Expected: PASS (all 6 parametrized cases).

- [ ] **Step 5: Confirm the class still compiles (no other test regressed)**

Run: `py -m pytest tools/panola_mei/ -q`
Expected: all pass (the two new classmethods are additive; nothing else changed).

- [ ] **Step 6: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
feat(panola_mei): pr_parseLyricLine tokenizer + pr_xmlEscape

Pure classmethods: tokenize a lyrics verse (whitespace=word, -=syllable+hyphen,
_=melisma, \ escapes) into slots, and XML-escape free-form syllable text.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/panola_mei/test_lyrics.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): pr_parseLyricLine tokenizer cases (hyphen/melisma/escape)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `scoreAsMEI` emits `<verse>/<syl>` from a `lyrics` arg

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\PanolaMEI.sc` (`*scoreAsMEI`)
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_lyrics.py`

- [ ] **Step 1: Write the failing render tests**

Append to `tools/panola_mei/test_lyrics.py`:

```python
# --- full-render lyrics via PanolaMEI.scoreAsMEI ------------------------------------------------
# 5 quarter-ish notes so "Twin-kle twin-kle star" (5 syllables) fills them; g5_2 is a half note.
V = r'Panola("c5_4 d5 e5 f5 g5_2")'
CHG = r'[( measure: 1, meter: "4/4", key: \Cmajor )]'

CASES = {
  # one verse, hyphens -> wordpos + con; last word single-syllable
  "basic":   r'PanolaMEI.scoreAsMEI([%s], %s, [\treble], nil, nil, nil, [[ "Twin-kle twin-kle star" ]])' % (V, CHG),
  # a rest is skipped (no syllable under it): "a b" aligns to the two notes, not the rest
  "rest":    r'PanolaMEI.scoreAsMEI([Panola("c5_4 r d5_4")], %s, [\treble], nil, nil, nil, [[ "a b" ]])' % CHG,
  # melisma: "joy" then two held notes -> only ONE <verse>, on note 1
  "melisma": r'PanolaMEI.scoreAsMEI([Panola("c5_4 d5 e5 f5")], %s, [\treble], nil, nil, nil, [[ "joy _ _ end" ]])' % CHG,
  # two verses -> two <verse> per sung note, n="1" and n="2"
  "verses":  r'PanolaMEI.scoreAsMEI([%s], %s, [\treble], nil, nil, nil, [[ "one two three four five", "un deux trois qua-tre" ]])' % (V, CHG),
  # a note tied across a barline: syllable on the FIRST fragment only. c5 lasts 6 quarters (> one 4/4 bar)
  "tied":    r'PanolaMEI.scoreAsMEI([Panola("c5_1.. d5_2")], %s, [\treble], nil, nil, nil, [[ "held done" ]])' % CHG,
  # XML-escape + literal quote via backslash: syllable  "Oh,"  contains quotes and needs no & but proves escaping path
  "escape":  r'PanolaMEI.scoreAsMEI([Panola("c5_4 d5")], %s, [\treble], nil, nil, nil, [[ "R\\&B \\\"Oh,\\\"" ]])' % CHG,
  # byte-identity control: same voice, NO lyrics
  "nolyr":   r'PanolaMEI.scoreAsMEI([%s], %s, [\treble], nil, nil, nil, nil)' % (V, CHG),
  "nolyr2":  r'PanolaMEI.scoreAsMEI([%s], %s, [\treble])' % (V, CHG),
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_render():
    outdir = tempfile.mkdtemp(prefix="panola_lyr_")
    try:
        _dump(outdir, CASES)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in CASES}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)

    # every lyric MEI must still render in Verovio
    for k in ("basic", "rest", "melisma", "verses", "tied", "escape"):
        assert render_props(meis[k])["ok"], k

    b = meis["basic"]
    assert b.count("<syl") == 5
    assert '<syl wordpos="i" con="d">Twin</syl>' in b
    assert '<syl wordpos="t">kle</syl>' in b
    assert '<syl>star</syl>' in b            # single-syllable word: no wordpos/con

    assert meis["rest"].count("<syl") == 2   # the rest consumed no syllable
    assert '<rest' in meis["rest"] and 'rest><syl' not in meis["rest"].replace(" ", "")

    assert meis["melisma"].count("<verse") == 2   # note 1 "joy" + note 4 "end"; notes 2-3 held
    assert '<syl>joy</syl>' in meis["melisma"]

    assert '<verse n="1">' in meis["verses"] and '<verse n="2">' in meis["verses"]
    assert meis["verses"].count('<verse n="2">') == 5

    assert meis["tied"].count("<syl>held</syl>") == 1   # first fragment only, not on the tied continuation

    assert '<syl>R&amp;B</syl>' in meis["escape"]        # & escaped
    assert '<syl>"Oh,"</syl>' in meis["escape"]          # backslash-escaped quotes are literal

    # byte-identity: lyrics nil renders exactly like the positional-default form
    assert meis["nolyr"] == meis["nolyr2"]
    assert "<verse" not in meis["nolyr"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/panola_mei/test_lyrics.py -k test_lyrics_render -q`
Expected: FAIL — `scoreAsMEI` ignores the 7th arg (SC keyword-arg warning) and emits no `<verse>`.

- [ ] **Step 3: Add the `lyrics` arg to the `scoreAsMEI` signature**

In `PanolaMEI.sc`, the signature (~line 74) is:

```
		| voices, changes, clefs = nil, braces = nil, pageBreaks = nil, systemBreaks = nil |
```

Change it to append `lyrics = nil`:

```
		| voices, changes, clefs = nil, braces = nil, pageBreaks = nil, systemBreaks = nil, lyrics = nil |
```

- [ ] **Step 4: Add the `verseXml` helper just above `meiElement`**

Find `var meiElement = { |ev, md, dt, tie, k|` (~line 208). Immediately BEFORE it, insert (same 3-TAB indent as the other `var` helpers):

```
			// build the <verse>/<syl> children for an event from ev[\lyrics] (an Array over verses; each
			// entry a slot Event or nil). Empty String when the event has no syllable, so the note stays
			// self-closing (byte-identical). Syllable text is XML-escaped.
			var verseXml = { |ev|
				var out = "";
				(ev[\lyrics] ? []).do({ |slot, vi|
					if (slot.notNil) {
						var attrs = "";
						if (slot[\wordpos].notNil) { attrs = attrs ++ " wordpos=\"" ++ slot[\wordpos] ++ "\"" };
						if (slot[\con].notNil) { attrs = attrs ++ " con=\"" ++ slot[\con] ++ "\"" };
						out = out ++ "<verse n=\"" ++ (vi+1) ++ "\"><syl" ++ attrs ++ ">"
							++ PanolaMEI.pr_xmlEscape(slot[\syl]) ++ "</syl></verse>";
					};
				});
				out;
			};
```

- [ ] **Step 5: Make `meiElement` emit the verses on the first fragment only**

`meiElement` currently (~lines 208-221) is:

```
			var meiElement = { |ev, md, dt, tie, k|
				var ts = tie.notNil.if({ " tie=\"" ++ tie ++ "\"" }, {""});
				// articulation only on a whole note or the first tied fragment (not on continuations)
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

Replace the whole block with (adds `vv`, keeps the note self-closing when `vv` is empty):

```
			var meiElement = { |ev, md, dt, tie, k|
				var ts = tie.notNil.if({ " tie=\"" ++ tie ++ "\"" }, {""});
				// articulation and lyrics only on a whole note or the first tied fragment (not on continuations)
				var firstFrag = tie.isNil or: { tie == "i" };
				var aa = (((ev[\articStr] ? "") != "") and: { firstFrag }).if({ " artic=\"" ++ ev[\articStr] ++ "\"" }, { "" });
				var vv = firstFrag.if({ verseXml.(ev) }, { "" });
				if (ev[\rest]) { "<rest" ++ durAttrs.(md,dt) ++ "/>" } {
					if (ev[\pnames].size == 1) {
						var head = "<note" ++ durAttrs.(md,dt) ++ aa ++ " oct=\"" ++ ev[\octs][0] ++ "\" pname=\"" ++ ev[\pnames][0] ++ "\"" ++ accidS.(accidInKey.(ev[\pnames][0], ev[\accids][0], k)) ++ ts;
						(vv == "").if({ head ++ "/>" }, { head ++ ">" ++ vv ++ "</note>" })
					} {
						var inner = "";
						ev[\pnames].size.do({ |c| inner = inner ++ "<note oct=\"" ++ ev[\octs][c] ++ "\" pname=\"" ++ ev[\pnames][c] ++ "\"" ++ accidS.(accidInKey.(ev[\pnames][c], ev[\accids][c], k)) ++ ts ++ "/>" });
						"<chord" ++ durAttrs.(md,dt) ++ aa ++ ">" ++ inner ++ vv ++ "</chord>"
					}
				}
			};
```

- [ ] **Step 6: Add the `attachLyrics` helper**

Find `var eventsOf = { |panola|` (~line 627). Immediately BEFORE it, insert (3-TAB indent):

```
			// bind lyric slots to events: for each verse, walk the events assigning the next slot to each
			// NON-REST note (a rest consumes no slot; a melisma slot advances but yields no syllable). Sets
			// ev[\lyrics] = an Array over verses (a slot Event or nil), or nil on a rest. Warns on overflow.
			var attachLyrics = { |events, verseSlotLists, voiceIndex|
				var ptrs = Array.fill(verseSlotLists.size, 0);
				events.do({ |ev|
					if (ev[\rest]) { ev[\lyrics] = nil } {
						ev[\lyrics] = verseSlotLists.collect({ |slots, vi|
							var p = ptrs[vi], slot = (p < slots.size).if({ slots[p] }, { nil });
							ptrs[vi] = p + 1;
							(slot.notNil and: { slot[\melisma] != true }).if({ slot }, { nil });
						});
					};
				});
				verseSlotLists.do({ |slots, vi|
					if (ptrs[vi] < slots.size) {
						("PanolaMEI: " ++ (slots.size - ptrs[vi]) ++ " lyric syllables past the end of voice "
							++ (voiceIndex+1) ++ " verse " ++ (vi+1) ++ " — dropped").warn;
					};
				});
				events;
			};
			// per staff, normalize the lyrics arg into an Array (per verse) of slot-arrays.
			var lyricSlotsFor = { |vi|
				var entry = (lyrics.notNil and: { vi < lyrics.size }).if({ lyrics[vi] }, { nil });
				var verseLines = case
					{ entry.isNil } { [] }
					{ entry.isString } { [ entry ] }
					{ true } { entry };
				verseLines.collect({ |ln| PanolaMEI.pr_parseLyricLine(ln) });
			};
```

- [ ] **Step 7: Attach lyrics per voice in the body; warn on extra entries**

Find (~line 654):

```
			perVoice = voices.collect({ |p| voiceToMeasures.(annotateExpression.(eventsOf.(p)), meterFor, keyFor) });
```

Replace it with:

```
			if (lyrics.notNil and: { lyrics.size > voices.size }) {
				("PanolaMEI: lyrics has " ++ lyrics.size ++ " entries but only " ++ voices.size ++ " voices — extra ignored").warn;
			};
			perVoice = voices.collect({ |p, vi|
				voiceToMeasures.(attachLyrics.(annotateExpression.(eventsOf.(p)), lyricSlotsFor.(vi), vi), meterFor, keyFor);
			});
```

- [ ] **Step 8: Clear `\lyrics` on the carried remainder of a split tuplet donor**

Find (~line 376, inside the tuplet-completion `if (canDonor)` block):

```
								} { units[ui + 1] = ( kind: \normal, ev: dev.copy.put(\beats, dev[\beats] - remainder).put(\tieIn, compRest.not).put(\dynMark, nil).put(\slur, "").put(\hairpin, "").put(\clef, "") );
```

Add `.put(\lyrics, nil)` before the closing `)` so the tied remainder does not re-emit the donor's syllable (exactly as `\dynMark`/`\slur` are cleared):

```
								} { units[ui + 1] = ( kind: \normal, ev: dev.copy.put(\beats, dev[\beats] - remainder).put(\tieIn, compRest.not).put(\dynMark, nil).put(\slur, "").put(\hairpin, "").put(\clef, "").put(\lyrics, nil) );
```

(The main note-split path at ~line 477 reuses the SAME `ev` across fragments, so the `firstFrag` gate in `meiElement` already prevents a duplicate there — no change needed.)

- [ ] **Step 9: Run to verify the render tests pass**

Run: `py -m pytest tools/panola_mei/test_lyrics.py -k test_lyrics_render -q`
Expected: PASS.

- [ ] **Step 10: Regression — full panola_mei suite (byte-identity for lyric-free scores)**

Run: `py -m pytest tools/panola_mei/ -q`
Expected: all pass (every existing score passes `lyrics: nil` → no `<verse>`, self-closing notes unchanged).

- [ ] **Step 11: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
feat(panola_mei): scoreAsMEI lyrics arg -> <verse>/<syl>

New trailing `lyrics` arg (per staff, a list of verse lines). Slots align to
non-rest notes; verses emit on the first tied fragment only, XML-escaped. Rests
skipped, melisma leaves a note blank, overflow warns. lyrics nil = byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/panola_mei/test_lyrics.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): scoreAsMEI <verse>/<syl> render (wordpos, melisma, rest, tied, verses, escape, byte-identity)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `Panola.asMEI` / `Panola.*scoreAsMEI` pass `lyrics` through

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola\Classes\Panola.sc` (`asMEI` ~1048-1051, `*scoreAsMEI` ~1064-1067)
- Test: `D:\Projects\MusicScene\tools\panola_mei\test_lyrics.py`

- [ ] **Step 1: Write the failing test**

Append to `tools/panola_mei/test_lyrics.py`:

```python
WRAP = {
  # single-voice asMEI: lyrics is a LIST OF VERSE LINES for that one voice
  "asmei":   r'Panola("c5_4 d5 e5 f5").asMEI("4/4", \Cmajor, \treble, [ "do re mi fa" ])',
  # public Panola.scoreAsMEI wrapper forwards lyrics to PanolaMEI
  "score":   r'Panola.scoreAsMEI([Panola("c5_4 d5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil, nil, nil, [[ "hel-lo" ]])',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_panola_facade():
    outdir = tempfile.mkdtemp(prefix="panola_lyrfac_")
    try:
        _dump(outdir, WRAP)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in WRAP}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    assert meis["asmei"].count("<syl") == 4
    assert '<syl>do</syl>' in meis["asmei"]
    assert '<syl wordpos="i" con="d">hel</syl>' in meis["score"]
    assert '<syl wordpos="t">lo</syl>' in meis["score"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/panola_mei/test_lyrics.py -k test_lyrics_panola_facade -q`
Expected: FAIL — `asMEI` takes no 4th arg and `*scoreAsMEI` no 7th; neither forwards lyrics, so no `<syl>`.

- [ ] **Step 3: Add `lyrics` to `asMEI`**

`asMEI` (~lines 1048-1051) is:

```
	asMEI {
		| meter="4/4", key=\Cmajor, clef=\treble |
		^PanolaMEI.scoreAsMEI([this], [( measure: 1, meter: meter, key: key )], [clef], nil);
	}
```

Change it to:

```
	asMEI {
		| meter="4/4", key=\Cmajor, clef=\treble, lyrics=nil |
		^PanolaMEI.scoreAsMEI([this], [( measure: 1, meter: meter, key: key )], [clef], nil, nil, nil,
			lyrics.notNil.if({ [lyrics] }, { nil }));
	}
```

(A single voice's `lyrics` is a list of verse lines; wrap it as `[lyrics]` so it becomes staff 1's entry. `PanolaMEI.lyricSlotsFor` accepts either a bare String or an Array of verse Strings for that entry.)

- [ ] **Step 4: Add `lyrics` to the public `*scoreAsMEI` wrapper**

`*scoreAsMEI` (~lines 1064-1067) is:

```
	*scoreAsMEI {
		| voices, changes, clefs=nil, braces=nil, pageBreaks=nil, systemBreaks=nil |
		^PanolaMEI.scoreAsMEI(voices, changes, clefs, braces, pageBreaks, systemBreaks);
	}
```

Change it to append `lyrics=nil` and forward it:

```
	*scoreAsMEI {
		| voices, changes, clefs=nil, braces=nil, pageBreaks=nil, systemBreaks=nil, lyrics=nil |
		^PanolaMEI.scoreAsMEI(voices, changes, clefs, braces, pageBreaks, systemBreaks, lyrics);
	}
```

- [ ] **Step 5: Run to verify it passes**

Run: `py -m pytest tools/panola_mei/test_lyrics.py -k test_lyrics_panola_facade -q`
Expected: PASS.

- [ ] **Step 6: Regression**

Run: `py -m pytest tools/panola_mei/ -q`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/Panola.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
feat(panola): asMEI / scoreAsMEI accept a lyrics arg (pass-through)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/panola_mei/test_lyrics.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(panola_mei): Panola.asMEI / scoreAsMEI forward lyrics

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: MSScore `lyrics` arg

**Files:**
- Modify: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore\Classes\MSScore.sc`
- Test: `D:\Projects\MusicScene\tools\msscore\test_lyrics.py` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/msscore/test_lyrics.py`:

```python
"""MSScore forwards a lyrics arg into the MEI it builds (msscore quark).
Run:  py -m pytest tools/msscore/test_lyrics.py -q   (skips if sclang absent)
"""
import os, pytest
from tools.msscore.test_midi_routing import _run, SCLANG

SCRIPT = r'''(
var s = MSScore(voices: ["c5_4 d5 e5 f5", "c3_1"], clefs: [\treble, \bass],
    lyrics: [ [ "Twin-kle lit-tle star" ], nil ]);
var m = s.mei;
(m.contains("<syl wordpos=\"i\" con=\"d\">Twin</syl>")).if({ "SYL-OK".postln }, { "SYL-BAD".postln });
(m.contains("<verse")).if({ "VERSE-OK".postln }, { "VERSE-BAD".postln });
// staff 2 (nil) must carry no lyrics: its <staff n="2"> has no <syl>
0.exit;
)'''

NIL_SCRIPT = r'''(
var a = MSScore(voices: ["c5_4 d5"], clefs: [\treble]).mei;
var b = MSScore(voices: ["c5_4 d5"], clefs: [\treble], lyrics: nil).mei;
(a == b).if({ "SAME".postln }, { "DIFF".postln });
(a.contains("<verse")).if({ "HASVERSE".postln }, { "NOVERSE".postln });
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_msscore_forwards_lyrics():
    r = _run(SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "SYL-OK" in r.stdout, r.stdout[-1500:]
    assert "VERSE-OK" in r.stdout, r.stdout[-1500:]


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_msscore_nil_lyrics_byte_identical():
    r = _run(NIL_SCRIPT)
    assert "SAME" in r.stdout, r.stdout[-1500:]
    assert "NOVERSE" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run to verify it fails**

Run: `py -m pytest tools/msscore/test_lyrics.py -q`
Expected: `test_msscore_forwards_lyrics` FAILS (MSScore ignores `lyrics:`, no `<verse>` → `SYL-BAD`/`VERSE-BAD`). `test_msscore_nil_lyrics_byte_identical` may already pass. If both SKIP, STOP and report BLOCKED.

- [ ] **Step 3: Add the `lyrics` instance var (with whelk docs)**

In `MSScore.sc`, find `var <systemBreaks;` (~line 140). Immediately after it, add:

```
	/*
	[method.lyrics]
	description = "per-staff lyrics: an Array parallel to voices. Each entry is nil (no lyrics on that staff), an Array of verse-line Strings (stacked as <verse n=\"1\">, <verse n=\"2\">, ...), or a bare String (one verse). Whitespace separates words, '-' separates syllables (a hyphen is drawn), a whole-token '_' is a melisma (the next note holds the previous syllable), and '\\' escapes the next character. Notation only — lyrics never affect playback."
	[method.lyrics.returns]
	what = "an Array (parallel to voices) of verse-line lists / Strings / nil, or nil"
	*/
	var <lyrics;
```

- [ ] **Step 4: Add the arg to `*new` and the `super.new.init` call**

The `*new` signature (~lines 304-307) ends `... changes, pageBreaks, systemBreaks |`. Append `, lyrics`:

```
		showCursor = true, host = "127.0.0.1", listenPort = 7400, changes, pageBreaks, systemBreaks, lyrics |
```

The `super.new.init(...)` call (~line 308) ends `... systemBreaks);`. Change to append `, lyrics`:

```
		^super.new.init(voices, clefs, meter, key, braces, tempo, instruments, backends, midiOut, channels, wrap, id, space, scale, showDelay, paginate, pageHeight, showCursor, host, listenPort, changes, pageBreaks, systemBreaks, lyrics);
```

- [ ] **Step 5: Add the param to `init` and assign it**

The `init` signature (~line 337) ends `... chg, pgbr, sysbr |`. Change to append `, lyr`:

```
	init { | v, cl, m, k, br, t, instr, bk, mo, ch, wr, i, sp, sc, sd, pg, ph, scr, host, lport, chg, pgbr, sysbr, lyr |
```

Find `systemBreaks = sysbr;` (~line 343) and add after it:

```
		lyrics = lyr;                                      // nil -> no lyrics; else per-staff verse lines
```

- [ ] **Step 6: Forward `lyrics` in the `mei` method**

The `mei` method (~line 404) is:

```
	mei { ^Panola.scoreAsMEI(voices, changes ? [( measure: 1, meter: meter, key: key )], clefs, braces, pageBreaks, systemBreaks) }
```

Change it to append `, lyrics`:

```
	mei { ^Panola.scoreAsMEI(voices, changes ? [( measure: 1, meter: meter, key: key )], clefs, braces, pageBreaks, systemBreaks, lyrics) }
```

- [ ] **Step 7: Run to verify it passes**

Run: `py -m pytest tools/msscore/test_lyrics.py -q`
Expected: PASS (both tests).

- [ ] **Step 8: Full Panola + MSScore suites (regression)**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "$(cat <<'EOF'
feat(msscore): lyrics arg (per-staff verse lines) forwarded to scoreAsMEI

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "D:/Projects/MusicScene" add tools/msscore/test_lyrics.py
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
test(msscore): lyrics reach the MEI; nil lyrics byte-identical

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Docs — whelk `[general]`/examples + schelp regen (both quarks)

**Files:**
- Modify: `panola/Classes/PanolaMEI.sc` (`[general]`), `panola/Classes/Panola.sc` (`asMEI`/`scoreAsMEI` arg docs + an `[examples]` snippet), `msscore/Classes/MSScore.sc` (`[general]`)
- Regenerate: both `HelpSource/Classes/*.schelp`

- [ ] **Step 1: Panola `asMEI` / `scoreAsMEI` arg docs**

In `Panola.sc`, the `[method.asMEI.args]` block lists `meter`/`key`/`clef`. After the `clef = "..."` line, add:

```
	lyrics = "a list of verse-line Strings for this one voice (or a bare String for a single verse; nil for none). Syllables align to non-rest notes: whitespace separates words, '-' separates syllables (drawing a hyphen), a whole-token '_' is a melisma, and '\\' escapes the next character."
```

In the `[classmethod.scoreAsMEI.args]` block, after the `braces = "..."` line, add:

```
	pageBreaks = "(see link::Classes/PanolaMEI#*scoreAsMEI::)"
	systemBreaks = "(see link::Classes/PanolaMEI#*scoreAsMEI::)"
	lyrics = "an Array parallel to voices; each entry is nil, an Array of verse-line Strings, or a bare String (one verse), engraved as MEI <verse>/<syl>. See link::Classes/PanolaMEI#*scoreAsMEI::."
```

- [ ] **Step 2: PanolaMEI `[general]` + `scoreAsMEI` arg doc**

In `PanolaMEI.sc` `[general]` description, after the forced-breaks paragraph (search for `selects the mode from the encoded breaks.`), add:

```
strong::Lyrics:: — pass teletype::lyrics:: (an Array parallel to teletype::voices::; each entry a list of
verse-line Strings, a bare String for one verse, or nil) to engrave sung text as teletype::<verse>/<syl>::.
Within a verse line, whitespace separates words, teletype::-:: separates syllables (a hyphen is drawn via
teletype::wordpos::/teletype::con="d"::), a whole-token teletype::_:: is a melisma (the next note holds the
previous syllable), and teletype::\\:: escapes the next character (teletype::\\ :: for a literal space,
teletype::\\_:: for a literal underscore). Syllables align to strong::non-rest:: notes (a rest is skipped),
land on the strong::first tied fragment:: of a split note, and are XML-escaped. Lyrics are notation only.
```

In the `[classmethod.scoreAsMEI.args]` block, after the `systemBreaks = "..."` line, add:

```
	lyrics = "an Array parallel to teletype::voices::. Each entry is nil (no lyrics on that staff), an Array of verse-line Strings (stacked as teletype::<verse n=\"1\">::, teletype::<verse n=\"2\">::, ...), or a bare String (one verse). Whitespace separates words, teletype::-:: separates syllables (drawing a hyphen), a whole-token teletype::_:: is a melisma, and teletype::\\:: escapes the next character. Syllables align to non-rest notes; a note tied across a barline carries its syllable on the first fragment only."
```

- [ ] **Step 3: Panola `[examples]` snippet**

In `Panola.sc`, the `[examples]` section (near the end) has forced-break / notation examples. After the final example block (the `pageBreaks`/`systemBreaks` one, search for `systemBreaks: new line at bar 3`), add a new example:

```
// Lyrics: a separate line per staff, aligned to the non-rest notes. '-' splits a word into
// syllables (a hyphen is drawn); '_' holds the previous syllable over a note (melisma); '\'
// escapes a space or other character into a syllable. Pass a LIST of lines for several verses.
(
~mei = Panola.scoreAsMEI([Panola("c5_4 d5 e5 f5 g5_2")],
    [ ( measure: 1, meter: "4/4", key: \Cmajor ) ],
    [\treble], nil, nil, nil,
    [ [ "Twin-kle twin-kle lit-tle star,",   // verse 1
        "Up a-bove the world so high," ] ]); // verse 2
)
```

- [ ] **Step 4: MSScore `[general]` paragraph**

In `MSScore.sc` `[general]` description, after the forced-breaks paragraph (search for `Use with teletype::paginate: true::.`), add:

```
strong::Lyrics:: — teletype::lyrics: [ [ "Twin-kle lit-tle star" ], nil ]:: engraves sung text under each
staff (an Array parallel to teletype::voices::: a list of verse lines, a bare String for one verse, or nil).
Whitespace separates words, teletype::-:: separates syllables, teletype::_:: is a melisma, teletype::\\::
escapes. Notation only — lyrics never affect playback. See link::Classes/PanolaMEI#*scoreAsMEI::.
```

- [ ] **Step 5: Regenerate both schelps**

Run `gendoc.bat` at each quark root. If Git Bash `cd`/`.bat` fails, run the underlying whelk directly (as gendoc.bat does), or via PowerShell `Set-Location "<quark>"; .\gendoc.bat`:
- panola: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola`
- msscore: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore`
Expected: each finishes with no `ERROR`. After regen, scan for control-character corruption (the `\amp`→BEL trap):
Run: `grep -c $'\x07' "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/Classes/PanolaMEI.sc"`
Expected: `0` (also `0` for the other edited `.sc` files).

- [ ] **Step 6: Verify docs mention lyrics and classes still compile**

Run: `grep -l "lyrics" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/PanolaMEI.schelp" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola/HelpSource/Classes/Panola.schelp" "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore/HelpSource/Classes/MSScore.schelp"`
Expected: all three listed.
Run: `py -m pytest tools/panola_mei/test_lyrics.py tools/msscore/test_lyrics.py -q`
Expected: PASS (a fresh sclang recompiles all edited classes cleanly).

- [ ] **Step 7: Commit**

```bash
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" add Classes/PanolaMEI.sc Classes/Panola.sc HelpSource/Classes/PanolaMEI.schelp HelpSource/Classes/Panola.schelp
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/panola" commit -m "$(cat <<'EOF'
docs(panola): document lyrics arg + example; regenerate schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc HelpSource/Classes/MSScore.schelp
git -C "C:/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "$(cat <<'EOF'
docs(msscore): document lyrics arg; regenerate schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: SuperCollider example

**Files:**
- Create: `D:\Projects\MusicScene\examples\supercollider\example_lyrics.scd`

- [ ] **Step 1: Write the example**

Create `examples/supercollider/example_lyrics.scd`:

```supercollider
// =============================================================================
// MSScore lyrics — sung text under a staff, authored as a SEPARATE line per staff.
//
//   lyrics: [ <staff 1>, <staff 2>, ... ]     parallel to `voices`
//     each entry:  a list of verse lines  [ "verse 1", "verse 2" ]   (stacked verses)
//                  a bare String           "one verse"
//                  nil                      no lyrics on that staff
//
//   In a verse line:
//     space   -> next word
//     -       -> hyphen between syllables of one word   (Twin-kle -> Twin- kle)
//     _       -> melisma: the note holds the previous syllable (no new syllable)
//     \       -> escape the next character into the syllable ( \  = space, \_ = underscore )
//
// Lyrics are NOTATION ONLY — they never change the sound.
// REQUIRES: the Panola + MSScore quarks (Quarks.install), MusicScene running with Verovio.
// USAGE: run the Godot project (one instance), put the cursor in the ( ) block, Ctrl+Enter.
// =============================================================================

(
// A melody + a bass line. Only the melody gets lyrics (two verses); the bass stays nil.
~melody = "c5_4 d5 e5 f5 g5_2 g5_4 a5 g5 f5 e5_2 e5_4 d5 c5_1";
~bass   = "c3_2 g3 c3_2 g3 c3_2 c3 c3_1";

~score = MSScore(
	voices:  [ ~melody, ~bass ],
	clefs:   [ \treble, \bass ],
	braces:  [ [1, 2] ],
	meter:   "4/4", key: \Cmajor, tempo: 96,
	lyrics:  [
		[ "Twin-kle twin-kle lit-tle star,",       // melody, verse 1
		  "Up a-bove the world so high," ],        // melody, verse 2
		nil                                        // bass: no lyrics
	],
	space:   "2d"
);

~score.show;
"Lyrics: two verses under the melody. '-' draws hyphens; try a melisma with '_' or an escaped space '\\ '.".postln;
)


// ~score.play;    // hear it (lyrics do NOT affect the sound)
// ~score.stop;    // clear the scene
```

- [ ] **Step 2: Verify the example builds valid, lyric-bearing MEI**

Build the example's MEI via sclang and confirm the syllables render. Run (Git Bash):
create a scratch `.scd` that assigns `~melody`/`~bass`, builds `s = MSScore(... lyrics: [[ "Twin-kle twin-kle lit-tle star,", "Up a-bove the world so high," ], nil] ...)`, writes `s.mei` to a temp file, `0.exit;`. Then:
```
grep -c "<verse n=\"2\"" <mei>    # expect > 0 (verse 2 present)
grep -o "<syl[^>]*>Twin</syl>" <mei>   # expect a wordpos="i" con="d" syllable
py "D:/Projects/MusicScene/tools/panola_mei/render_check.py" <mei>   # expect a dict with 'ok': True
```
Expected: verse 2 present, the `Twin` syllable carries `wordpos="i" con="d"`, and `render_check` reports `ok: True` (Verovio renders the verses).

- [ ] **Step 3: Commit**

```bash
git -C "D:/Projects/MusicScene" add examples/supercollider/example_lyrics.scd
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs(examples): example_lyrics.scd — sung lyrics under a staff (two verses)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: README / TUTORIAL / CHANGELOG + finish

**Files:**
- Modify: `D:\Projects\MusicScene\README.md`, `D:\Projects\MusicScene\TUTORIAL.md`, `D:\Projects\MusicScene\CHANGELOG.md`

- [ ] **Step 1: README notation mention**

In `README.md`, the MSScore notation subsection (search for the MSScore constructor example / the `wrap:` paragraph added earlier). After that paragraph, add:

```
**Lyrics.** Pass `lyrics:` — an array parallel to `voices`, one entry per staff (a list of verse
lines, a bare string for one verse, or `nil`) — to engrave sung text as MEI `<verse>/<syl>`. In a
line, a space starts the next word, `-` splits a word into syllables (a hyphen is drawn), `_` holds
the previous syllable over a note (melisma), and `\` escapes the next character into a syllable.
Syllables align to the non-rest notes; lyrics are notation only and never affect the sound.
Example: `examples/supercollider/example_lyrics.scd`.
```

- [ ] **Step 2: TUTORIAL notation mention**

In `TUTORIAL.md` §9 (the Panola/MSScore notation section, near subsection E "Panola in SuperCollider"), after the `wrap:` subsection ("Making the printed marks audible"), add a short subsection:

```
**Adding lyrics.** Sung text is a separate line per staff, passed as `lyrics:` (parallel to
`voices`). Each staff takes a list of verse lines (or a bare string, or `nil`):

```supercollider
~score = MSScore(
    voices: [ "c5_4 d5 e5 f5 g5_2" ],
    lyrics: [ [ "Twin-kle twin-kle star",     // verse 1
               "Up a-bove the world" ] ]      // verse 2
);
~score.show;
```

Within a line: a space starts the next word, `-` splits a word into syllables (drawing a hyphen),
`_` is a melisma (the note holds the previous syllable), and `\` escapes the next character (`\ ` = a
literal space inside a syllable). Syllables align to the non-rest notes, a note tied across a barline
carries its syllable on the first fragment, and lyrics never affect playback. Runnable:
`examples/supercollider/example_lyrics.scd`.
```

- [ ] **Step 3: CHANGELOG entry**

In `CHANGELOG.md`, add an `### Added` bullet under the current top (unreleased) version entry:

```
- **Lyrics in Panola notation.** `MSScore(lyrics: [[ "Twin-kle lit-tle star" ], nil])` (and the new
  `lyrics` arg on `Panola.asMEI` / `Panola.scoreAsMEI`) engrave sung text as MEI `<verse>/<syl>`,
  authored as a separate line per staff. A space separates words, `-` splits syllables (drawing a
  hyphen), `_` is a melisma, `\` escapes; several lines give several verses. Syllables align to the
  non-rest notes and land on the first tied fragment; lyrics are notation only (they never affect the
  sound). Example: `examples/supercollider/example_lyrics.scd`. (Panola + MSScore quarks.)
```

- [ ] **Step 4: Full suite green**

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q`
Expected: all pass.

- [ ] **Step 5: Commit docs (incl. spec + plan)**

```bash
git -C "D:/Projects/MusicScene" add README.md TUTORIAL.md CHANGELOG.md docs/superpowers/specs/2026-07-10-panola-lyrics-design.md docs/superpowers/plans/2026-07-10-panola-lyrics.md
git -C "D:/Projects/MusicScene" commit -m "$(cat <<'EOF'
docs: lyrics in README/TUTORIAL/CHANGELOG + spec + plan

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Finish the branch**

Use **superpowers:finishing-a-development-branch** for MusicScene `feature/panola-lyrics`. The Panola (`master`) and MSScore (`main`) quark commits live in their own repos. Pushing all three repos and any release/tag ([[release-doc-version-consistency]]) are the user's responsibility — do not push.

---

## Self-review

**Spec coverage (against `2026-07-10-panola-lyrics-design.md`):**
- §1 authoring API — `lyrics` trailing arg on PanolaMEI (Task 2), Panola `asMEI`/`scoreAsMEI` (Task 3), MSScore (Task 4); per-staff list-of-verses / bare-string / nil normalization in `lyricSlotsFor` (Task 2 Step 6); `lyrics` shorter than voices → none, longer → warn (Task 2 Steps 6-7). ✓
- §2 grammar & alignment — tokenizer `pr_parseLyricLine` (Task 1): whitespace/`-`/`_`/`\`, wordpos i/m/t + con=d; rest-skip + melisma-blank + non-rest alignment in `attachLyrics` (Task 2 Step 6); overflow warn (Task 2 Step 6); underflow silent (no code = trailing notes get nil). ✓
- §3 MEI output — `<verse>/<syl>`, multi-verse `n`, first-tied-fragment guard, byte-identity self-closing when empty, `\lyrics` cleared on split remainder (Task 2 Steps 4/5/8); XML-escape (Task 1 `pr_xmlEscape`, used in `verseXml`). ✓
- §4 components/files — all logic in PanolaMEI; Panola/MSScore pass-through (Tasks 2-4). ✓
- §5 testing — tokenizer unit cases (Task 1), full render incl. wordpos/melisma/rest/tied/multi-verse/overflow/byte-identity (Task 2), facade (Task 3), MSScore + nil byte-identity (Task 4). ✓
- §6 standing rules — whelk + schelp regen (Task 5), example (Task 6), README/TUTORIAL + CHANGELOG (Task 7); version bump left for release. ✓

**Placeholder scan:** No TBD/TODO/"similar to". Every code step shows the code; every run step gives the command and expected result. The two verify-by-scratch-script steps (Task 5 Step 5 render is via pytest; Task 6 Step 2) describe the exact greps/commands and expected values.

**Type / name consistency:** `lyrics` is the arg name across PanolaMEI `*scoreAsMEI`, Panola `asMEI`/`*scoreAsMEI`, and MSScore `*new`/`init`/`mei` (MSScore init param `lyr` → var `lyrics`). Slot shape `( syl:, wordpos:, con: )` / `( melisma: true )` produced by `pr_parseLyricLine` (Task 1) is exactly what `verseXml` and `attachLyrics` consume (Task 2). Canonical tokenizer format `syl|wordpos|con` / `_` in `_tok` matches the emitted attributes. The MEI substrings asserted in tests (`<syl wordpos="i" con="d">Twin</syl>`, `<verse n="2">`, `<syl>R&amp;B</syl>`) match `verseXml`'s output (`n` is `vi+1`; wordpos before con; `pr_xmlEscape` maps `&`→`&amp;`). The split-remainder clear adds `.put(\lyrics, nil)` alongside the existing `\dynMark`/`\slur`/`\hairpin`/`\clef` clears.
```
