"""lily_render.py runs LilyPond to a cropped SVG and outlines its <text> to <path> so Godot's ThorVG
(which cannot draw SVG <text>) shows lyrics/dynamics/tuplet numbers. LilyPond is always run first, so a
missing fontTools only skips the outlining — it never fails the render.

Run:  py -m pytest tools/verovio/test_lily_render.py -q     (skips cleanly if LilyPond is absent)
"""
import os
import subprocess
import sys
import tempfile
import shutil
import pytest

LILYPOND = os.environ.get("LILYPOND", r"C:\Program Files\lilypond-2.25.81\bin\lilypond.exe")
WRAPPER = os.path.join("addons", "musicscene", "tools", "lily_render.py")

# A tiny score with a tuplet ("3"), lyrics and a dynamic — all of which LilyPond emits as <text>.
LY = (
    '\\version "2.24.0"\n\\header { tagline = ##f }\n\\paper { indent = 0\\mm }\n'
    '\\score { <<\n'
    '  \\new Staff \\new Voice = "v1" { \\tuplet 3/2 { c\'8\\mf d\' e\' } c\'2 }\n'
    '  \\new Lyrics \\lyricsto "v1" { la la la la }\n'
    '>> }\n'
)


@pytest.mark.skipif(not os.path.exists(LILYPOND), reason="LilyPond not installed (set $LILYPOND)")
def test_lily_render_wrapper_outlines_text():
    d = tempfile.mkdtemp(prefix="lily_render_")
    try:
        ly_path = os.path.join(d, "s.ly")
        with open(ly_path, "w", encoding="utf-8") as f:
            f.write(LY)
        stem = os.path.join(d, "out")
        r = subprocess.run([sys.executable, WRAPPER, LILYPOND, ly_path, stem],
                           capture_output=True, text=True, timeout=120)
        assert r.returncode == 0, r.stderr[-1000:]
        cropped = stem + ".cropped.svg"
        assert os.path.exists(cropped), "wrapper produced no cropped SVG"
        svg = open(cropped, encoding="utf-8").read()
        # Point-and-click links survive the conversion (addressable positions still parse).
        assert "textedit" in svg, "point-and-click links lost"
        try:
            import fontTools  # noqa: F401
            has_ft = True
        except ImportError:
            has_ft = False
        if has_ft:
            # With fontTools present the text must be outlined to paths.
            assert "<text" not in svg, "text was not outlined to <path> despite fontTools being present"
            assert "<path" in svg
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(LILYPOND), reason="LilyPond not installed (set $LILYPOND)")
def test_lily_render_paged_multipage():
    """--paged renders a score with an explicit \\pageBreak to one cropped SVG per page."""
    d = tempfile.mkdtemp(prefix="lily_paged_")
    try:
        ly = (
            '\\version "2.24.0"\n\\header { tagline = ##f }\n'
            '\\score { <<\n'
            '  \\new Staff \\new Voice = "v1" { c\'1 \\pageBreak d\'1 }\n'
            '>> }\n'
        )
        ly_path = os.path.join(d, "s.ly")
        with open(ly_path, "w", encoding="utf-8") as f:
            f.write(ly)
        stem = os.path.join(d, "out")
        r = subprocess.run([sys.executable, WRAPPER, LILYPOND, ly_path, stem, "--paged", "1200"],
                           capture_output=True, text=True, timeout=120)
        assert r.returncode == 0, r.stderr[-1000:]
        p1 = stem + "-1.cropped.svg"
        p2 = stem + "-2.cropped.svg"
        assert os.path.exists(p1), "no page 1 (%s)" % r.stdout
        assert os.path.exists(p2), "no page 2 (\\pageBreak did not split): %s" % r.stdout
        for p in (p1, p2):
            svg = open(p, encoding="utf-8").read()
            assert "viewBox" in svg
            assert "textedit" in svg, "point-and-click links lost on " + p
        import re as _re
        def _w(path):
            m = _re.search(r'width="([-\d.]+)mm"', open(path, encoding="utf-8").read())
            return float(m.group(1)) if m else -1.0
        assert abs(_w(p1) - _w(p2)) < 0.01, "page widths differ (%s vs %s)" % (_w(p1), _w(p2))
    finally:
        shutil.rmtree(d, ignore_errors=True)
