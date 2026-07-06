# MSScore MIDI (hardware-synth) playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `MSScore` play each voice on either a built-in SuperCollider synth (`\internal`, the default) or an external/hardware synth over MIDI (`\midi`), selectable per voice, under the same note-accurate follow cursor.

**Architecture:** MSScore already builds one pattern per voice with `Panola#asPbind` and plays a single `Ppar` on a shared `TempoClock`. This adds four per-voice constructor args (`backends`, `midiOut`, `channels`, `wrap`), routes each voice through `asPbind` or `asMidiPbind` in a new `pr_voicePatterns` helper, validates inputs, and sends all-notes-off on `stop`. The cursor/notation are untouched (backend-agnostic).

**Tech Stack:** SuperCollider (msscore quark `MSScore.sc`; Panola quark provides `asMidiPbind`, confirmed present in the pinned `panola@tags/0.4.0`). Tests: Python pytest driving headless `sclang` (pure pattern inspection — no audio server, no MIDI hardware). Docs: whelk → schelp via gendoc.

---

## Repositories & branches

Two git repos are involved (as in the prior Panola/MSScore features):

- **msscore quark** — `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore` (git branch **main**). All `MSScore.sc` and `HelpSource/` changes commit here. (bash path: `/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore`)
- **MusicScene repo** — `D:\Projects\MusicScene` (git branch **feature/msscore-midi**, already created; the design spec is committed there). The plan, tests (`tools/msscore/`) and the example (`examples/supercollider/`) commit here.

The msscore quark's development branch is `main` (its GitHub push/tag is the user's step, matching prior features). Editing any `.sc` file recompiles the SuperCollider class library on the next `sclang` run, so the tests pick up the edits automatically.

Class file under edit: `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\msscore\Classes\MSScore.sc`.

## File structure

- **`…/msscore/Classes/MSScore.sc`** (modify) — the whole feature: 4 new instance vars + accessors, extended `*new`/`init`, new private methods `pr_validate`, `pr_midiOutFor`, `pr_voicePatterns`, `pr_allNotesOff`, and changed `pr_startPlayback`/`stop`. Whelk doc comments updated.
- **`…/msscore/HelpSource/Classes/MSScore.schelp`** (regenerate) — from the whelk comments via gendoc.
- **`D:\Projects\MusicScene\tools\msscore\test_midi_routing.py`** (create) — headless sclang routing/validation/all-notes-off tests.
- **`D:\Projects\MusicScene\examples\supercollider\example_msscore_midi.scd`** (create) — a mixed `\internal`/`\midi` example (MIDI lines commented so it runs with no hardware).

---

### Task 1: Constructor args, defaults, and validation

**Files:**
- Modify: `…/msscore/Classes/MSScore.sc` (instance vars after `var <instruments;`; the `*new` and `init` methods; add `pr_validate`)
- Test: `D:\Projects\MusicScene\tools\msscore\test_midi_routing.py`

- [ ] **Step 1: Write the failing tests** (create `tools\msscore\test_midi_routing.py`)

```python
"""MIDI (hardware-synth) playback tests for MSScore (msscore quark).
Pure sclang pattern inspection -- no audio server, no MIDI hardware. Run:
  py -m pytest tools/msscore/test_midi_routing.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script)
        path = f.name
    try:
        return subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)


DEFAULTS_SCRIPT = r'''(
var s = MSScore(voices: ["c4_4 d4", "c3_4 e3"], clefs: [\treble, \bass]);
("BACKENDS:" ++ s.backends.asString).postln;
("CHANNELS:" ++ s.channels.asString).postln;
("WRAP_NIL:" ++ s.wrap.every({ |w| w.isNil }).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_defaults():
    r = _run(DEFAULTS_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "BACKENDS:[ internal, internal ]" in r.stdout, r.stdout[-1500:]
    assert "CHANNELS:[ 0, 1 ]" in r.stdout, r.stdout[-1500:]
    assert "WRAP_NIL:true" in r.stdout, r.stdout[-1500:]


VALIDATION_SCRIPT = r'''(
var e1 = "none", e2 = "none";
try { MSScore(voices: ["c4_4"], backends: [\midi]) } { |err| e1 = err.errorString };
try { MSScore(voices: ["c4_4", "c3_4"], backends: [\midi]) } { |err| e2 = err.errorString };
("NO_MIDIOUT:" ++ e1).postln;
("LENGTH:" ++ e2).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_validation_errors():
    r = _run(VALIDATION_SCRIPT)
    assert "needs a midiOut" in r.stdout, r.stdout[-1500:]
    assert "must have one entry per voice" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py -q`
Expected: FAIL — `test_defaults` errors because `MSScore` has no `backends`/`channels`/`wrap` accessor yet; `test_validation_errors` fails because no validation is raised.

- [ ] **Step 3: Add the four instance vars (with whelk docs)**

In `MSScore.sc`, replace the single line `\tvar <instruments;` with that line followed by the new vars:

```supercollider
	var <instruments;
	/*
	[method.backends]
	description = "per-voice playback backend: \\internal (SuperCollider synth) or \\midi (external/hardware synth)"
	[method.backends.returns]
	what = "an Array of Symbols (\\internal / \\midi)"
	*/
	var <backends;
	/*
	[method.midiOut]
	description = "the MIDIOut(s) used by \\midi voices: a single MIDIOut shared by all of them, or an Array of MIDIOut (one per voice)"
	[method.midiOut.returns]
	what = "a MIDIOut, an Array of MIDIOut, or nil"
	*/
	var <midiOut;
	/*
	[method.channels]
	description = "per-voice MIDI channel (0..15), used only by \\midi voices"
	[method.channels.returns]
	what = "an Array of Integers"
	*/
	var <channels;
	/*
	[method.wrap]
	description = "per-voice pattern transform applied after the base pattern is built: nil, or a Function { |pattern, voiceIndex| newPattern }. Use it to add per-note MIDI control (CC / sustain pedal / program change) while keeping the shared clock and follow cursor."
	[method.wrap.returns]
	what = "an Array whose entries are nil or a Function"
	*/
	var <wrap;
```

- [ ] **Step 4: Extend the `*new` signature and its init call**

Replace the whole `*new { … }` method with:

```supercollider
	*new { | voices, clefs, meter = "4/4", key = \Cmajor, braces, tempo = 84, instruments,
		backends, midiOut, channels, wrap,
		id = "score", space = "2d", scale, showDelay = 1.0, paginate = true, pageHeight = 1200,
		host = "127.0.0.1", listenPort = 7400 |
		^super.new.init(voices, clefs, meter, key, braces, tempo, instruments, backends, midiOut, channels, wrap, id, space, scale, showDelay, paginate, pageHeight, host, listenPort);
	}
```

- [ ] **Step 5: Extend `init` to store/default the new args and validate**

Replace the whole `init { … }` method with:

```supercollider
	init { | v, cl, m, k, br, t, instr, bk, mo, ch, wr, i, sp, sc, sd, pg, ph, host, lport |
		voices = v.collect({ |x| x.isKindOf(Panola).if({ x }, { Panola(x) }) });
		clefs = cl ? voices.collect({ \treble });
		meter = m; key = k; braces = br; tempo = t; id = i; space = sp;
		instruments = instr ? voices.collect({ \default });
		backends = bk ? voices.collect({ \internal });
		channels = ch ? voices.collect({ |x, ix| ix });   // default: each voice on its own MIDI channel
		wrap = wr ? voices.collect({ nil });
		midiOut = mo;
		scale = sc ? (sp == "3d").if({ 2.5 }, { 0.7 });   // pass `scale:` to enlarge/shrink the score
		showDelay = sd;                                    // seconds to let the notation render before playing
		paginate = pg; pageHeight = ph;                    // split long scores into pages that turn automatically
		engine = NetAddr(host, lport);
		totalBeats = voices.collect({ |p| p.totalDuration }).maxItem;
		this.pr_validate;
	}
```

- [ ] **Step 6: Add the `pr_validate` method** (place it right after the `init` method)

```supercollider
	/*
	[method.pr_validate]
	description = "(private) check that the per-voice arrays are parallel to voices and that \\midi voices have a usable midiOut; clamp out-of-range MIDI channels with a warning"
	*/
	pr_validate {
		var n = voices.size;
		[["clefs", clefs], ["instruments", instruments], ["backends", backends],
		 ["channels", channels], ["wrap", wrap]].do({ |pair|
			(pair[1].size != n).if({
				Error("MSScore: '" ++ pair[0] ++ "' must have one entry per voice (" ++ n ++ "), got " ++ pair[1].size ++ ".").throw;
			});
		});
		if (backends.includes(\midi)) {
			midiOut.isNil.if({
				Error("MSScore: a \\midi voice needs a midiOut (a MIDIOut, or an Array of MIDIOut).").throw;
			});
			midiOut.isArray.if({
				(midiOut.size != n).if({
					Error("MSScore: midiOut Array must have one entry per voice (" ++ n ++ "), got " ++ midiOut.size ++ ".").throw;
				});
				backends.do({ |b, ix|
					(b == \midi and: { midiOut[ix].isNil }).if({
						Error("MSScore: midiOut[" ++ ix ++ "] is nil but voice " ++ ix ++ " is \\midi.").throw;
					});
				});
			});
			channels = channels.collect({ |c, ix|
				(backends[ix] == \midi and: { (c < 0) or: { c > 15 } }).if({
					warn("MSScore: MIDI channel " ++ c ++ " for voice " ++ ix ++ " out of 0..15; clamping.");
					c.clip(0, 15);
				}, { c });
			});
		};
	}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py -q`
Expected: PASS (2 passed).

- [ ] **Step 8: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "feat(msscore): per-voice backends/midiOut/channels/wrap args + validation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/msscore/test_midi_routing.py
git commit -m "test(msscore): MSScore MIDI arg defaults + validation (headless sclang)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Per-voice pattern routing

**Files:**
- Modify: `…/msscore/Classes/MSScore.sc` (add `pr_midiOutFor` + `pr_voicePatterns`; change the `Ppar(...)` line in `pr_startPlayback`)
- Test: `D:\Projects\MusicScene\tools\msscore\test_midi_routing.py` (add `test_routing`)

- [ ] **Step 1: Add the failing test** (append to `test_midi_routing.py`)

```python
ROUTING_SCRIPT = r'''(
var s, pats, e0, e1;
s = MSScore(
    voices: ["c4_4 d4 e4 f4", "c3_4 e3 g3 c4"],
    clefs: [\treble, \bass],
    backends: [\internal, \midi],
    midiOut: \dummyMidi,
    channels: [0, 1],
    wrap: [nil, { |pat, i| Pbindf(pat, \wrapMarker, 42) }]
);
pats = s.pr_voicePatterns;
e0 = pats[0].asStream.next(());
e1 = pats[1].asStream.next(());
("E0_TYPE_MIDI:" ++ (e0[\type] == \midi).asString).postln;
("E0_HAS_INSTRUMENT:" ++ e0[\instrument].notNil.asString).postln;
("E1_TYPE:" ++ e1[\type].asString).postln;
("E1_CHAN:" ++ e1[\chan].asString).postln;
("E1_MIDIOUT_OK:" ++ (e1[\midiout] === \dummyMidi).asString).postln;
("E1_WRAP:" ++ e1[\wrapMarker].asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_routing():
    r = _run(ROUTING_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "E0_TYPE_MIDI:false" in r.stdout, r.stdout[-1500:]
    assert "E0_HAS_INSTRUMENT:true" in r.stdout, r.stdout[-1500:]
    assert "E1_TYPE:midi" in r.stdout, r.stdout[-1500:]
    assert "E1_CHAN:1" in r.stdout, r.stdout[-1500:]
    assert "E1_MIDIOUT_OK:true" in r.stdout, r.stdout[-1500:]
    assert "E1_WRAP:42" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py::test_routing -q`
Expected: FAIL — `pr_voicePatterns` does not exist yet (sclang posts `doesNotUnderstand`, so the markers are missing / `ERROR` present).

- [ ] **Step 3: Add `pr_midiOutFor` and `pr_voicePatterns`** (place both right before the `pr_startPlayback` method)

```supercollider
	/*
	[method.pr_midiOutFor]
	description = "(private) the MIDIOut for voice i: the shared midiOut, or midiOut[i] when midiOut is a per-voice Array"
	[method.pr_midiOutFor.args]
	i = "the voice index"
	[method.pr_midiOutFor.returns]
	what = "a MIDIOut (or nil)"
	*/
	pr_midiOutFor { | i | ^midiOut.isArray.if({ midiOut[i] }, { midiOut }); }

	/*
	[method.pr_voicePatterns]
	description = "(private) the pattern for each voice: asPbind for an \\internal voice, asMidiPbind for a \\midi voice, then passed through this voice's wrap function if one is set"
	[method.pr_voicePatterns.returns]
	what = "an Array of patterns (one per voice), ready for a Ppar"
	*/
	pr_voicePatterns {
		^voices.collect({ | p, i |
			var pat = (backends[i] == \midi).if(
				{ p.asMidiPbind(this.pr_midiOutFor(i), channels[i], include_tempo: false) },
				{ p.asPbind(instruments[i], include_tempo: false) }
			);
			wrap[i].notNil.if({ wrap[i].value(pat, i) }, { pat });
		});
	}
```

- [ ] **Step 4: Route `pr_startPlayback` through the helper**

In `pr_startPlayback`, replace the line

```supercollider
		player = Ppar(voices.collect({ |p, i| p.asPbind(instruments[i], include_tempo: false) })).play(clock, quant: 0);
```

with

```supercollider
		player = Ppar(this.pr_voicePatterns).play(clock, quant: 0);
```

- [ ] **Step 5: Run all MSScore tests to verify they pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py -q`
Expected: PASS (3 passed).

- [ ] **Step 6: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "feat(msscore): route each voice via asPbind/asMidiPbind (+ wrap) in pr_voicePatterns

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/msscore/test_midi_routing.py
git commit -m "test(msscore): per-voice internal/midi routing + wrap hook

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: All-notes-off on stop

**Files:**
- Modify: `…/msscore/Classes/MSScore.sc` (change `stop`; add `pr_allNotesOff`)
- Test: `D:\Projects\MusicScene\tools\msscore\test_midi_routing.py` (add `test_all_notes_off`)

- [ ] **Step 1: Add the failing test** (append to `test_midi_routing.py`)

The stub is a SuperCollider Event with a `\control` function; calling `stub.control(ch, cc, val)` triggers the Event's pseudo-method dispatch, recording the call — so we can verify `pr_allNotesOff` sends CC 123 without any real MIDI device.

```python
ALLNOTESOFF_SCRIPT = r'''(
var s, calls = List.new, stub;
stub = ( control: { |self, ch, cc, val| calls.add([ch, cc, val]) } );
s = MSScore(voices: ["c4_4 d4"], backends: [\midi], midiOut: stub, channels: [5]);
s.pr_allNotesOff;
("CALLS:" ++ calls.asArray.asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_all_notes_off():
    r = _run(ALLNOTESOFF_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "CALLS:[ [ 5, 123, 0 ] ]" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py::test_all_notes_off -q`
Expected: FAIL — `pr_allNotesOff` does not exist yet.

- [ ] **Step 3: Change `stop` and add `pr_allNotesOff`**

Replace the whole `stop { … }` method with:

```supercollider
	stop {
		clock.notNil.if({ clock.stop; clock = nil });
		player.notNil.if({ player.stop });
		cursorRoutine.notNil.if({ cursorRoutine.stop });
		this.pr_allNotesOff;
		Server.default.freeAll;
		engine.sendMsg("/ms/scene", "clear");
	}

	/*
	[method.pr_allNotesOff]
	description = "(private) send an all-notes-off (CC 123) to each \\midi voice's device and channel, so stopping mid-note leaves no hanging hardware notes; each device+channel is sent once"
	*/
	pr_allNotesOff {
		var done = [];
		backends.do({ | b, i |
			var mo, ch, k;
			if (b == \midi) {
				mo = this.pr_midiOutFor(i);
				ch = channels[i];
				k = [mo, ch];
				if (mo.notNil and: { done.includes(k).not }) {
					mo.control(ch, 123, 0);   // CC 123 = All Notes Off
					done = done.add(k);
				};
			};
		});
	}
```

- [ ] **Step 4: Run all MSScore tests to verify they pass**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit** (two repos)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "feat(msscore): all-notes-off (CC 123) for MIDI voices on stop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd /d/Projects/MusicScene
git add tools/msscore/test_midi_routing.py
git commit -m "test(msscore): stop sends all-notes-off to each MIDI voice's channel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Whelk docs + regenerate HelpSource

**Files:**
- Modify: `…/msscore/Classes/MSScore.sc` (`[general]` description; `*new` arg docs)
- Regenerate: `…/msscore/HelpSource/Classes/MSScore.schelp`

- [ ] **Step 1: Add a MIDI section to the `[general]` description**

In the `[general]` block, immediately after the Slurs example line

```
teletype::c5_4@slur^start^ d5 e5@slur^endstart^ f5 g5@slur^end^ a5::.
```

and before the `Requires the link::Classes/Panola::` paragraph, insert a blank line and:

```
strong::MIDI / hardware synths:: - by default every voice plays on a SuperCollider synth (backend
teletype::\internal::). To play a voice on an external/hardware synth instead, set strong::backends:: to
teletype::\midi:: for that voice and pass strong::midiOut:: - either a single link::Classes/MIDIOut::
shared by all teletype::\midi:: voices, or an Array of MIDIOut (one per voice). strong::channels:: gives
each voice a MIDI channel (default: the voice's index, so one multitimbral device gets a distinct channel
per staff); teletype::instruments:: applies only to teletype::\internal:: voices. For per-note MIDI
control (CC, sustain pedal, program change) pass strong::wrap::, a teletype::{ |pattern, i| newPattern }::
per voice applied to the built pattern - e.g.
teletype::{ |pat, i| Pbindf(pat, \handle, Pfunc { |ev| midiOut.control(ev[\chan], 64, (ev[\ped] ? 0).asInteger) }) }::
turns a teletype::@ped:: property into a sustain-pedal controller. You create and own the MIDIOut
(teletype::MIDIClient.init; MIDIOut.newByName(...)::); MSScore never opens devices. The follow cursor works
the same over MIDI.
```

- [ ] **Step 2: Confirm the new `*new`/`init` arg docs are present**

The four `[classmethod.new.args]` docs (`backends`/`midiOut`/`channels`/`wrap`, plus the clarified `instruments` line) and the four `[method.init.args]` docs (`bk`/`mo`/`ch`/`wr`) were added in Task 1 (to keep the whelk docs current with the arg addition). Verify they are present in `MSScore.sc`; if for some reason they are missing, add them now with the wording from Task 1. No other change needed in this step.

- [ ] **Step 3: Regenerate the schelp via gendoc**

Run:
```bash
cd "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" && \
"/d/Projects/python/whelk/.venv/Scripts/python.exe" "/d/Projects/python/whelk/whelk.py" \
  -i Classes/MSScore.sc -o HelpSource/Classes
```
Expected: it writes `HelpSource/Classes/MSScore.schelp` with no error.

- [ ] **Step 4: Verify the generated schelp mentions the new args**

Run: `grep -c -E 'midiOut|backends|wrap' "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore/HelpSource/Classes/MSScore.schelp"`
Expected: a non-zero count (the MIDI section + arg docs rendered).

- [ ] **Step 5: Commit** (msscore repo)

```bash
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" add Classes/MSScore.sc HelpSource/Classes/MSScore.schelp
git -C "/c/Users/Stefaan Himpe/AppData/Local/SuperCollider/Extensions/msscore" commit -m "docs(msscore): document MIDI backends/midiOut/channels/wrap; regen schelp

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Mixed-backend example

**Files:**
- Create: `D:\Projects\MusicScene\examples\supercollider\example_msscore_midi.scd`

- [ ] **Step 1: Write the example**

```supercollider
// example_msscore_midi.scd
//
// MSScore plays each voice either on a built-in SuperCollider synth (\internal, the default)
// or on an external/hardware synth over MIDI (\midi). A single score can mix them.
//
// As written, BOTH voices play on SC synths, so this runs with no hardware. To send the bass
// (voice 2) to a hardware synth, open your device in the OPTIONAL block, then switch ~backends
// / ~midiOut in the score block as noted.

// ---- OPTIONAL: open your MIDI device (edit the names for your hardware) --------------------
/*
(
if (MIDIClient.initialized.not) { MIDIClient.init };
~integra = MIDIOut.newByName("INTEGRA-7", "INTEGRA-7 MIDI 1");   // <- change to your device
)
*/

// ---- boot the audio server (needed for the \internal voices) ------------------------------
(
s.boot;
)

// ---- build the score ----------------------------------------------------------------------
(
~backends = [\internal, \internal];   // all-internal default
~midiOut  = nil;

// To play the bass over MIDI instead, comment the two lines above and uncomment these
// (after opening ~integra in the OPTIONAL block):
// ~backends = [\internal, \midi];
// ~midiOut  = ~integra;

~score = MSScore(
    voices:   [ "c5_4@dyn^mf^ e5 g5 c6", "c3_2 g3_2" ],
    clefs:    [ \treble, \bass ],
    meter:    "4/4",
    key:      \Cmajor,
    braces:   [ [1, 2] ],
    tempo:    84,
    space:    "2d",
    backends: ~backends,
    midiOut:  ~midiOut,
    channels: [ 0, 1 ],       // used only by \midi voices
    // per-note MIDI control example (sustain pedal from a @ped property) on a \midi voice:
    // wrap: [ nil, { |pat, i| Pbindf(pat, \handle, Pfunc { |ev| ~integra.control(ev[\chan], 64, (ev[\ped] ? 0).asInteger) }) } ]
);
)

~score.play;   // display the notation, play the voices, follow with the cursor
~score.stop;   // stop (all-notes-off for MIDI voices), free synths, clear the scene
```

- [ ] **Step 2: Add a pytest check that the example's MSScore call is valid against the new API**

This constructs the same call the example uses (all-internal, no `play`, so no server/OSC), confirming the example's API usage stays correct. Append to `tools\msscore\test_midi_routing.py`:

```python
EXAMPLE_SCRIPT = r'''(
var s = MSScore(
    voices:   [ "c5_4@dyn^mf^ e5 g5 c6", "c3_2 g3_2" ],
    clefs:    [ \treble, \bass ],
    meter:    "4/4", key: \Cmajor, braces: [ [1, 2] ], tempo: 84, space: "2d",
    backends: [\internal, \internal], midiOut: nil, channels: [0, 1]
);
("EXAMPLE_OK:" ++ (s.notNil and: { s.backends == [\internal, \internal] }).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_example_constructs():
    r = _run(EXAMPLE_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "EXAMPLE_OK:true" in r.stdout, r.stdout[-1500:]
```

- [ ] **Step 3: Run the check to verify it passes**

Run: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py::test_example_constructs -q`
Expected: PASS.

- [ ] **Step 4: Commit** (MusicScene repo)

```bash
cd /d/Projects/MusicScene
git add examples/supercollider/example_msscore_midi.scd tools/msscore/test_midi_routing.py
git commit -m "docs(example): MSScore mixed internal/MIDI playback example (+ API check)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Run the whole MSScore test file once more: `cd /d/Projects/MusicScene && py -m pytest tools/msscore/test_midi_routing.py -q` → **7 passed** (defaults, validation, routing, routing-midiout-array, all-notes-off, all-notes-off-dedupe, example). *(The routing-midiout-array and all-notes-off-dedupe tests were added during code review to cover the per-voice-Array and de-dup branches.)*
- [ ] Run the existing suite to confirm no regression: `cd /d/Projects/MusicScene && py -m pytest tools/panola_mei -q` → all pass (unchanged; MSScore playback isn't exercised there).
- [ ] Sanity-check an `\internal`-only score still plays (manual): in SuperCollider boot the server, `MSScore(voices: ["c5_4 e5 g5 c6"]).play` shows and plays exactly as before.

## Notes for the implementer

- **sclang gotchas:** every test script ends with `0.exit;` so `sclang` returns cleanly (the pytest `timeout=120` is a backstop, not the normal exit path). sclang buffers stdout; if a script seems to hang, it usually means a compile error in `MSScore.sc` — run `sclang` on the script by hand to see the class-library error. A leftover hung `sclang` can be cleared with PowerShell `Get-Process sclang | Stop-Process -Force`.
- **Editing `MSScore.sc` recompiles the class library** on the next `sclang` run, so a syntax error surfaces immediately as the first test run failing to construct `MSScore`.
- **The all-notes-off test stub** relies on SuperCollider Event pseudo-methods: `( control: { |self, ch, cc, val| … } )` makes `stub.control(5, 123, 0)` dispatch to the stored function. If a future SC version defines a real `control` on `Event`, switch the stub key to an unused selector and update `pr_allNotesOff` accordingly (it is the only caller in the test).
- **Whitespace in `.sc` edits:** SuperCollider ignores indentation, so if an exact multi-line match fails, match on a single unique line instead. The class file is tab-indented.
```
