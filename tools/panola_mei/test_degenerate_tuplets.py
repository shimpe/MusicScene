"""A degenerate *m/d ratio (num==1 or numbase==1 after gcd) is NOT a tuplet: it renders as a plain
note that splits-and-ties over barlines, never as a meaningless <tuplet num="1"> "1-tuplet" bracket.
Genuine tuplets (both sides > 1, e.g. duplet 2:3) are unaffected and stay bracketed.
Generates MEI via sclang, asserts on the MEI XML, renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_degenerate_tuplets.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_deg_")
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
def test_half_times_three_ties_whole_to_half_over_the_barline():
    # c5_2*3 : a half note with mult=3/div=1 -> 6 beats (a degenerate 1:3 ratio, NOT a tuplet). In 4/4 from
    # the downbeat this is a whole note (bar 1) tied to a half note (bar 2), never a <tuplet num="1"> bracket.
    mei, out = _mei('Panola.scoreAsMEI([Panola("c5_2*3 r_2")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert '<tuplet num="1"' not in mei, mei                        # no degenerate 1-tuplet bracket
    assert "1-tuplet" not in out, out[-1500:]
    assert "crosses a barline" not in out, out[-1500:]              # not treated as a tuplet at all
    assert "incomplete tuplet" not in out, out[-1500:]
    assert mei.count("<tuplet ") == 0, mei                          # a plain tied note, no tuplet
    assert mei.count("<measure ") == 2, mei
    assert re.search(r'<note dur="1"[^>]*tie="i"', mei), mei        # whole note, tied out
    assert re.search(r'<note dur="2"[^>]*tie="t"', mei), mei        # tied to a half note over the barline
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_whole_times_two_ties_whole_to_whole_over_the_barline():
    # c3_1*2 : a whole note with mult=2/div=1 -> 8 beats (a degenerate 1:2 ratio). In 4/4 it is a whole note
    # (bar 1) tied to a whole note (bar 2), exactly like a plain long note split at the barline.
    mei, out = _mei('Panola.scoreAsMEI([Panola("c3_1*2")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert '<tuplet num="1"' not in mei, mei
    assert "1-tuplet" not in out, out[-1500:]
    assert "crosses a barline" not in out, out[-1500:]
    assert "incomplete tuplet" not in out, out[-1500:]
    assert mei.count("<tuplet ") == 0, mei
    assert mei.count("<measure ") == 2, mei
    assert re.search(r'<note dur="1"[^>]*tie="i"', mei), mei        # whole note, tied out
    assert re.search(r'<note dur="1"[^>]*tie="t"', mei), mei        # tied to a whole note over the barline
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_genuine_duplet_stays_bracketed():
    # c5_4*3/2 : a 2:3 duplet (num=2, numbase=3) is a GENUINE tuplet (both sides > 1, not degenerate). It
    # must STILL emit a <tuplet num="2" numbase="3"> bracket and NOT be routed to the plain-note path.
    mei, out = _mei('Panola.scoreAsMEI([Panola("c5_4*3/2")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert '<tuplet num="2" numbase="3">' in mei, mei              # genuine duplet stays a tuplet
    assert '<tuplet num="1"' not in mei, mei
