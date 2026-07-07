"""SP2d: an explicit *m/d tuplet crossing a barline splits into tied per-measure <tuplet> brackets.
Generates MEI via sclang, asserts on the MEI XML, renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_barline_tuplets.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_bxt_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read(), r.stdout
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_septuplet_across_a_barline_splits_into_two_brackets():
    # 7:4 septuplet of 16ths starting on the "and" of beat 4 (3.5) spans 3.5-4.5, crossing the barline.
    # The straddling member is cut exactly in half -> two tied 32nd[7:4]; two <tuplet 7:4> brackets.
    mei, out = _mei('Panola.scoreAsMEI([Panola("c5_4 d5 e5 f5_8 g5_16*4/7 a5 b5 c6 d6 e6 f6")], '
                    '"4/4", \\Cmajor, [\\treble], nil)')
    assert "crosses a barline" not in out, out[-1500:]              # no warning: it split cleanly
    assert mei.count('<tuplet num="7" numbase="4">') == 2, mei      # one bracket per bar
    assert mei.count("<measure ") == 2, mei
    assert mei.count('<note dur="32"') == 2, mei                    # the straddling 16th -> two 32nds
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei              # tied across the barline
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_quarter_triplet_across_a_barline():
    # a 3:2 quarter-triplet starting at beat 3 spans 3-5, crossing the barline; the middle member
    # straddles and splits into two tied triplet-eighths -> two <tuplet 3:2> brackets.
    mei, out = _mei('Panola.scoreAsMEI([Panola("c5_2 d5_4 e5_4*2/3 f5 g5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert "crosses a barline" not in out, out[-1500:]
    assert mei.count('<tuplet num="3" numbase="2">') == 2, mei
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_noncrossing_tuplets_unchanged():
    # a complete in-bar triplet is byte-identical (atomic path); a 7:4 septuplet in beat 1 is one bracket.
    trip, _ = _mei('Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert trip.count("<tuplet ") == 1 and trip.count('<note dur="4"') == 3, trip
    sept, _ = _mei('Panola.scoreAsMEI([Panola("c5_16*4/7 d5 e5 f5 g5 a5 b5 c6_2 r_4")], "4/4", \\Cmajor, [\\treble], nil)')
    assert sept.count('<tuplet num="7" numbase="4">') == 1, sept
