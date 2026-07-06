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
