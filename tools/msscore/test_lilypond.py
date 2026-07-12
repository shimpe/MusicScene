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

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lilypond_paginate_int():
    """LilyPond no longer forces pagination off: pr_paginateInt reflects the paginate flag for \\lilypond."""
    r = _run(r'''(
var on  = MSScore(voices: ["c5_4 e5"], clefs: [\treble], notation: \lilypond, paginate: true);
var off = MSScore(voices: ["c5_4 e5"], clefs: [\treble], notation: \lilypond, paginate: false);
("ON="  ++ on.pr_paginateInt.asString).postln;
("OFF=" ++ off.pr_paginateInt.asString).postln;
0.exit;
)''')
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "ON=1" in r.stdout, r.stdout[-1500:]
    assert "OFF=0" in r.stdout, r.stdout[-1500:]
