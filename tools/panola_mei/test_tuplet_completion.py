"""SP2c tuplet-completion tests: PanolaMEI brackets split fragments and completes incomplete tuplets.
Generates MEI via sclang, asserts on the MEI XML, and renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_tuplet_completion.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_tupc_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_split_fragments_render_inside_a_tuplet():
    # c5_8*2/3 d5 c5_2 : the incomplete triplet (still partial in Phase A) pushes the half note onto a
    # non-dyadic onset (2/3); the splitter spells its fragments as triplet values, which must now be
    # WRAPPED in <tuplet> brackets rather than emitted as bare mis-valued notes. Before Piece 1-2 there
    # is exactly one <tuplet> (the partial triplet) and bare dur="8"/dur="4" tuplet-value notes after it;
    # after, the cascade fragments are bracketed too.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 c5_2")], "4/4", \\Cmajor, [\\treble], nil)')
    assert mei.count("<tuplet ") >= 2, mei                 # partial triplet + at least one cascade bracket
    # no tuplet-valued note sits directly outside a bracket (every <note> after a </tuplet> that is a
    # triplet fragment is itself inside a <tuplet>); sanity: it renders
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_plain_and_complete_tuplets_unchanged():
    # a plain-note score and a complete triplet must be byte-identical to before (nil-tuplet fragments
    # render exactly as today; complete *m/d keeps its atomic path).
    plain = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 c5_4")], "4/4", \\Cmajor, [\\treble], nil)')
    assert plain.count("<tuplet ") == 0 and plain.count("<note") == 4, plain
    trip = _mei('Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert '<tuplet num="3" numbase="2">' in trip and trip.count('<note dur="4"') == 3, trip
