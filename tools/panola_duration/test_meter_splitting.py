"""SP2a meter-splitting tests for the Panola quark (PanolaMeter + PanolaMeterSplitter).
Pure sclang value computation -- no server. Run:
  py -m pytest tools/panola_duration/test_meter_splitting.py -q   (skips if sclang absent)
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


# format a meter's boundaries as "off@strength" tokens joined by ; (offsets as num/den)
METER_SCRIPT = r'''(
var fmt = { |m| m.boundaries.collect({ |b| b[\offsetQL].asString ++ "@" ++ b[\strength] }).join(";") };
("M44:" ++ fmt.(PanolaMeter(4, 4))).postln;
("M34:" ++ fmt.(PanolaMeter(3, 4))).postln;
("M68:" ++ fmt.(PanolaMeter(6, 8))).postln;
("M78:" ++ fmt.(PanolaMeter(7, 8, [2,2,3]))).postln;
("LEN44:" ++ PanolaMeter(4,4).measureLengthQL.asString).postln;
("LEN68:" ++ PanolaMeter(6,8).measureLengthQL.asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_meter_boundaries():
    r = _run(METER_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "LEN44:4/1" in r.stdout, r.stdout[-1500:]
    assert "LEN68:3/1" in r.stdout, r.stdout[-1500:]
    # 4/4: 0@100 0.5@30 1@60 1.5@30 2@80 2.5@30 3@60 3.5@30 4@100
    assert "M44:0/1@100;1/2@30;1/1@60;3/2@30;2/1@80;5/2@30;3/1@60;7/2@30;4/1@100" in r.stdout, r.stdout[-1500:]
    # 3/4: 0@100 1@60 2@60 3@100 (+ subdivisions 0.5,1.5,2.5 @30)
    assert "M34:0/1@100;1/2@30;1/1@60;3/2@30;2/1@60;5/2@30;3/1@100" in r.stdout, r.stdout[-1500:]
    # 6/8: 0@100 0.5@40 1@40 1.5@70 2@40 2.5@40 3@100
    assert "M68:0/1@100;1/2@40;1/1@40;3/2@70;2/1@40;5/2@40;3/1@100" in r.stdout, r.stdout[-1500:]
    # 7/8 [2,2,3]: 0@100 0.5@40 1@75 1.5@40 2@75 2.5@40 3@40 3.5@100
    assert "M78:0/1@100;1/2@40;1/1@75;3/2@40;2/1@75;5/2@40;3/1@40;7/2@100" in r.stdout, r.stdout[-1500:]
