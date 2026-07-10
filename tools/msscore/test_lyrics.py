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
// staff 2 (nil) must carry no lyrics: the content after <staff n="2"> has no <syl>
// (single measure here, so everything past the staff-2 marker belongs to staff 2)
(m.copyRange(m.find("<staff n=\"2\">"), m.size - 1).contains("<syl")).if({ "STAFF2-BAD".postln }, { "STAFF2-CLEAN".postln });
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
    assert "STAFF2-CLEAN" in r.stdout, r.stdout[-1500:]   # the nil staff carries no <syl>


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_msscore_nil_lyrics_byte_identical():
    r = _run(NIL_SCRIPT)
    assert "SAME" in r.stdout, r.stdout[-1500:]
    assert "NOVERSE" in r.stdout, r.stdout[-1500:]
