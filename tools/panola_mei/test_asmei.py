"""End-to-end test for Panola.asMEI / Panola.scoreAsMEI (the Panola-quark MEI export).

Runs sclang headlessly to generate MEI from real Panola strings, then renders each MEI through
the bundled Verovio wrapper and asserts structural properties. Requires:
  * SuperCollider sclang  (env SCLANG, or the default path below)
  * the Panola quark installed (with PanolaMEI.sc + Panola:asMEI)
  * `pip install verovio` for the `py` interpreter

Run:  py -m pytest tools/panola_mei/test_asmei.py -q      (skips cleanly if sclang is absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

# name -> Panola scoreAsMEI call. Each generated file is rendered and checked below.
CASES = {
    "single":  'Panola("c5_4 e g a").asMEI("4/4", \\Cmajor, \\treble)',
    "grand":   'Panola.scoreAsMEI([Panola("c5_4 e g a"), Panola("c3_2 g2")], "4/4", \\Cmajor, [\\treble,\\bass], [[1,2]])',
    "chords":  'Panola.scoreAsMEI([Panola("<c4_4 e4 g4> <d4_4 f4 a4> <e4_2 g4 c5>")], "4/4", \\Cmajor, [\\treble], nil)',
    "rests":   'Panola.scoreAsMEI([Panola("c5_4 r_4 e5_4 r_4")], "4/4", \\Cmajor, [\\treble], nil)',
    "ties":    'Panola.scoreAsMEI([Panola("c5_2 c5_1 c5_4")], "4/4", \\Cmajor, [\\treble], nil)',
    "gmajor":  'Panola.scoreAsMEI([Panola("f#5_4 g a b")], "4/4", \\Gmajor, [\\treble], nil)',
    "waltz":   'Panola.scoreAsMEI([Panola("c5_4 e g c5_4 e g")], "3/4", \\Cmajor, [\\treble], nil)',
    "beams":   'Panola.scoreAsMEI([Panola("c5_8 d5 e5 f5 g5 a5 b5 c6")], "4/4", \\Cmajor, [\\treble], nil)',
}


def _dump_mei(outdir):
    """Run sclang to write <outdir>/<name>.mei for every case; return True on success."""
    dir_sc = outdir.replace("\\", "/") + "/"
    lines = ['File.mkdir("%s");' % dir_sc]
    for name, expr in CASES.items():
        lines.append('File.use("%s%s.mei", "w", { |f| f.write(%s) });' % (dir_sc, name, expr))
    lines.append('"DONE".postln; 0.exit;')
    scd = "(\n" + "\n".join(lines) + "\n)\n"
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(scd); scd_path = f.name
    try:
        r = subprocess.run([SCLANG, scd_path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(scd_path)
    if "ERROR" in r.stdout or "parse panola" in r.stdout:
        raise AssertionError("sclang reported an error:\n" + r.stdout[-1500:])
    return all(os.path.exists(os.path.join(outdir, n + ".mei")) for n in CASES)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed (set $SCLANG)")
def test_panola_asmei_renders_all_cases():
    outdir = tempfile.mkdtemp(prefix="panola_mei_")
    try:
        assert _dump_mei(outdir), "sclang did not produce all MEI files"
        props = {n: render_props(os.path.join(outdir, n + ".mei")) for n in CASES}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)

    for n, p in props.items():
        assert p["ok"], f"{n} failed to render: rc={p['rc']} {p['stderr'][:200]}"

    assert props["grand"]["treble"] >= 1 and props["grand"]["bass"] >= 1     # grand staff
    assert props["ties"]["ties"] and props["ties"]["measures"] == 2          # whole note split+tied across barline
    assert props["gmajor"]["sharps"] >= 1                                    # key signature drawn
    assert props["waltz"]["measures"] == 2                                   # 6 quarters in 3/4 = 2 bars
    assert props["beams"]["beams"] == 4 and props["beams"]["flag_glyphs"] == 0  # 8 eighths auto-beamed per beat


def test_written_values_correct_for_all_plain_durations():
    """After the parseDur rewrite, written value + dots must be correct for plain notes."""
    import re
    if not os.path.exists(SCLANG):
        pytest.skip("sclang not installed")
    outdir = tempfile.mkdtemp(prefix="panola_dur_")
    scd = ('( File.use("%s/d.mei","w",{|f| f.write('
           'Panola("c5_1 c5_2 c5_4 c5_8 c5_16 c5_4.").asMEI("16/4", \\Cmajor, \\treble)) });'
           ' "DONE".postln; 0.exit; )' % outdir.replace("\\", "/"))
    p = os.path.join(outdir, "s.scd")
    open(p, "w").write(scd)
    subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
    mei = open(os.path.join(outdir, "d.mei"), encoding="utf-8").read()
    shutil.rmtree(outdir, ignore_errors=True)
    durs = re.findall(r'<note dur="(\d+)"( dots="(\d+)")?', mei)
    got = [(d, (dots or "0")) for d, _, dots in durs]
    assert got == [("1", "0"), ("2", "0"), ("4", "0"), ("8", "0"), ("16", "0"), ("4", "1")]
