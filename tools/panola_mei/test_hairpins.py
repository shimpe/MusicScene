"""Hairpin tests for Panola.scoreAsMEI (PanolaMEI). sclang -> MEI -> Verovio render + assert.
Run:  py -m pytest tools/panola_mei/test_hairpins.py -q   (skips if sclang absent)
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
  '<hairpin form="cres" tstamp="1" tstamp2="0m+4" staff="1"/></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_hairpin():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["hairpins"] == 1


from tools.panola_mei.test_expression import _dump, SCLANG

CASES = {
  "within":    r'Panola.scoreAsMEI([Panola("c5_4@hairpin^cresc^ d5 e5 f5@hairpin^end^ g5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "dim":       r'Panola.scoreAsMEI([Panola("c5_4@hairpin^decrescendo^ d5 e5 f5@hairpin^end^ g5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "crossbar":  r'Panola.scoreAsMEI([Panola("c5_4@hairpin^cresc^ d5 e5 f5 g5@hairpin^end^ a5 b5 c6")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "messa":     r'Panola.scoreAsMEI([Panola("c5_4@hairpin^cresc^ d5 e5@hairpin^enddim^ f5 g5@hairpin^end^ a5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "coexist":   r'Panola.scoreAsMEI([Panola("c5_4@dyn^p^@slur^start^@hairpin^cresc^ d5 e5 f5@slur^end^@hairpin^end^ g5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "unmatched": r'Panola.scoreAsMEI([Panola("c5_4 d5@hairpin^end^ e5 f5")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble], nil)',
  "twovoice":  r'Panola.scoreAsMEI([Panola("c5_4 d5 e5 f5"), Panola("c3_4@hairpin^cresc^ e3 g3 c4@hairpin^end^")], [( measure: 1, meter: "4/4", key: \Cmajor )], [\treble, \bass], nil)',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_hairpins():
    outdir = tempfile.mkdtemp(prefix="panola_hairpin_")
    try:
        _dump(outdir, CASES)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in CASES}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert props["within"]["hairpins"] == 1
    assert '<hairpin form="cres" tstamp="1" tstamp2="0m+4" staff="1"/>' in meis["within"]
    assert '<hairpin form="dim" tstamp="1" tstamp2="0m+4" staff="1"/>' in meis["dim"]
    assert props["crossbar"]["hairpins"] == 1
    assert '<hairpin form="cres" tstamp="1" tstamp2="1m+1" staff="1"/>' in meis["crossbar"]
    assert props["messa"]["hairpins"] == 2
    assert '<hairpin form="cres" tstamp="1" tstamp2="0m+3" staff="1"/>' in meis["messa"]
    assert '<hairpin form="dim" tstamp="3" tstamp2="1m+1" staff="1"/>' in meis["messa"]
    assert props["coexist"]["hairpins"] == 1 and props["coexist"]["slurs"] == 1 and props["coexist"]["dynam"] >= 1
    assert props["unmatched"]["hairpins"] == 0
    assert props["twovoice"]["hairpins"] == 1 and 'form="cres"' in meis["twovoice"] and 'staff="2"' in meis["twovoice"]
