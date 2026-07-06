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
    assert "BACKENDS:[internal, internal]" in r.stdout, r.stdout[-1500:]
    assert "CHANNELS:[0, 1]" in r.stdout, r.stdout[-1500:]
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


ROUTING_ARRAY_SCRIPT = r'''(
var s, pats, e0, e1;
s = MSScore(
    voices: ["c4_4 d4", "c3_4 e3"],
    clefs: [\treble, \bass],
    backends: [\midi, \midi],
    midiOut: [\mZero, \mOne],
    channels: [0, 1]
);
pats = s.pr_voicePatterns;
e0 = pats[0].asStream.next(());
e1 = pats[1].asStream.next(());
("E0_MIDIOUT:" ++ (e0[\midiout] === \mZero).asString).postln;
("E1_MIDIOUT:" ++ (e1[\midiout] === \mOne).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_routing_midiout_array():
    r = _run(ROUTING_ARRAY_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "E0_MIDIOUT:true" in r.stdout, r.stdout[-1500:]
    assert "E1_MIDIOUT:true" in r.stdout, r.stdout[-1500:]


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
    assert "CALLS:[[5, 123, 0]]" in r.stdout, r.stdout[-1500:]


ALLNOTESOFF_DEDUPE_SCRIPT = r'''(
var same, diff, callsSame = List.new, callsDiff = List.new, stubSame, stubDiff;
stubSame = ( control: { |self, ch, cc, val| callsSame.add([ch, cc, val]) } );
stubDiff = ( control: { |self, ch, cc, val| callsDiff.add([ch, cc, val]) } );
same = MSScore(voices: ["c4_4 d4", "c3_4 e3"], backends: [\midi, \midi], midiOut: stubSame, channels: [7, 7]);
same.pr_allNotesOff;
diff = MSScore(voices: ["c4_4 d4", "c3_4 e3"], backends: [\midi, \midi], midiOut: stubDiff, channels: [3, 9]);
diff.pr_allNotesOff;
("SAME_COUNT:" ++ callsSame.size.asString).postln;
("DIFF_COUNT:" ++ callsDiff.size.asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_all_notes_off_dedupe():
    r = _run(ALLNOTESOFF_DEDUPE_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "SAME_COUNT:1" in r.stdout, r.stdout[-1500:]   # same device+channel -> one send
    assert "DIFF_COUNT:2" in r.stdout, r.stdout[-1500:]   # same device, two channels -> two sends


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


BAD_BACKEND_SCRIPT = r'''(
var e = "none";
try { MSScore(voices: ["c4_4"], backends: [\bogus]) } { |err| e = err.errorString };
("BAD_BACKEND:" ++ e).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_validation_bad_backend():
    r = _run(BAD_BACKEND_SCRIPT)
    assert "backends[0] must be" in r.stdout, r.stdout[-1500:]
    assert "got bogus" in r.stdout, r.stdout[-1500:]


MIDIOUT_NIL_SCRIPT = r'''(
var e = "none";
try { MSScore(voices: ["c4_4", "c3_4"], backends: [\internal, \midi], midiOut: [\devA, nil]) } { |err| e = err.errorString };
("MIDIOUT_NIL:" ++ e).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_validation_midiout_array_nil():
    r = _run(MIDIOUT_NIL_SCRIPT)
    assert "midiOut[1] is nil" in r.stdout, r.stdout[-1500:]


CLAMP_SCRIPT = r'''(
var s = MSScore(voices: ["c4_4"], backends: [\midi], midiOut: \dev, channels: [99]);
("CLAMP:" ++ s.channels.asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_channel_clamp():
    r = _run(CLAMP_SCRIPT)
    assert "CLAMP:[15]" in r.stdout, r.stdout[-1500:]


# --- showCursor: hide the cursor line while keeping auto page-turn ---
# show() sends the notation setup over OSC to the `engine` NetAddr. Point that at sclang's own OSC
# port (NetAddr.langPort) so we can OSCdef-capture the cursor-visibility message `show` emits. No
# server or MusicScene instance needed.
SHOWCURSOR_HIDDEN_SCRIPT = r'''(
var s, got = List.new;
OSCdef(\capH, { |msg| got.add(msg) }, '/ms/scene/scoreHidden/cursor');
Routine({
    s = MSScore(voices: ["c5_4 e5 g5 c6"], id: "scoreHidden", showCursor: false, host: "127.0.0.1", listenPort: NetAddr.langPort);
    s.show;
    0.8.wait;
    got.do({ |m| if (m[1] == \show) { ("CURSOR_SHOW:" ++ m[2].asString).postln } });
    ("FLAG:" ++ s.showCursor.asString).postln;
    OSCdef(\capH).free;
    0.exit;
}).play;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_show_cursor_hidden():
    r = _run(SHOWCURSOR_HIDDEN_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "CURSOR_SHOW:0" in r.stdout, r.stdout[-1500:]   # show() hides the cursor line
    assert "FLAG:false" in r.stdout, r.stdout[-1500:]


SHOWCURSOR_DEFAULT_SCRIPT = r'''(
var s, got = List.new;
OSCdef(\capD, { |msg| got.add(msg) }, '/ms/scene/scoreDefault/cursor');
Routine({
    s = MSScore(voices: ["c5_4 e5 g5 c6"], id: "scoreDefault", host: "127.0.0.1", listenPort: NetAddr.langPort);
    s.show;
    0.8.wait;
    got.do({ |m| if (m[1] == \show) { ("CURSOR_SHOW:" ++ m[2].asString).postln } });
    ("FLAG:" ++ s.showCursor.asString).postln;
    OSCdef(\capD).free;
    0.exit;
}).play;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_show_cursor_default():
    r = _run(SHOWCURSOR_DEFAULT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "CURSOR_SHOW:1" in r.stdout, r.stdout[-1500:]   # default: cursor shown
    assert "FLAG:true" in r.stdout, r.stdout[-1500:]
