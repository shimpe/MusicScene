"""SP2f: mid-piece meter/key changes via a `changes` list; inline clef via @clef.
Run:  py -m pytest tools/panola_mei/test_midpiece_changes.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_mp_")
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
def test_new_api_constant_matches_old_shape():
    # a single measure-1 changes entry with no changes: one top <scoreDef>, correct sig, renders.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 a5")], '
               '[( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert mei.count("<scoreDef") == 1, mei
    assert 'meter.count="4" meter.unit="4"' in mei and 'key.sig="0"' in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_key_change_at_a_measure():
    # 4/4 throughout; key goes Cmajor -> Gmajor at bar 2. A mid-section <scoreDef key.sig="1s"/> precedes
    # measure 2, and an f in bar 2 is spelled in G (no natural forced) while an f in bar 1 shows a natural
    # if needed. (c5 e5 g5 f5 | f5 g5 a5 b5)
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 c6 f5_4 g5 a5 b5")], '
               '[( measure: 1, meter: "4/4", key: \\Cmajor ), ( measure: 2, key: \\Gmajor )], [\\treble], nil)')
    body = mei.split("</scoreDef>", 1)[1]     # after the top scoreDef
    assert '<scoreDef key.sig="1s"/>' in body, mei          # mid-section key change before bar 2
    assert body.index('<scoreDef key.sig="1s"') < body.index('<measure n="2"'), mei
    assert render_props(mei)["ok"], mei
