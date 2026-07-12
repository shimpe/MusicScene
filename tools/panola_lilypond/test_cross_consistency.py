"""Cross-consistency: PanolaMEI and PanolaLilypond must encode the SAME structure for the same
Panola input (measure count, tuplet ratios, tie presence). Locks the duplicated LilyPond walk to
the MEI transform. Run:
  py -m pytest tools/panola_lilypond/test_cross_consistency.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

CHG = r'[( measure: 1, meter: "4/4", key: \Cmajor )], [\treble]'
CORPUS_PLAIN = [
    'Panola("c5_4 e5 g5 c6")',
    'Panola("c5_2 c5_1 c5_4")',
    'Panola("<c4_4 e4 g4> d4_4 r_4 e4_4")',
    'Panola("c5_4 d5 e5 f5 g5 a5 b5 c6")',
]
CORPUS_TUPLET = [
    'Panola("c5_8*2/3 d5 e5 c5_2 r_4")',
    'Panola("c5_8*2/3 d5 c5_4 d5 e5 f5")',            # incomplete -> music21 completion
    'Panola("c5_4 c5_4 c5_4 c5_2*2/3 d5 e5")',        # complete tuplet crossing the bar 1/2 line in 4/4
]


def _gen(exprs):
    """exprs: {name: sclang expr}. Runs sclang once, returns {name: written file text}."""
    d = tempfile.mkdtemp(prefix="xc_")
    lines = ['File.mkdir("%s");' % (d.replace("\\", "/") + "/")]
    for name, expr in exprs.items():
        lines.append('File.use("%s/%s","w",{|f| f.write(%s) });' % (d.replace("\\", "/"), name, expr))
    lines.append('"DONE".postln; 0.exit;')
    sp = os.path.join(d, "s.scd"); open(sp, "w", encoding="utf-8").write("(\n" + "\n".join(lines) + "\n)\n")
    try:
        r = subprocess.run([SCLANG, sp], capture_output=True, text=True, timeout=180)
        assert "ERROR" not in r.stdout and "parse panola" not in r.stdout, r.stdout[-1500:]
        return {name: open(os.path.join(d, name), encoding="utf-8").read() for name in exprs}
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_structure_agreement():
    exprs = {}
    for i, v in enumerate(CORPUS_PLAIN):
        exprs["mei%d" % i] = "Panola.scoreAsMEI([%s], %s)" % (v, CHG)
        exprs["ly%d" % i] = "PanolaLilypond.scoreAsLilypond([%s], %s)" % (v, CHG)
    files = _gen(exprs)
    for i in range(len(CORPUS_PLAIN)):
        mei, ly = files["mei%d" % i], files["ly%d" % i]
        # exact measure count: one s1* spine skip per measure vs one <measure in MEI
        assert ly.count("s1*") == mei.count("<measure "), (i, "measures", ly.count("s1*"), mei.count("<measure "))
        # tie presence must agree
        assert ("tie=" in mei) == ("~" in ly), (i, "tie agreement")


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplet_structure_agreement():
    exprs = {}
    for i, v in enumerate(CORPUS_TUPLET):
        exprs["mei%d" % i] = "Panola.scoreAsMEI([%s], %s)" % (v, CHG)
        exprs["ly%d" % i] = "PanolaLilypond.scoreAsLilypond([%s], %s)" % (v, CHG)
    files = _gen(exprs)
    for i in range(len(CORPUS_TUPLET)):
        mei, ly = files["mei%d" % i], files["ly%d" % i]
        for num, numbase in re.findall(r'<tuplet num="(\d+)" numbase="(\d+)"', mei):
            assert ("\\tuplet %s/%s" % (num, numbase)) in ly, (i, num, numbase)
