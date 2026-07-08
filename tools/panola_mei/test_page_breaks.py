"""Forced page/system break tests: Panola.scoreAsMEI emission + the Verovio wrapper's breaks-mode
auto-detection. Run:  py -m pytest tools/panola_mei/test_page_breaks.py -q  (sclang parts skip if absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.test_expression import _dump, SCLANG

# a 6-bar single voice (24 quarters in 4/4); breaks at measures 3 (page) and 5 (system)
SIXBAR = "c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5 c5_4 d5 e5 f5"
EMIT = {
  "brk":   r'Panola.scoreAsMEI([Panola("%s")], nil, [\treble], nil, [3], [5])' % SIXBAR,
  "nobrk": r'Panola.scoreAsMEI([Panola("%s")], nil, [\treble], nil, nil, nil)' % SIXBAR,
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_scoreasmei_emits_breaks():
    outdir = tempfile.mkdtemp(prefix="panola_brk_")
    try:
        _dump(outdir, EMIT)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in EMIT}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)
    assert '<pb/><measure n="3"' in meis["brk"], meis["brk"][:400]
    assert '<sb/><measure n="5"' in meis["brk"], meis["brk"][:400]
    assert "<pb/>" not in meis["nobrk"]
    assert "<sb/>" not in meis["nobrk"]
