"""Convert SVG <text> elements to <path> glyph outlines.

Verovio emits lyrics/tempo/directions as <text>/<tspan>. Godot's ThorVG rasteriser draws
<path> but NOT <text>, so that text is invisible. This rewrites each <text> into filled
<path> outlines using bundled Tinos faces (Times-metric, matching Verovio's
`Times, serif`), choosing Regular/Bold/Italic from the element's Verovio CSS class.

Robust by design: on any failure (fontTools missing, a face missing, an unparseable SVG)
the ORIGINAL svg string is returned, so a render never breaks. Note glyphs (<use
xlink:href>) and ids are preserved, so note-position parsing is unaffected.
"""
import os, re, sys
import xml.etree.ElementTree as ET

_SVG_NS = "http://www.w3.org/2000/svg"
_XLINK_NS = "http://www.w3.org/1999/xlink"
_FONT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
_FACES = {
    "regular": "Tinos-Regular.ttf",
    "bold": "Tinos-Bold.ttf",
    "italic": "Tinos-Italic.ttf",
}
_face_cache = {}


def _load_face(style):
    """Return {glyphset, cmap, hmtx, upm} for a style, or None if unavailable (cached)."""
    if style in _face_cache:
        return _face_cache[style]
    face = None
    try:
        from fontTools.ttLib import TTFont
        ft = TTFont(os.path.join(_FONT_DIR, _FACES[style]))
        face = {
            "glyphset": ft.getGlyphSet(),
            "cmap": ft.getBestCmap(),
            "hmtx": ft["hmtx"],
            "upm": ft["head"].unitsPerEm,
        }
    except Exception as e:
        sys.stderr.write("svg_text_to_path: cannot load %s: %s\n" % (style, e))
    _face_cache[style] = face
    return face


def _localname(tag):
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def _f(s):
    if s is None:
        return 0.0
    m = re.match(r"\s*(-?[0-9.]+)", str(s))
    return float(m.group(1)) if m else 0.0


def _fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def _parse_css(style_text):
    """(bold_classes, italic_classes) from Verovio's <style> CSS."""
    bold, italic = set(), set()
    for m in re.finditer(r"([^{}]+)\{([^}]*)\}", style_text or ""):
        decls = m.group(2).replace(" ", "")
        b = "font-weight:bold" in decls
        i = "font-style:italic" in decls
        if not (b or i):
            continue
        for cls in re.findall(r"g\.([A-Za-z0-9_-]+)", m.group(1)):
            if b:
                bold.add(cls)
            if i:
                italic.add(cls)
    return bold, italic


def _first_size(text_el):
    """The real font-size: a tspan's (Verovio puts 0px on the outer <text>), else the text's."""
    for el in list(text_el.findall("{%s}tspan" % _SVG_NS)) + [text_el]:
        n = _f(el.get("font-size"))
        if n > 0:
            return n
    return None


def _advance(s, face):
    w = 0.0
    for ch in s:
        g = face["cmap"].get(ord(ch))
        w += face["hmtx"][g][0] if g else face["upm"] * 0.5
    return w


def _text_to_paths(text_el, is_bold, is_italic):
    """List of <path> Elements for a <text>, or None to leave it unchanged."""
    style = "italic" if is_italic else ("bold" if is_bold else "regular")
    face = _load_face(style)
    if face is None:
        return None
    fs = _first_size(text_el)
    if not fs or fs <= 0:
        return None
    s = "".join(text_el.itertext())
    if s.strip() == "":
        return None
    x, y = _f(text_el.get("x")), _f(text_el.get("y"))
    tsp = text_el.find("{%s}tspan" % _SVG_NS)
    if tsp is not None:
        if tsp.get("x") is not None:
            x = _f(tsp.get("x"))
        if tsp.get("y") is not None:
            y = _f(tsp.get("y"))
    scale = fs / face["upm"]
    anchor = text_el.get("text-anchor") or "start"
    if anchor in ("middle", "end"):
        x -= _advance(s, face) * scale * (0.5 if anchor == "middle" else 1.0)
    from fontTools.pens.svgPathPen import SVGPathPen
    out, penx = [], x
    for ch in s:
        g = face["cmap"].get(ord(ch))
        if g is None:
            penx += fs * 0.5
            continue
        pen = SVGPathPen(face["glyphset"])
        face["glyphset"][g].draw(pen)
        d = pen.getCommands()
        if d:
            p = ET.Element("{%s}path" % _SVG_NS)
            p.set("fill", "#000000")
            p.set("transform", "translate(%s %s) scale(%s %s)" % (_fmt(penx), _fmt(y), _fmt(scale), _fmt(-scale)))
            p.set("d", d)
            out.append(p)
        penx += face["hmtx"][g][0] * scale
    return out or None


def _process(el, bold_classes, italic_classes, inh_b, inh_i):
    cls = (el.get("class") or "").split()
    b = inh_b or any(c in bold_classes for c in cls)
    i = inh_i or any(c in italic_classes for c in cls)
    new_kids, changed = [], False
    for child in list(el):
        if _localname(child.tag) == "text":
            ccls = (child.get("class") or "").split()
            paths = _text_to_paths(child,
                                   b or any(c in bold_classes for c in ccls),
                                   i or any(c in italic_classes for c in ccls))
            if paths:
                new_kids.extend(paths)
                changed = True
            else:
                new_kids.append(child)
        else:
            _process(child, bold_classes, italic_classes, b, i)
            new_kids.append(child)
    if changed:
        el[:] = new_kids


def svg_text_to_path(svg):
    """Rewrite <text> -> <path> outlines. Returns the original string on any failure."""
    if "<text" not in svg:
        return svg
    ET.register_namespace("", _SVG_NS)
    ET.register_namespace("xlink", _XLINK_NS)
    try:
        root = ET.fromstring(svg)
    except Exception as e:
        sys.stderr.write("svg_text_to_path: parse failed: %s\n" % e)
        return svg
    if _load_face("regular") is None:        # no fonttools/fonts -> leave unchanged
        return svg
    bold, italic = set(), set()
    for st in root.iter("{%s}style" % _SVG_NS):
        b, i = _parse_css(st.text)
        bold |= b
        italic |= i
    try:
        _process(root, bold, italic, False, False)
        body = ET.tostring(root, encoding="unicode")
    except Exception as e:
        sys.stderr.write("svg_text_to_path: convert failed: %s\n" % e)
        return svg
    decl = ""
    m = re.match(r"\s*(<\?xml[^>]*\?>)", svg)
    if m:
        decl = m.group(1)
    return decl + body
