"""Core Panola->LilyPond tests: assert on the emitted .ly text. Where LilyPond is installed
(env LILYPOND), also compile the .ly to confirm it is valid. Run:
  py -m pytest tools/panola_lilypond/test_core.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")
LILYPOND = os.environ.get("LILYPOND", r"C:\Program Files\lilypond-2.25.81\bin\lilypond.exe")


def gen(expr):
    """Run sclang; return the String value of `expr` (written to a temp file)."""
    outdir = tempfile.mkdtemp(prefix="panola_ly_")
    p = os.path.join(outdir, "o.ly").replace("\\", "/")
    scd = '( File.use("%s","w",{|f| f.write(%s) }); "DONE".postln; 0.exit; )' % (p, expr)
    sp = os.path.join(outdir, "s.scd"); open(sp, "w", encoding="utf-8").write(scd)
    try:
        r = subprocess.run([SCLANG, sp], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout and "parse panola" not in r.stdout, r.stdout[-1500:]
        return open(p, encoding="utf-8").read()
    finally:
        shutil.rmtree(outdir, ignore_errors=True)


def compiles(ly_text):
    """True if LilyPond compiles ly_text without error (skip-friendly: True when LilyPond absent)."""
    if not os.path.exists(LILYPOND):
        return True
    d = tempfile.mkdtemp(prefix="ly_compile_")
    try:
        src = os.path.join(d, "s.ly"); open(src, "w", encoding="utf-8").write(ly_text)
        r = subprocess.run([LILYPOND, "-o", os.path.join(d, "out"), src],
                           capture_output=True, text=True, timeout=120)
        return r.returncode == 0
    finally:
        shutil.rmtree(d, ignore_errors=True)


ONE = 'PanolaLilypond.scoreAsLilypond([Panola("c5_4 e5 g5 c6")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])'
CH  = 'PanolaLilypond.scoreAsLilypond([Panola("<c4_4 e4 g4> <d4_4 f4 a4> r_4 <e4_4 g4 c5>")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble])'


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_core_notes():
    ly = gen(ONE)
    assert "\\version" in ly and "\\language \"english\"" in ly
    assert "\\clef treble" in ly
    assert "c''4" in ly and "e''4" in ly and "g''4" in ly and "c'''4" in ly
    assert compiles(ly)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_core_chords_and_rest():
    ly = gen(CH)
    assert "<c' e' g'>4" in ly and "<d' f' a'>4" in ly and "<e' g' c''>4" in ly
    assert "r4" in ly
    assert compiles(ly)
