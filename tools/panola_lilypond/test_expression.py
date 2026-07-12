import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dynamics_and_articulation():
    ly = gen(r'Panola.scoreAsLilypond([Panola("c5_4@dyn^p^ e5 g5@art^staccato^ c6@dyn^f^")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble])')
    assert "\\p" in ly and "\\f" in ly and "-." in ly
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_slurs_and_hairpins():
    ly = gen(r'Panola.scoreAsLilypond([Panola("c5_4@slur^start^@hairpin^cresc^ e5 g5@slur^endstart^ c6@slur^end^@hairpin^end^")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble])')
    assert "(" in ly and ")" in ly and ")(" in ly
    assert "\\<" in ly and "\\!" in ly
    assert compiles(ly)
