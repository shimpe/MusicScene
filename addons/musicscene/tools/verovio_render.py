#!/usr/bin/env python3
"""Verovio engraver/positions wrapper for MusicScene.

Renders MEI / MusicXML / ABC / PAE / Humdrum to an SVG cropped to the music (page width AND height
shrink to the content, so a short excerpt isn't padded to a full page of white), and (with --timemap)
also writes a timemap JSON (element id -> onset time). MusicScene rasterizes the SVG, reads stable note
ids from it, and joins them to the timemap for note-level addressing + following.

Usage:
    py verovio_render.py <input> <output.svg> [--page N] [--timemap <file.json>] [--scale N] [--no-crop]

Install: pip install verovio
"""
import argparse
import json
import sys

try:
    import verovio
except ImportError:
    sys.stderr.write("verovio not installed. Run: pip install verovio\n")
    sys.exit(3)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")                 # .svg
    ap.add_argument("--page", type=int, default=1)
    ap.add_argument("--timemap", default="")
    ap.add_argument("--scale", type=int, default=40)
    ap.add_argument("--breaks", default="auto")  # "none" = single system strip
    ap.add_argument("--no-crop", action="store_true", help="keep the full page width (default: crop to content)")
    a = ap.parse_args()

    tk = verovio.toolkit()
    tk.setOptions({
        # Crop the page to the music so a short excerpt isn't padded to a full page of white
        # (adjustPageWidth/Height shrink the page to the content's bounding box).
        "adjustPageHeight": True,
        "adjustPageWidth": not a.no_crop,
        "breaks": a.breaks,
        "scale": a.scale,
        "header": "none",
        "footer": "none",
    })
    if not tk.loadFile(a.input):
        sys.stderr.write("verovio: could not load " + a.input + "\n")
        return 2

    page = max(1, min(a.page, tk.getPageCount()))
    with open(a.output, "w", encoding="utf-8") as f:
        f.write(tk.renderToSVG(page))

    if a.timemap:
        tm = tk.renderToTimemap()
        if not isinstance(tm, str):
            tm = json.dumps(tm)
        with open(a.timemap, "w", encoding="utf-8") as f:
            f.write(tm)

    print("verovio: wrote " + a.output + (" + timemap" if a.timemap else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
