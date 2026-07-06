"""SP1 duration-spelling tests for the Panola quark (PanolaRational + PanolaDurationSpeller).
Pure sclang value computation -- no server. Run:
  py -m pytest tools/panola_duration/test_duration_spelling.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script)
        path = f.name
    try:
        return subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)


RATIONAL_SCRIPT = r'''(
("REDUCE:" ++ PanolaRational(4, 8).asString).postln;
("ADD:" ++ (PanolaRational(1,3) + PanolaRational(1,6)).asString).postln;
("SUB:" ++ (PanolaRational(3,4) - PanolaRational(1,4)).asString).postln;
("MUL:" ++ (PanolaRational(1,2) * PanolaRational(2,3)).asString).postln;
("DIV:" ++ (PanolaRational(1,2) / PanolaRational(1,4)).asString).postln;
("EQ:" ++ (PanolaRational(4,8) == PanolaRational(1,2)).asString).postln;
("LT:" ++ (PanolaRational(1,3) < PanolaRational(1,2)).asString).postln;
("NEG:" ++ PanolaRational(-2,4).asString).postln;
("BIG:" ++ (PanolaRational(1,65536) * PanolaRational(1,2)).asString).postln;
("F13:" ++ PanolaRational.fromFloat(1/3).asString).postln;
("F04:" ++ PanolaRational.fromFloat(0.4).asString).postln;
("F01:" ++ PanolaRational.fromFloat(0.1).asString).postln;
("DEC:" ++ PanolaRational.fromDecimalString("0.625").asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_rational():
    r = _run(RATIONAL_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    for expect in ["REDUCE:1/2", "ADD:1/2", "SUB:1/2", "MUL:1/3", "DIV:2/1", "EQ:true",
                   "LT:true", "NEG:-1/2", "BIG:1/131072", "F13:1/3", "F04:2/5", "F01:1/10",
                   "DEC:5/8"]:
        assert expect in r.stdout, f"missing {expect}\n{r.stdout[-1500:]}"
