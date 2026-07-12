#!/usr/bin/env python3
"""Render a LilyPond source to a cropped SVG for the MusicScene notation preview.

Two jobs, both so the preview looks right in Godot's ThorVG rasteriser:

1. Vertical spacing. LilyPond's own ``-dcrop`` removes the vertical space between systems (a documented
   limitation), so several systems on one image clash. Instead we render a normal (full) page onto one
   very tall page — where LilyPond spaces the systems correctly — and then crop the SVG's viewBox to the
   inked content ourselves, keeping the inter-system gaps. If anything about that path fails we fall back
   to plain ``-dcrop`` (systems may clash, but the render still succeeds).

2. Text. LilyPond emits lyrics, dynamics and tuplet numbers as SVG ``<text>``, which ThorVG cannot draw.
   We outline them to ``<path>`` via the shared svg_text_to_path module. LilyPond is always run first and
   the outlining is best-effort, so a missing fontTools only leaves the text unoutlined — never blank.

Usage:  python lily_render.py <lilypond_exe> <input.ly> <output_stem>
Writes <output_stem>.cropped.svg (the file MusicScene reads).
"""
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
# A page tall enough for any realistic score (the empty part below the music is cropped away), with a
# controlled inter-system distance — full-page layout respects system-system-spacing (unlike -dcrop),
# so this gives a clear but not airy gap between systems.
FULLPAGE_PAPER = ("\n\\paper { page-count = #1 paper-height = 12000\\mm ragged-bottom = ##t"
                  " ragged-last-bottom = ##t system-system-spacing.basic-distance = #12"
                  " system-system-spacing.padding = #2 }\n")
CROP_MARGIN = 3.0   # viewBox units of slack so glyph/stem/ledger edges are never clipped


def _translate(el):
    m = re.search(r"translate\(([-\d.eE]+)[ ,]+([-\d.eE]+)\)", el.get("transform", ""))
    return (float(m.group(1)), float(m.group(2))) if m else (0.0, 0.0)


def _content_bbox(root):
    """Bounding box (minx, miny, maxx, maxy) of the inked content, accumulating <g translate>.
    Rects/lines/polygons are exact; glyph/text/use are taken at their placement point (CROP_MARGIN
    covers their small extent). Returns None if nothing was found."""
    box = [1e18, 1e18, -1e18, -1e18]

    def add(x, y):
        if x < box[0]: box[0] = x
        if y < box[1]: box[1] = y
        if x > box[2]: box[2] = x
        if y > box[3]: box[3] = y

    def walk(el, ax, ay):
        for ch in el:
            tag = ch.tag.split("}")[-1]
            dx, dy = _translate(ch)
            nx, ny = ax + dx, ay + dy
            if tag == "rect":
                x = float(ch.get("x", 0)); y = float(ch.get("y", 0))
                add(nx + x, ny + y); add(nx + x + float(ch.get("width", 0)), ny + y + float(ch.get("height", 0)))
            elif tag == "line":
                add(nx + float(ch.get("x1", 0)), ny + float(ch.get("y1", 0)))
                add(nx + float(ch.get("x2", 0)), ny + float(ch.get("y2", 0)))
            elif tag == "polygon":
                for a, b in re.findall(r"([-\d.eE]+)[ ,]([-\d.eE]+)", ch.get("points", "")):
                    add(nx + float(a), ny + float(b))
            elif tag in ("path", "text", "use"):
                add(nx, ny)
            walk(ch, nx, ny)

    walk(root, 0.0, 0.0)
    if box[0] > box[2] or box[1] > box[3]:
        return None
    return tuple(box)


def _crop_to_content(svg_path, out_path):
    """Rewrite svg_path's viewBox/width/height to the inked content (plus a margin) and save to
    out_path. Returns True on success."""
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    tree = ET.parse(svg_path)
    root = tree.getroot()
    vb = (root.get("viewBox") or "").split()
    width_mm = float(re.sub(r"[a-z]+$", "", root.get("width", "0")))
    if len(vb) != 4 or width_mm <= 0.0:
        return False
    mm_per_unit = width_mm / float(vb[2]) if float(vb[2]) else 0.0
    bbox = _content_bbox(root)
    if bbox is None or mm_per_unit <= 0.0:
        return False
    minx, miny, maxx, maxy = bbox
    m = CROP_MARGIN
    x0, y0 = minx - m, miny - m
    w, h = (maxx - minx) + 2 * m, (maxy - miny) + 2 * m
    if w <= 0.0 or h <= 0.0:
        return False
    root.set("viewBox", "%.4f %.4f %.4f %.4f" % (x0, y0, w, h))
    root.set("width", "%.4fmm" % (w * mm_per_unit))
    root.set("height", "%.4fmm" % (h * mm_per_unit))
    tree.write(out_path, encoding="unicode")
    return True


def _text_to_path(cropped):
    """Best-effort: outline <text> to <path> in place (never fails the render)."""
    if not os.path.exists(cropped):
        return
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from svg_text_to_path import svg_text_to_path
        with open(cropped, encoding="utf-8") as f:
            svg = f.read()
        with open(cropped, "w", encoding="utf-8") as f:
            f.write(svg_text_to_path(svg))
    except Exception as e:
        sys.stderr.write("lily_render: text->path skipped: %s\n" % e)


def _run(lilypond, args):
    return subprocess.run([lilypond] + args).returncode


def main() -> int:
    if len(sys.argv) < 4:
        sys.stderr.write("lily_render: usage: lily_render.py <lilypond_exe> <input.ly> <output_stem>\n")
        return 2
    lilypond, inp, stem = sys.argv[1], sys.argv[2], sys.argv[3]
    cropped = stem + ".cropped.svg"

    # Path 1: full page (correct inter-system spacing) on one tall page, then crop the viewBox ourselves.
    ok = False
    try:
        with open(inp, encoding="utf-8") as f:
            src = f.read()
        render_ly = stem + ".render.ly"
        with open(render_ly, "w", encoding="utf-8") as f:
            f.write(src + FULLPAGE_PAPER)
        if _run(lilypond, ["-dbackend=svg", "-o", stem, render_ly]) == 0:
            full = stem + ".svg"
            if not os.path.exists(full) and os.path.exists(stem + "-1.svg"):
                full = stem + "-1.svg"
            if os.path.exists(full):
                ok = _crop_to_content(full, cropped)
    except Exception as e:
        sys.stderr.write("lily_render: full-page crop failed (%s); using -dcrop\n" % e)
        ok = False

    # Path 2 (fallback): LilyPond's own crop. Systems may clash, but the render succeeds.
    if not ok:
        rc = _run(lilypond, ["-dbackend=svg", "-dcrop=#t", "-o", stem, inp])
        if rc != 0:
            return rc
        if not os.path.exists(cropped):
            sys.stderr.write("lily_render: no cropped SVG produced\n")
            return 1

    _text_to_path(cropped)
    sys.stdout.write("lily_render: wrote %s (%s)\n" % (cropped, "full-page crop" if ok else "-dcrop fallback"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
