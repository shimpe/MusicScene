import os, pytest
from tools.panola_lilypond.test_core import gen, compiles, SCLANG

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_basic():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_4 d5 e5 f5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil, nil, nil, [ [ "Twin-kle lit-tle" ] ])')
    assert "\\lyricsto \"v1\"" in ly
    assert "Twin -- kle" in ly and "lit -- tle" in ly
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_nil_no_lyrics_block():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_4 d5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble])')
    assert "\\lyricsto" not in ly
    assert compiles(ly)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_melisma_and_multiverse():
    ly = gen(r'PanolaLilypond.scoreAsLilypond([Panola("c5_4 d5 e5 f5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil, nil, nil, [ [ "A _ men", "one two three four" ] ])')
    assert ly.count("\\lyricsto \"v1\"") == 2   # two verses stacked on the same voice
    assert "men" in ly and "three" in ly
    assert compiles(ly)
