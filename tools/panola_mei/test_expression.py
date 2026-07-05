"""Per-note expression (dynamics + articulation) tests for Panola.scoreAsMEI (PanolaMEI).
Runs sclang to generate MEI, renders via Verovio, and asserts expression structure.
Run:  py -m pytest tools/panola_mei/test_expression.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

MINIMAL = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<note dur="4" oct="5" pname="c" artic="stacc"/><note dur="4" oct="5" pname="d"/>'
  '<note dur="2" oct="5" pname="e"/></layer></staff>'
  '<dynam tstamp="1" staff="1">mf</dynam></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_dynam_and_artic():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["dynam"] == 1
    assert p["artics"] == 1


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


ART = {
  "oneshot":  r'Panola.scoreAsMEI([Panola("c5_4@art^staccato^ d5 e5 c5_4")], "4/4", \Cmajor, [\treble], nil)',
  "passage":  r'Panola.scoreAsMEI([Panola("c5_4@art[stacc:on] d5 e5 f5 g5@art[stacc:off] a5 b5 c6")], "4/4", \Cmajor, [\treble], nil)',
  "layered":  r'Panola.scoreAsMEI([Panola("c5_4@art[acc:on] d5@art[stacc:on] e5@art[acc:off] f5")], "4/4", \Cmajor, [\treble], nil)',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_articulation():
    outdir = tempfile.mkdtemp(prefix="panola_expr_")
    try:
        _dump(outdir, ART)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in ART}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert meis["oneshot"].count(' artic="stacc"') == 1
    assert meis["passage"].count(' artic="stacc"') == 4
    assert 'artic="acc"' in meis["layered"] and 'artic="acc stacc"' in meis["layered"] and 'artic="stacc"' in meis["layered"]


DYN = {
  "oneshot": r'Panola.scoreAsMEI([Panola("c5_4@dyn^p^ d5 e5@dyn^f^ g5")], "4/4", \Cmajor, [\treble], nil)',
  "norepeat": r'Panola.scoreAsMEI([Panola("c5_4@dyn^mf^ d5 e5 g5")], "4/4", \Cmajor, [\treble], nil)',
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dynamics():
    outdir = tempfile.mkdtemp(prefix="panola_expr_")
    try:
        _dump(outdir, DYN)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in DYN}
        props = {k: render_props(v) for k, v in meis.items()}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    for k, p in props.items():
        assert p["ok"], f"{k}: {p['stderr'][:200]}"
    assert props["oneshot"]["dynam"] == 2
    assert '<dynam tstamp="1" staff="1">p</dynam>' in meis["oneshot"]
    assert '<dynam tstamp="3" staff="1">f</dynam>' in meis["oneshot"]
    assert props["norepeat"]["dynam"] == 1


# Regression guard: a voice carrying @dyn/@art must still build a playable asPbind. Two past bugs:
#  (1) numeric property defaults ("0.5") slipped through as strings -> "Message '*' not understood"
#      (a Character times a Float) at play time;
#  (2) string properties were passed into the Pbind as symbols -> notes without an articulation got
#      the empty symbol '' and SuperCollider dropped them as rests (melody started late).
# Fix: numeric text is coerced to Float, and string-valued (notation-only) properties are left out of
# the Pbind. So every drawn event must have a numeric amp and NO \art / \dyn key.
ASPBIND_SCRIPT = r'''(
var st, ev, ok = true, hasArt = false, hasDyn = false;
st = Panola("c5_4@dyn^mf^ e5 g5 e5_8*2/3@art[stacc:on] f5 g5").asPbind(\default, include_tempo:false).asStream;
6.do({ ev = st.next(());
    if (ev.at(\amp).isNumber.not) { ok = false };
    if (ev.includesKey(\art)) { hasArt = true };
    if (ev.includesKey(\dyn)) { hasDyn = true };
});
(ok and: { hasArt.not } and: { hasDyn.not }).if({ "ASPBIND-OK".postln }, { ("ASPBIND-BAD amp-ok=" ++ ok ++ " art=" ++ hasArt ++ " dyn=" ++ hasDyn).postln });
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_aspbind_materializes_with_expression():
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(ASPBIND_SCRIPT)
        path = f.name
    try:
        r = subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    assert "ASPBIND-OK" in r.stdout, r.stdout[-1500:]
    assert "not understood" not in r.stdout, r.stdout[-1500:]
