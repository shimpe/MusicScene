"""MSScore forwards pageBreaks/systemBreaks into the MEI it builds (msscore quark).
Run:  py -m pytest tools/msscore/test_page_breaks.py -q  (skips if sclang absent)
"""
import os, pytest
from tools.msscore.test_midi_routing import _run, SCLANG

SIXBAR = "c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5"
SCRIPT = r'''(
var s = MSScore(voices: ["%s"], pageBreaks: [3], systemBreaks: [5]);
var m = s.mei;
(m.contains("<pb/><measure n=\"3\"")).if({ "PB-OK".postln }, { "PB-BAD".postln });
(m.contains("<sb/><measure n=\"5\"")).if({ "SB-OK".postln }, { "SB-BAD".postln });
0.exit;
)''' % SIXBAR


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_msscore_forwards_breaks():
    r = _run(SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "PB-OK" in r.stdout, r.stdout[-1500:]
    assert "SB-OK" in r.stdout, r.stdout[-1500:]
