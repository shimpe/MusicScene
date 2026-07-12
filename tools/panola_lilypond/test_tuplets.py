"""Tuplet Panola->LilyPond tests. Run: py -m pytest tools/panola_lilypond/test_tuplets.py -q"""
import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_eighth_triplet():
    ly = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_8*2/3 d5 e5 c5_2 r_4")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])')
    assert "\\tuplet 3/2" in ly
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_quintuplet_and_grouping():
    ly = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_16*4/5 d5 e5 f5 g5")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])')
    assert "\\tuplet 5/4" in ly
    assert compiles(ly)
    ly2 = gen('PanolaLilypond.scoreAsLilypond([Panola("c5_8*2/3 d5 e5 f5 g5 a5")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])')
    assert ly2.count("\\tuplet 3/2") == 2   # two triplets, not one 6-tuplet
    assert compiles(ly2)
