#!/usr/bin/env python3
"""Render a LilyPond source to a cropped SVG, then outline its <text> to <path>.

MusicScene invokes this instead of calling LilyPond directly when a fontTools-capable Python is
available. LilyPond emits lyrics, dynamics and tuplet numbers as SVG <text> (font-family="serif"),
and Godot's ThorVG rasteriser cannot draw <text> — so without this step that text is invisible in the
notation preview (noteheads/staff, which are <path>/<rect>, still show). Outlining the text to <path>
(via the shared svg_text_to_path module, which uses the bundled Tinos faces) makes it visible while
leaving the point-and-click <a> links and note data-when attributes untouched, so addressable
positions still parse.

Usage:  python lily_render.py <lilypond_exe> <input.ly> <output_stem>
LilyPond writes <output_stem>.cropped.svg (and <output_stem>.svg); the cropped one is converted in
place. LilyPond is ALWAYS run first; the conversion is best-effort — if svg_text_to_path or fontTools
is unavailable, the SVG is left as LilyPond wrote it (render still succeeds; text simply not outlined),
so this can never turn a working render blank.
"""
import os
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 4:
        sys.stderr.write("lily_render: usage: lily_render.py <lilypond_exe> <input.ly> <output_stem>\n")
        return 2
    lilypond, inp, stem = sys.argv[1], sys.argv[2], sys.argv[3]
    # Same flags MSRenderQueue used before: a cropped SVG for the addressable/preview path.
    rc = subprocess.run([lilypond, "-dbackend=svg", "-dcrop=#t", "-o", stem, inp]).returncode
    if rc != 0:
        return rc
    cropped = stem + ".cropped.svg"
    if os.path.exists(cropped):
        # Best-effort text->path. Import INSIDE the try, AFTER LilyPond ran, so a missing fontTools
        # (or any converter error) never fails the render — it just leaves the text unoutlined.
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from svg_text_to_path import svg_text_to_path
            with open(cropped, encoding="utf-8") as f:
                svg = f.read()
            converted = svg_text_to_path(svg)   # returns the original SVG on any internal failure
            with open(cropped, "w", encoding="utf-8") as f:
                f.write(converted)
            sys.stdout.write("lily_render: wrote %s (text->path)\n" % cropped)
        except Exception as e:  # never fail the render over the cosmetic conversion
            sys.stderr.write("lily_render: text->path skipped: %s\n" % e)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
