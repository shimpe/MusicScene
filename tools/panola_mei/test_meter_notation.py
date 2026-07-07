"""SP2b meter-aware notation tests: PanolaMeterSplitter wired into PanolaMEI's non-tuplet path.
Generates MEI via sclang, asserts on the MEI XML (note/tie counts) and that it renders.
Run:  py -m pytest tools/panola_mei/test_meter_notation.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    """Run sclang, return the MEI string produced by `expr` (a scoreAsMEI/asMEI call)."""
    d = tempfile.mkdtemp(prefix="panola_meter_")
    try:
        path = (d.replace("\\", "/") + "/s.mei")
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd")
        open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


def _notes(mei):   # count <note ...> elements (not <notedef> etc.)
    return len(re.findall(r"<note[ />]", mei))


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_mid_measure_half_note_splits_at_the_4_4_midpoint():
    # c5_4 c5_2 c5_4 in 4/4: the middle half note starts on beat 2 and spans the 2.0 half-measure
    # boundary, so it must split into two tied quarters (quarter + quarter~) rather than one half note.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 c5_2 c5_4")], "4/4", \\Cmajor, [\\treble], nil)')
    assert _notes(mei) == 4, mei              # q + (q~q) + q  (was 3: q + half + q)
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei
    assert render_props(mei)["ok"], mei
