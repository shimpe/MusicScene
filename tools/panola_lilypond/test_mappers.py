"""Unit tests for PanolaLilypond's pure mapper class-methods (panola quark).
Runs sclang headlessly and asserts on postln output. Run:
  py -m pytest tools/panola_lilypond/test_mappers.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write("(\n" + script + "\n0.exit;\n)\n"); path = f.name
    try:
        return subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_pitch():
    r = _run(r'''
["PA:" ++ PanolaLilypond.pr_pitchLy("c", nil, 4),
 "PB:" ++ PanolaLilypond.pr_pitchLy("c", nil, 5),
 "PC:" ++ PanolaLilypond.pr_pitchLy("c", nil, 3),
 "PD:" ++ PanolaLilypond.pr_pitchLy("c", nil, 2),
 "PE:" ++ PanolaLilypond.pr_pitchLy("f", "s", 5),
 "PF:" ++ PanolaLilypond.pr_pitchLy("b", "f", 3),
 "PG:" ++ PanolaLilypond.pr_pitchLy("d", "x", 5),
 "PH:" ++ PanolaLilypond.pr_pitchLy("e", "ff", 4)
].do({ |x| x.postln });''')
    out = r.stdout
    assert "ERROR" not in out, out[-1500:]
    for exp in ["PA:c'", "PB:c''", "PC:c\n", "PD:c,", "PE:fs''", "PF:bf", "PG:dss''", "PH:eff'"]:
        assert exp in out, (exp, out[-1500:])


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dur_and_clef():
    r = _run(r'''
["DA:" ++ PanolaLilypond.pr_durLy("4", 0), "DB:" ++ PanolaLilypond.pr_durLy("4", 1),
 "DC:" ++ PanolaLilypond.pr_durLy("1", 0), "DD:" ++ PanolaLilypond.pr_durLy("16", 2),
 "DE:" ++ PanolaLilypond.pr_durLy("breve", 0),
 "CA:" ++ PanolaLilypond.pr_clefLy(\treble), "CB:" ++ PanolaLilypond.pr_clefLy(\bass),
 "CC:" ++ PanolaLilypond.pr_clefLy(\alto), "CD:" ++ PanolaLilypond.pr_clefLy(\tenor)
].do({ |x| x.postln });''')
    out = r.stdout
    assert "ERROR" not in out, out[-1500:]
    for exp in ["DA:4", "DB:4.", "DC:1", "DD:16..", "DE:\\breve",
                "CA:treble", "CB:bass", "CC:alto", "CD:tenor"]:
        assert exp in out, (exp, out[-1500:])
