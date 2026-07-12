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

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_breaks():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_1 d5_1 e5_1 f5_1")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil, [3], [2])')
    assert "\\break" in ly       # systemBreaks: [2]
    assert "\\pageBreak" in ly   # pageBreaks: [3]
    assert compiles(ly)
