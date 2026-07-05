"""Slur tests for Panola.scoreAsMEI (PanolaMEI). sclang -> MEI -> Verovio render + assert.
Run:  py -m pytest tools/panola_mei/test_slurs.py -q   (skips if sclang absent)
"""
import os, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

MINIMAL = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<note dur="4" oct="5" pname="c"/><note dur="4" oct="5" pname="d"/>'
  '<note dur="4" oct="5" pname="e"/><note dur="4" oct="5" pname="f"/></layer></staff>'
  '<slur tstamp="1" tstamp2="0m+4" staff="1"/></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_slur():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["slurs"] == 1


from tools.panola_mei.test_expression import _dump, SCLANG

CASES = {
  "within":    r'Panola.scoreAsMEI([Panola("c5_4@slur^start^ d5 e5 f5@slur^end^ g5")], "4/4", \Cmajor, [\treble], nil)',
  "crossbar":  r'Panola.scoreAsMEI([Panola("c5_4@slur^start^ d5 e5 f5 g5@slur^end^ a5 b5 c6")], "4/4", \Cmajor, [\treble], nil)',
  "chained":   r'Panola.scoreAsMEI([Panola("c5_4@slur^start^ d5 e5@slur^endstart^ f5 g5@slur^end^ a5")], "4/4", \Cmajor, [\treble], nil)',
  "unmatched": r'Panola.scoreAsMEI([Panola("c5_4 d5@slur^end^ e5 f5")], "4/4", \Cmajor, [\treble], nil)',
  "twovoice":  r'Panola.scoreAsMEI([Panola("c5_4 d5 e5 f5"), Panola("c3_4@slur^start^ e3 g3 c4@slur^end^")], "4/4", \Cmajor, [\treble, \bass], nil)',
  # slur that both starts and ends inside the same triplet -> endpoints must get distinct sub-tuplet
  # tstamps, else it collapses to a zero-length (invisible) slur
  "intuplet":  r'Panola.scoreAsMEI([Panola("a5_8*2/3@slur^start^ c6 a5@slur^end^ c6_4 d6_4 e6_4")], "4/4", \Cmajor, [\treble], nil)',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_slurs():
    outdir = tempfile.mkdtemp(prefix="panola_slur_")
    try:
        _dump(outdir, CASES)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in CASES}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert props["within"]["slurs"] == 1
    assert '<slur tstamp="1" tstamp2="0m+4" staff="1"/>' in meis["within"]
    assert props["crossbar"]["slurs"] == 1
    assert '<slur tstamp="1" tstamp2="1m+1" staff="1"/>' in meis["crossbar"]
    assert props["chained"]["slurs"] == 2
    assert '<slur tstamp="1" tstamp2="0m+3" staff="1"/>' in meis["chained"]
    assert '<slur tstamp="3" tstamp2="1m+1" staff="1"/>' in meis["chained"]
    assert props["unmatched"]["slurs"] == 0
    assert props["twovoice"]["slurs"] == 1 and 'staff="2"' in meis["twovoice"]
    # within-tuplet slur: one slur, distinct endpoints (not the degenerate 0m+1), renders as an arc
    assert props["intuplet"]["slurs"] == 1
    assert '<slur tstamp="1" tstamp2="0m+1" staff="1"/>' not in meis["intuplet"]
    assert props["intuplet"]["slur_arcs"] == 1
