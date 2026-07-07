"""MSScore `changes:` surface — a mid-piece meter/key changes list flows through to the MEI, while the
constant meter/key form stays byte-identical (one top <scoreDef>, no mid-section scoreDefs).
Pure sclang MEI inspection -- no audio server. Run:
  py -m pytest tools/msscore/test_changes.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script)
        path = f.name
    try:
        return subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)


def _scoredef_count(stdout):
    m = re.search(r"SCOREDEF_COUNT:(\d+)", stdout)
    assert m, stdout[-1500:]
    return int(m.group(1))


# A constant meter/key MSScore (no `changes:`) emits exactly one top <scoreDef>, no key/meter change.
CONSTANT_SCRIPT = r'''(
var s = MSScore(voices: ["c5_4 d5 e5 f5", "c3_1"], clefs: [\treble, \bass],
    meter: "4/4", key: \Cmajor, braces: [[1, 2]]);
var m = s.mei;
("SCOREDEF_COUNT:" ++ (m.findAll("<scoreDef") ? []).size).postln;
("HAS_KEYSIG_1S:" ++ (m.find("key.sig=\"1s\"").notNil).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_constant_meter_key_single_scoredef():
    r = _run(CONSTANT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert _scoredef_count(r.stdout) == 1, r.stdout[-1500:]     # only the top scoreDef
    assert "HAS_KEYSIG_1S:false" in r.stdout, r.stdout[-1500:]  # no mid-section key change


# A `changes:` list drives a mid-piece key change (Cmajor -> Gmajor at bar 3) and meter change
# (4/4 -> 3/4 at bar 5) -> extra mid-section <scoreDef>s carrying key.sig="1s" and meter.count="3".
CHANGES_SCRIPT = r'''(
var s = MSScore(
    voices: ["c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5"],
    clefs:  [\treble],
    changes: [ ( measure: 1, meter: "4/4", key: \Cmajor ),
               ( measure: 3, key: \Gmajor ),
               ( measure: 5, meter: "3/4" ) ]);
var m = s.mei;
("SCOREDEF_COUNT:" ++ (m.findAll("<scoreDef") ? []).size).postln;
("HAS_KEYSIG_1S:" ++ (m.find("key.sig=\"1s\"").notNil).asString).postln;
("HAS_METER_3:"   ++ (m.find("meter.count=\"3\"").notNil).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_changes_list_emits_midsection_scoredefs():
    r = _run(CHANGES_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert _scoredef_count(r.stdout) >= 2, r.stdout[-1500:]     # top + mid-section scoreDef(s)
    assert "HAS_KEYSIG_1S:true" in r.stdout, r.stdout[-1500:]   # Gmajor from bar 3
    assert "HAS_METER_3:true" in r.stdout, r.stdout[-1500:]     # 3/4 from bar 5
