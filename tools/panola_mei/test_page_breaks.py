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


_WRAP = os.path.join(os.path.dirname(__file__), "..", "..", "addons", "musicscene", "tools", "verovio_render.py")


def _mei(pb=False, sb=False):
    inner = ""
    for n in range(1, 7):
        brk = ("<pb/>" if (pb and n == 3) else "") + ("<sb/>" if (sb and n == 3) else "")
        inner += (brk + '<measure n="%d"><staff n="1"><layer n="1">'
                  '<note dur="1" oct="5" pname="c"/></layer></staff></measure>' % n)
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0">'
            '<music><body><mdiv><score>'
            '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
            '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
            '<section>' + inner + '</section></score></mdiv></body></music></mei>')


def _run_wrap(mei, height=700):
    d = tempfile.mkdtemp(prefix="brk_wrap_")
    try:
        inp = os.path.join(d, "s.mei")
        open(inp, "w", encoding="utf-8").write(mei)
        r = subprocess.run(["py", _WRAP, inp, os.path.join(d, "s.svg"),
                            "--paginate", "--page-height", str(height)],
                           capture_output=True, text=True)
        if "verovio not installed" in (r.stdout + r.stderr):
            pytest.skip("verovio not installed")
        return r.stdout + r.stderr
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_wrapper_detects_encoded_for_pb():
    assert "breaks=encoded" in _run_wrap(_mei(pb=True))


def test_wrapper_detects_line_for_sb_only():
    assert "breaks=line" in _run_wrap(_mei(sb=True))


def test_wrapper_auto_without_breaks():
    assert "breaks=auto" in _run_wrap(_mei())
