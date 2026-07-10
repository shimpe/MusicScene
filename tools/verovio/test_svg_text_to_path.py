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
