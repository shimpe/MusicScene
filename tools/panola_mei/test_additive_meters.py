"""SP2e: additive meter grouping ("2+2+3/8") -> group-boundary splitting, per-group beaming, additive sig.
Generates MEI via sclang, asserts on the MEI XML, renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_additive_meters.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(panola, meter):
    d = tempfile.mkdtemp(prefix="panola_add_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        expr = ('Panola.scoreAsMEI([Panola("%s")], "%s", \\Cmajor, [\\treble], nil)' % (panola, meter))
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_additive_meter_signature_and_barlength():
    # seven eighths fill exactly one 2+2+3/8 bar (3.5 quarter-beats); the signature is additive.
    mei = _mei("c5_8 d5 e5 f5 g5 a5 b5", "2+2+3/8")
    assert 'meter.count="2+2+3" meter.unit="8"' in mei, mei
    assert mei.count("<measure ") == 1, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_additive_beaming_2_2_3():
    # a bar of seven eighths beams 2 + 2 + 3 -> three <beam> groups, not a uniform grouping.
    mei = _mei("c5_8 d5 e5 f5 g5 a5 b5", "2+2+3/8")
    assert mei.count("<beam>") == 3, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_additive_splitting_at_group_boundary():
    # in 2+2+3/8, group boundaries sit at beats 1.0 and 2.0 (strength 75). A quarter starting on the
    # off-beat of group 1 (onset 0.5, weak) crosses the 1.0 boundary -> two tied eighths; a quarter that
    # starts on the group-3 boundary (onset 2.0) spans only weaker subdivisions -> stays a quarter.
    mei = _mei("c5_8 d5_4 f5_8 g5_4 a5_8", "2+2+3/8")
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei          # d5_4 split+tied at the group boundary
    # g5_4 (onset 2.0) stays a single quarter (not over-split within its group)
    assert re.search(r'<note dur="4"[^>]*pname="g"', mei), mei
    assert render_props(mei)["ok"], mei
