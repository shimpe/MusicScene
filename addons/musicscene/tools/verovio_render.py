#!/usr/bin/env python3
"""Verovio engraver/positions wrapper for MusicScene.

Renders MEI / MusicXML / ABC / PAE / Humdrum to an SVG cropped to the music (page width AND height
shrink to the content, so a short excerpt isn't padded to a full page of white), and (with --timemap)
also writes a timemap JSON (element id -> onset time). MusicScene rasterizes the SVG, reads stable note
ids from it, and joins them to the timemap for note-level addressing + following.

Usage:
    py verovio_render.py <input> <output.svg> [--page N] [--timemap <file.json>] [--scale N] [--no-crop]
    py verovio_render.py <input> <output.svg> --paginate [--page-height H] [--page-width W] [--timemap f]

With --paginate the score is laid out on several fixed-size pages (readable for long fragments) and each
page is written to <output_stem>-<n>.svg; without it, the single page is cropped to the music.

Install: pip install verovio
"""
import argparse
import json
import os
import sys

try:
    import verovio
except ImportError:
    sys.stderr.write("verovio not installed. Run: pip install verovio\n")
    sys.exit(3)


def _write_timemap(tk, path: str) -> None:
    if not path:
        return
    tm = tk.renderToTimemap()
    if not isinstance(tm, str):
        tm = json.dumps(tm)
    with open(path, "w", encoding="utf-8") as f:
        f.write(tm)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")                 # .svg
    ap.add_argument("--page", type=int, default=1)
    ap.add_argument("--timemap", default="")
    ap.add_argument("--scale", type=int, default=40)
    ap.add_argument("--breaks", default="detect")  # detect: encoded if <pb>, line if <sb>, else auto
    ap.add_argument("--text-to-path", action="store_true",
                    help="rewrite SVG <text> to <path> outlines (for renderers without SVG-text support)")
    ap.add_argument("--no-crop", action="store_true", help="keep the full page width (default: crop to content)")
    ap.add_argument("--paginate", action="store_true",
                    help="lay the score out on several fixed-size pages; write <output_stem>-<n>.svg per page")
    ap.add_argument("--page-height", type=int, default=1200)   # Verovio units; ~a few systems per page
    ap.add_argument("--page-width", type=int, default=2100)
    a = ap.parse_args()

    convert = None
    if a.text_to_path:
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from svg_text_to_path import svg_text_to_path as convert
        except Exception as e:
            sys.stderr.write("verovio_render: --text-to-path unavailable: %s\n" % e)
            convert = None

    breaks = a.breaks
    if breaks == "detect":
        try:
            _src = open(a.input, encoding="utf-8", errors="ignore").read()
        except OSError:
            _src = ""
        breaks = "encoded" if "<pb" in _src else ("line" if "<sb" in _src else "auto")

    tk = verovio.toolkit()
    if a.paginate:
        # Uniform fixed-size pages so Verovio breaks the score into readable pages (no cropping, so every
        # page is the same size and the display doesn't jump when turning).
        tk.setOptions({
            "adjustPageHeight": False, "adjustPageWidth": False,
            "pageHeight": a.page_height, "pageWidth": a.page_width,
            "breaks": breaks, "scale": a.scale, "header": "none", "footer": "none",
        })
    else:
        tk.setOptions({
            # Crop the page to the music so a short excerpt isn't padded to a full page of white.
            "adjustPageHeight": True, "adjustPageWidth": not a.no_crop,
            "breaks": breaks, "scale": a.scale, "header": "none", "footer": "none",
        })
    if not tk.loadFile(a.input):
        sys.stderr.write("verovio: could not load " + a.input + "\n")
        return 2

    if a.paginate:
        n = tk.getPageCount()
        stem = a.output[:-4] if a.output.lower().endswith(".svg") else a.output
        for pg in range(1, n + 1):
            svg = tk.renderToSVG(pg)
            if convert is not None:
                svg = convert(svg)
            with open("%s-%d.svg" % (stem, pg), "w", encoding="utf-8") as f:
                f.write(svg)
        _write_timemap(tk, a.timemap)
        print("verovio: wrote %d page(s) %s-N.svg%s (breaks=%s)%s" % (n, stem, " + timemap" if a.timemap else "", breaks, " (text->path)" if convert is not None else ""))
        return 0

    page = max(1, min(a.page, tk.getPageCount()))
    svg = tk.renderToSVG(page)
    if convert is not None:
        svg = convert(svg)
    with open(a.output, "w", encoding="utf-8") as f:
        f.write(svg)
    _write_timemap(tk, a.timemap)
    print("verovio: wrote " + a.output + (" + timemap" if a.timemap else "") + (" (breaks=%s)" % breaks) + (" (text->path)" if convert is not None else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
