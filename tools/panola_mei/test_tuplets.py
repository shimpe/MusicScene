"""Tuplet rendering tests for Panola.scoreAsMEI (PanolaMEI in the Panola quark).
Runs sclang to generate MEI, renders via Verovio, and asserts tuplet structure.
Run:  py -m pytest tools/panola_mei/test_tuplets.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

MINIMAL_TUPLET = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<tuplet num="3" numbase="2"><note dur="8" oct="5" pname="c"/><note dur="8" oct="5" pname="d"/>'
  '<note dur="8" oct="5" pname="e"/></tuplet>'
  '<rest dur="2"/></layer></staff></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_tuplets():
    p = render_props(MINIMAL_TUPLET)
    assert p["ok"] is True
    assert p["tuplets"] == 1


CASES = {   # name -> Panola.scoreAsMEI expression
    "triplet":    'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 e5 c5_2 r_4")], "4/4", \\Cmajor, [\\treble], nil)',
    "sixeighths": 'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 e5 f5 g5 a5")], "4/4", \\Cmajor, [\\treble], nil)',
    "mixed":      'Panola.scoreAsMEI([Panola("c5_4*2/3 d5_8*2/3 c5_2")], "4/4", \\Cmajor, [\\treble], nil)',
    "quintuplet": 'Panola.scoreAsMEI([Panola("c5_16*4/5 d5 e5 f5 g5")], "4/4", \\Cmajor, [\\treble], nil)',
    "quarter3":   'Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)',
    "then_plain": 'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 e5 c5_4 d5_4 e5_2")], "4/4", \\Cmajor, [\\treble], nil)',
    "with_rest":  'Panola.scoreAsMEI([Panola("c5_8*2/3 r d5 c5_2 r_4")], "4/4", \\Cmajor, [\\treble], nil)',
    "incomplete": 'Panola.scoreAsMEI([Panola("c5_8*2/3 d5 c5_4 d5 e5 f5")], "4/4", \\Cmajor, [\\treble], nil)',
}


def _dump(outdir, cases):
    dir_sc = outdir.replace("\\", "/") + "/"
    lines = ['File.mkdir("%s");' % dir_sc]
    for n, expr in cases.items():
        lines.append('File.use("%s%s.mei","w",{|f| f.write(%s) });' % (dir_sc, n, expr))
    lines.append('"DONE".postln; 0.exit;')
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write("(\n" + "\n".join(lines) + "\n)\n")
        path = f.name
    try:
        r = subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    assert "ERROR" not in r.stdout and "parse panola" not in r.stdout, r.stdout[-1500:]


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_eighth_triplet():
    outdir = tempfile.mkdtemp(prefix="panola_tup_")
    try:
        _dump(outdir, {"triplet": CASES["triplet"]})
        mei = open(os.path.join(outdir, "triplet.mei"), encoding="utf-8").read()
        p = render_props(mei)
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    assert p["ok"], p["stderr"][:200]
    assert p["tuplets"] == 1
    assert '<tuplet num="3" numbase="2">' in mei
    assert mei.count('<note dur="8"') == 3          # three written eighths inside the tuplet


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_duration_based_grouping():
    outdir = tempfile.mkdtemp(prefix="panola_tup_")
    keys = ["sixeighths", "mixed", "quintuplet", "quarter3"]
    try:
        _dump(outdir, {k: CASES[k] for k in keys})
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in keys}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert props["sixeighths"]["tuplets"] == 2                                  # two triplets, not one 6-tuplet
    assert meis["mixed"].count("<tuplet") == 1                                   # quarter+eighth = one triplet
    assert meis["mixed"].count('<note dur="4"') >= 1 and meis["mixed"].count('<note dur="8"') >= 1
    assert '<tuplet num="5" numbase="4">' in meis["quintuplet"]
    assert '<tuplet num="3" numbase="2">' in meis["quarter3"] and meis["quarter3"].count('<note dur="4"') == 3


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplet_edge_cases():
    outdir = tempfile.mkdtemp(prefix="panola_tup_")
    keys = ["then_plain", "with_rest", "incomplete"]
    try:
        _dump(outdir, {k: CASES[k] for k in keys})
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in keys}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    # a plain quarter after the triplet is NOT inside a tuplet
    assert meis["then_plain"].count("<tuplet") == 1
    assert '</tuplet><note dur="4"' in meis["then_plain"]
    # a rest can be a tuplet member
    assert "<tuplet" in meis["with_rest"] and "<rest" in meis["with_rest"].split("</tuplet>")[0]
    # the once-incomplete run now completes music21-style into a tied tuplet cascade (the quarter donor's
    # leading third joins the bracket, tied); still renders and still has at least one tuplet
    assert props["incomplete"]["tuplets"] >= 1
