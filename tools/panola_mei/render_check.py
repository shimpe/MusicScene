"""Render an MEI string or .mei file via the bundled Verovio wrapper and report structural props.
Usage:  py tools/panola_mei/render_check.py <file.mei>   (exit 0 = renders OK)
Import: from tools.panola_mei.render_check import render_props
"""
import sys, subprocess, os, tempfile

_WRAP = os.path.join(os.path.dirname(__file__), "..", "..",
                     "addons", "musicscene", "tools", "verovio_render.py")

def render_props(mei_or_path: str) -> dict:
    mei = mei_or_path
    if len(mei_or_path) < 260 and os.path.exists(mei_or_path):
        mei = open(mei_or_path, encoding="utf-8").read()
    with tempfile.TemporaryDirectory() as d:
        inp, outp = os.path.join(d, "s.mei"), os.path.join(d, "s.svg")
        open(inp, "w", encoding="utf-8").write(mei)
        r = subprocess.run(["py", _WRAP, inp, outp, "--page", "1"],
                           capture_output=True, text=True)
        svg = open(outp, encoding="utf-8").read() if os.path.exists(outp) else ""
    return {
        "ok": r.returncode == 0 and "<svg" in svg,
        "rc": r.returncode, "stderr": r.stderr,
        "treble": svg.count("E050"), "bass": svg.count("E062"),   # G-clef / F-clef glyphs
        "measures": mei.count("<measure "),
        "ties": ('tie="i"' in mei) or ('tie="t"' in mei),
        "sharps": svg.count("E262"), "flats": svg.count("E260"),
        "beams": svg.count('class="beam"'), "flag_glyphs": svg.count('class="flag"'),
        "tuplets": mei.count("<tuplet "),
        "dynam": mei.count("<dynam "), "artics": mei.count(' artic="'),
    }

if __name__ == "__main__":
    p = render_props(sys.argv[1])
    print(p)
    sys.exit(0 if p["ok"] else 1)
