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


SIMPLE_DOTTED_SCRIPT = r'''(
var fmt = { |sp|
    sp[\inexpressible].if({ "INEXPR:" ++ sp[\reason] }, {
        "OK:" ++ sp[\components].collect({ |c| c[\type].asString ++ "." ++ c[\dots] ++ "(" ++ c[\meidur] ++ ")" }).join("+");
    });
};
("Q1:" ++ fmt.(PanolaDurationSpeller.spell(1.0))).postln;
("E:" ++ fmt.(PanolaDurationSpeller.spell(0.5))).postln;
("W:" ++ fmt.(PanolaDurationSpeller.spell(4.0))).postln;
("DE:" ++ fmt.(PanolaDurationSpeller.spell(0.75))).postln;
("DDQ:" ++ fmt.(PanolaDurationSpeller.spell(1.75))).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_simple_dotted():
    r = _run(SIMPLE_DOTTED_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "Q1:OK:quarter.0(4)" in r.stdout, r.stdout[-1500:]
    assert "E:OK:eighth.0(8)" in r.stdout, r.stdout[-1500:]
    assert "W:OK:whole.0(1)" in r.stdout, r.stdout[-1500:]
    assert "DE:OK:eighth.1(8)" in r.stdout, r.stdout[-1500:]    # dotted eighth
    assert "DDQ:OK:quarter.2(4)" in r.stdout, r.stdout[-1500:]  # double-dotted quarter = 1.75


GUARDS_SCRIPT = r'''(
var fmt = { |sp| sp[\inexpressible].if({ "INEXPR:" ++ sp[\reason] }, { "OK:" ++ sp[\components].size }) };
("NEG:" ++ fmt.(PanolaDurationSpeller.spell(-1.0))).postln;
("NAN:" ++ fmt.(PanolaDurationSpeller.spell(0.0/0.0))).postln;
("ZERO:" ++ fmt.(PanolaDurationSpeller.spell(0.0))).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_guards_zero():
    r = _run(GUARDS_SCRIPT)
    assert "NEG:INEXPR:negative duration" in r.stdout, r.stdout[-1500:]
    assert "NAN:INEXPR:NaN or infinite duration" in r.stdout, r.stdout[-1500:]
    assert "ZERO:OK:0" in r.stdout, r.stdout[-1500:]   # zero duration -> empty components


TUPLET_SCRIPT = r'''(
var fmt = { |sp|
    sp[\inexpressible].if({ "INEXPR" }, {
        sp[\components].collect({ |c|
            var t = c[\tuplets];
            c[\type].asString ++ (t.isEmpty.if({ "" }, { "[" ++ t[0][\actual] ++ ":" ++ t[0][\normal] ++ "]" }));
        }).join("+");
    });
};
("T3:" ++ fmt.(PanolaDurationSpeller.spell(1/3))).postln;   // eighth triplet 3:2
("T6:" ++ fmt.(PanolaDurationSpeller.spell(1/6))).postln;   // 16th triplet 3:2
("T5:" ++ fmt.(PanolaDurationSpeller.spell(1/5))).postln;   // 16th quintuplet 5:4 (1/4*4/5=1/5)
("T11:" ++ fmt.(PanolaDurationSpeller.spell(1/11))).postln; // 11-tuplet under a 32nd (11:8, power-of-two normal)
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplets():
    r = _run(TUPLET_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "T3:eighth[3:2]" in r.stdout, r.stdout[-1500:]
    assert "T6:16th[3:2]" in r.stdout, r.stdout[-1500:]
    assert "T5:16th[5:4]" in r.stdout, r.stdout[-1500:]
    assert "T11:32nd[11:8]" in r.stdout, r.stdout[-1500:]


SPLIT_SCRIPT = r'''(
var fmt = { |sp|
    sp[\inexpressible].if({ "INEXPR" }, {
        sp[\components].collect({ |c| c[\type].asString ++ "." ++ c[\dots] }).join("+");
    });
};
("S125:" ++ fmt.(PanolaDurationSpeller.spell(1.25))).postln;   // quarter + 16th
("S0625:" ++ fmt.(PanolaDurationSpeller.spell(0.625))).postln; // eighth + 32nd
("SUM:" ++ (PanolaDurationSpeller.spell(1.25)[\components].inject(PanolaRational(0,1), { |a, c| a + c[\ql] }) == PanolaRational(5,4)).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_split():
    r = _run(SPLIT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "S125:quarter.0+16th.0" in r.stdout, r.stdout[-1500:]
    assert "S0625:eighth.0+32nd.0" in r.stdout, r.stdout[-1500:]
    assert "SUM:true" in r.stdout, r.stdout[-1500:]   # components sum exactly to the input
