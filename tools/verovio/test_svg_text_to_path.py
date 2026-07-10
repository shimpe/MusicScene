"""Tests for the Verovio SVG <text> -> <path> converter.
Run:  py -m pytest tools/verovio/test_svg_text_to_path.py -q
"""
import importlib.util, os, sys, re
import pytest

_MOD = os.path.join(os.path.dirname(__file__), "..", "..",
                    "addons", "musicscene", "tools", "svg_text_to_path.py")

def _load():
    spec = importlib.util.spec_from_file_location("svg_text_to_path", _MOD)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

# a minimal Verovio-shaped SVG: a <style> with the class rules, a note glyph via <use xlink:href>,
# a verse <text> (regular) and a tempo <text> (bold), each with the Verovio 0px-outer/real-tspan idiom.
SVG = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
  'width="400" height="200" viewBox="0 0 4000 2000">'
  '<style type="text/css">#x g.tempo {font-weight:bold;}#x g.dir {font-style:italic;}'
  'ellipse, path {stroke:currentColor}</style>'
  '<g class="note" id="note1"><use xlink:href="#glyph-x" x="100" y="100"/></g>'
  '<g class="verse"><text x="500" y="1500" font-size="0px"><tspan font-size="360">morn</tspan></text></g>'
  '<g class="tempo"><text x="500" y="200" font-size="0px"><tspan font-size="360">morn</tspan></text></g>'
  '</svg>'
)

def test_converts_text_to_path_and_preserves_notes():
    out = _load().svg_text_to_path(SVG)
    assert "<text" not in out                          # every <text> converted
    assert "<path" in out                              # ... into paths
    assert 'xlink:href="#glyph-x"' in out              # note glyph refs preserved (namespace round-trip)
    assert 'id="note1"' in out                         # note ids preserved (position parsing safe)
    assert "<style" in out                             # style block still present

def test_bold_class_uses_bold_face():
    # same letters at the same size, one in a verse (regular) group, one in a tempo (bold) group.
    # the two runs must emit DIFFERENT path outlines -> proves the bold face was selected.
    out = _load().svg_text_to_path(SVG)
    ds = re.findall(r'<path[^>]*\bd="([^"]+)"', out)
    assert len(ds) >= 2
    # the verse "morn" (4 glyphs regular) and tempo "morn" (4 glyphs bold) differ glyph-for-glyph
    assert ds[:4] != ds[4:8]

def test_missing_fonttools_returns_unchanged(monkeypatch):
    m = _load()
    monkeypatch.setattr(m, "_load_face", lambda style: None)  # simulate no font/fonttools
    out = m.svg_text_to_path(SVG)
    assert out == SVG                                   # unchanged, render never breaks

def test_no_text_is_noop():
    plain = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
             '<rect width="10" height="10"/></svg>')
    out = _load().svg_text_to_path(plain)
    assert "<rect" in out and "<text" not in out

# a REALISTIC Verovio-shaped fragment: INDENTED, sized tspan nested inside <tspan class="text">
# (this is what renderToSVG actually emits; the flat SVG above never occurs in practice).
NESTED = (
  '<?xml version="1.0" encoding="UTF-8"?>\n'
  '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 4000 3000">\n'
  '  <style type="text/css">#x g.dir {font-style:italic;}</style>\n'
  '  <g class="verse">\n'
  '    <text x="1193" y="2708" font-size="0px">\n'
  '      <tspan class="text">\n'
  '        <tspan font-size="405px">morn</tspan>\n'
  '      </tspan>\n'
  '    </text>\n'
  '  </g>\n'
  '  <g class="dir">\n'
  '    <text x="500" y="300" font-size="0px"><tspan class="text"><tspan font-size="300px">dolce</tspan></tspan></text>\n'
  '  </g>\n'
  '</svg>\n'
)

def test_nested_indented_verovio_shape_converts_and_positions():
    out = _load().svg_text_to_path(NESTED)
    assert "<text" not in out and "<path" in out          # nested tspan size found -> converted
    # the first glyph of "morn" must land near the text x=1193 (not shifted by indent whitespace)
    m = re.search(r'<path[^>]*translate\((-?[0-9.]+) ', out)
    assert m, out
    assert abs(float(m.group(1)) - 1193.0) < 50.0          # at the text origin, not +indent advance
    # the dir syllable uses the italic face (its outlines differ from the regular face)
    reg = _load().svg_text_to_path(NESTED.replace('class="dir"', 'class="plain"'))
    assert re.findall(r'd="([^"]+)"', out) != re.findall(r'd="([^"]+)"', reg)

import subprocess, tempfile, shutil, json
SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")
WRAP = os.path.join(os.path.dirname(__file__), "..", "..",
                    "addons", "musicscene", "tools", "verovio_render.py")

def _mei_with_lyrics(path):
    """Write a 2-note lyric MEI via sclang; skip if sclang absent."""
    script = ('(File.use("%s","w",{|f| f.write('
              'PanolaMEI.scoreAsMEI([Panola("c5_4 d5")], [( measure: 1, meter: "4/4", key: \\Cmajor )],'
              ' [\\treble], nil, nil, nil, [[ "morn-ing" ]]))}); 0.exit;)' % path.replace("\\", "/"))
    f = tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8")
    f.write(script); f.close()
    try:
        subprocess.run([SCLANG, f.name], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(f.name)

@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_flag_converts_text_but_default_does_not():
    d = tempfile.mkdtemp(prefix="v2p_")
    try:
        mei = os.path.join(d, "s.mei"); _mei_with_lyrics(mei)
        if not os.path.exists(mei):
            pytest.skip("sclang did not produce MEI")
        # default: SVG keeps <text>
        subprocess.run(["py", WRAP, mei, os.path.join(d, "plain.svg"), "--page", "1"],
                       capture_output=True, text=True)
        plain = open(os.path.join(d, "plain.svg"), encoding="utf-8").read()
        # with the flag: SVG has <path>, no <text>, and the "morn" glyphs
        r = subprocess.run(["py", WRAP, mei, os.path.join(d, "p.svg"), "--page", "1", "--text-to-path"],
                           capture_output=True, text=True)
        conv = open(os.path.join(d, "p.svg"), encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    assert "<text" in plain                      # default unchanged
    assert "<text" not in conv and "<path" in conv
    assert "(text→path)" in (r.stdout + r.stderr) or "text->path" in (r.stdout + r.stderr)
