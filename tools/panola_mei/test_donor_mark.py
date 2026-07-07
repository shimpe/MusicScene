"""A @dyn/@slur on the note that COMPLETES an incomplete tuplet (the donor) must attach at the donor's
onset (the completing member inside the bracket), not at the tied remainder ~1/3 beat later.
Run:  py -m pytest tools/panola_mei/test_donor_mark.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(panola):
    d = tempfile.mkdtemp(prefix="panola_dm_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        expr = 'Panola.scoreAsMEI([Panola("%s")], "4/4", \\Cmajor, [\\treble], nil)' % panola
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dyn_on_completing_donor_attaches_at_its_onset():
    # incomplete triplet [c,d] (2/3 beat); e5_4 (the donor) carries @dyn^ff^. The ff belongs at the donor
    # onset (2/3 -> tstamp 5/3 ~= 1.6667), NOT at the tied remainder (onset 1.0 -> tstamp 2).
    mei = _mei("c5_8*2/3 d5 e5_4@dyn^ff^")
    assert '<dynam tstamp="1.6667" staff="1">ff</dynam>' in mei, mei
    assert 'tstamp="2" staff="1">ff' not in mei, mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_slur_on_completing_donor_starts_at_its_onset():
    # the slur opens on the donor note e5_4 -> tstamp 1.6667 (donor onset), not 2.
    mei = _mei("c5_8*2/3 d5 e5_4@slur^start^ f5_4 g5_4@slur^end^")
    assert '<slur tstamp="1.6667"' in mei, mei
    assert '<slur tstamp="2"' not in mei, mei
