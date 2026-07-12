import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_panola_facade():
    a = gen(r'Panola("c5_4 e5 g5 c6").asLilypond("4/4", \Cmajor, \treble)')
    assert "\\version" in a and "c''4" in a and compiles(a)
    b = gen(r'Panola.scoreAsLilypond([Panola("c5_4 e5"), Panola("c3_2")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble, \bass])')
    assert "\\clef bass" in b and compiles(b)
