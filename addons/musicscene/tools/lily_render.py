#!/usr/bin/env python3
"""Render a LilyPond source to cropped SVG(s) for the MusicScene notation preview.

Two jobs, both so the preview looks right in Godot's ThorVG rasteriser:

1. Vertical spacing. LilyPond's own ``-dcrop`` removes the vertical space between systems (a documented
   limitation), so several systems on one image clash. Instead we render a full page — where LilyPond
   spaces the systems correctly — and then crop the SVG's viewBox to the inked content ourselves. If
   anything about that path fails we fall back to plain ``-dcrop`` (systems may clash, render succeeds).

2. Text. LilyPond emits lyrics, dynamics and tuplet numbers as SVG ``<text>``, which ThorVG cannot draw.
   We outline them to ``<path>`` via the shared svg_text_to_path module (best-effort: a missing fontTools
   only leaves the text unoutlined, never blank).

Two modes:
  * Single image (default): one tall page, ``\\pageBreak`` -> ``\\break``, one ``<stem>.cropped.svg``.
  * Paged (``--paged <pageHeight>``): keep ``\\pageBreak``, a finite page height from <pageHeight>, so
    LilyPond emits one SVG per page; each is cropped to content at a uniform width, written
    ``<stem>-1.cropped.svg``, ``<stem>-2.cropped.svg``, ...  If the paged path fails we fall back to the
    single-image render (so a render is never blank).

Usage:  python lily_render.py <lilypond_exe> <input.ly> <output_stem> [--paged <pageHeight>]
"""
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
# A page tall enough for any realistic single-image score (empty space below is cropped away), with a
# controlled inter-system distance — full-page layout respects system-system-spacing (unlike -dcrop).
FULLPAGE_PAPER = ("\n\\paper { page-count = #1 paper-height = 12000\\mm ragged-bottom = ##t"
                  " ragged-last-bottom = ##t system-system-spacing.basic-distance = #12"
                  " system-system-spacing.padding = #2 }\n")
# Paged mode uses a finite page height derived from the Verovio-style pageHeight (units). The default
# 1200 maps to ~250 mm (A4-ish content height); smaller pageHeight => shorter pages => more pages.
PAGED_SPACING = ("ragged-bottom = ##t ragged-last-bottom = ##t"
                 " system-system-spacing.basic-distance = #12 system-system-spacing.padding = #2")
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


def _measure(svg_path):
    """Parse svg_path and return (tree, root, minx, miny, maxx, maxy, mm_per_unit) or None."""
    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    tree = ET.parse(svg_path)
    root = tree.getroot()
    vb = (root.get("viewBox") or "").split()
    width_mm = float(re.sub(r"[a-z]+$", "", root.get("width", "0")))
    if len(vb) != 4 or width_mm <= 0.0:
        return None
    denom = float(vb[2])
    mm_per_unit = width_mm / denom if denom else 0.0
    bbox = _content_bbox(root)
    if bbox is None or mm_per_unit <= 0.0:
        return None
    return (tree, root, bbox[0], bbox[1], bbox[2], bbox[3], mm_per_unit)


def _write_cropped(meas, out_path, view_width=None):
    """Rewrite a measured SVG's viewBox/width/height to its content (plus margin) and save. When
    view_width (in viewBox units, margins included) is given, use it as the viewBox width instead of the
    content width — so several pages share one width and stay left-aligned. Returns True on success."""
    tree, root, minx, miny, maxx, maxy, mm_per_unit = meas
    m = CROP_MARGIN
    x0, y0 = minx - m, miny - m
    w = ((maxx - minx) + 2 * m) if view_width is None else view_width
    h = (maxy - miny) + 2 * m
    if w <= 0.0 or h <= 0.0:
        return False
    root.set("viewBox", "%.4f %.4f %.4f %.4f" % (x0, y0, w, h))
    root.set("width", "%.4fmm" % (w * mm_per_unit))
    root.set("height", "%.4fmm" % (h * mm_per_unit))
    tree.write(out_path, encoding="unicode")
    return True


def _crop_to_content(svg_path, out_path):
    """Single-image crop: viewBox -> content, saved to out_path. Returns True on success."""
    meas = _measure(svg_path)
    return bool(meas) and _write_cropped(meas, out_path)


def _crop_pages(page_svgs, stem):
    """Crop each page SVG to content at a uniform (max) width; write <stem>-<i>.cropped.svg (1-based).
    Returns the list of written paths, or [] if any page could not be measured (caller falls back)."""
    measured = [_measure(sp) for sp in page_svgs]
    if any(m is None for m in measured):
        return []
    common_w = max((mx - mnx) for (_t, _r, mnx, _mny, mx, _mxy, _mm) in measured) + 2 * CROP_MARGIN
    out_paths = []
    for i, meas in enumerate(measured, start=1):
        out = "%s-%d.cropped.svg" % (stem, i)
        if not _write_cropped(meas, out, view_width=common_w):
            return []
        out_paths.append(out)
    return out_paths


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


def _page_svgs(stem):
    """LilyPond writes <stem>-1.svg.. for multi-page and <stem>.svg for a single page. Return the list
    of page SVGs in order (possibly one), or [] if none were produced."""
    if os.path.exists(stem + "-1.svg"):
        pages, i = [], 1
        while os.path.exists("%s-%d.svg" % (stem, i)):
            pages.append("%s-%d.svg" % (stem, i)); i += 1
        return pages
    if os.path.exists(stem + ".svg"):
        return [stem + ".svg"]
    return []


def _render_paged(lilypond, src, stem, paged_height):
    """Render src (with \\pageBreak kept) onto finite pages and crop each. Returns written cropped paths,
    or [] on any failure (so the caller falls back to a single image)."""
    mm = max(80.0, paged_height * 250.0 / 1200.0)
    paper = "\n\\paper { paper-height = %.1f\\mm %s }\n" % (mm, PAGED_SPACING)
    render_ly = stem + ".render.ly"
    try:
        with open(render_ly, "w", encoding="utf-8") as f:
            f.write(src + paper)
    except Exception as e:
        sys.stderr.write("lily_render: could not write paged source (%s)\n" % e)
        return []
    if _run(lilypond, ["-dbackend=svg", "-o", stem, render_ly]) != 0:
        return []
    pages = _page_svgs(stem)
    if not pages:
        return []
    return _crop_pages(pages, stem)


def _render_single(lilypond, raw, inp, stem):
    """Existing single-image behaviour: \\pageBreak -> \\break, full page + custom crop, else -dcrop."""
    cropped = stem + ".cropped.svg"
    src = None
    preview = inp
    if raw is not None:
        src = raw.replace("\\pageBreak", "\\break")
        preview = stem + ".preview.ly"
        try:
            with open(preview, "w", encoding="utf-8") as f:
                f.write(src)
        except Exception as e:
            sys.stderr.write("lily_render: could not write preview (%s)\n" % e)

    ok = False
    if src is not None:
        try:
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

    if not ok:
        rc = _run(lilypond, ["-dbackend=svg", "-dcrop=#t", "-o", stem, preview])
        if rc != 0:
            return rc
        if not os.path.exists(cropped):
            sys.stderr.write("lily_render: no cropped SVG produced\n")
            return 1

    _text_to_path(cropped)
    sys.stdout.write("lily_render: wrote %s (%s)\n" % (cropped, "full-page crop" if ok else "-dcrop fallback"))
    return 0


def main() -> int:
    argv = sys.argv[1:]
    paged_height = None
    if "--paged" in argv:
        i = argv.index("--paged")
        try:
            paged_height = float(argv[i + 1])
        except (IndexError, ValueError):
            sys.stderr.write("lily_render: --paged needs a numeric page height\n")
            return 2
        argv = argv[:i] + argv[i + 2:]
    if len(argv) < 3:
        sys.stderr.write("lily_render: usage: lily_render.py <lilypond_exe> <input.ly> <output_stem> "
                         "[--paged <pageHeight>]\n")
        return 2
    lilypond, inp, stem = argv[0], argv[1], argv[2]

    try:
        with open(inp, encoding="utf-8") as f:
            raw = f.read()
    except Exception as e:
        raw = None
        sys.stderr.write("lily_render: could not read source (%s)\n" % e)

    if paged_height is not None and raw is not None:
        outs = _render_paged(lilypond, raw, stem, paged_height)   # keeps \pageBreak
        if outs:
            for o in outs:
                _text_to_path(o)
            sys.stdout.write("lily_render: wrote %d page(s) %s-N.cropped.svg\n" % (len(outs), stem))
            return 0
        sys.stderr.write("lily_render: paged render failed; falling back to single image\n")

    return _render_single(lilypond, raw, inp, stem)


if __name__ == "__main__":
    raise SystemExit(main())
