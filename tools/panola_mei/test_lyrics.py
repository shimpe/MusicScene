"""Lyrics tests for Panola.scoreAsMEI (PanolaMEI): the pure tokenizer *pr_parseLyricLine
and full MEI <verse>/<syl> emission. Run:
  py -m pytest tools/panola_mei/test_lyrics.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.test_expression import _dump, SCLANG
from tools.panola_mei.render_check import render_props


def _tok(sc_literal):
    """Run PanolaMEI.pr_parseLyricLine(<sc_literal>) and return the canonical token string.
    Each slot renders as  syl|wordpos|con  (- for a nil wordpos/con), a melisma as  _ ."""
    script = (
        "(\n"
        "~fmt = { |line| PanolaMEI.pr_parseLyricLine(line).collect({ |s|\n"
        '  (s[\\melisma] == true).if({ "_" }, { s[\\syl] ++ "|" ++ (s[\\wordpos] ? "-") ++ "|" ++ (s[\\con] ? "-") }) }).join(" ") };\n'
        '("TOK:" ++ ~fmt.(' + sc_literal + ')).postln; 0.exit;\n'
        ")\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script); path = f.name
    try:
        r = subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    line = [l for l in r.stdout.splitlines() if l.startswith("TOK:")]
    assert line, r.stdout[-1500:]
    return line[0][4:]


# each case: (SuperCollider string LITERAL, expected canonical token string)
TOK_CASES = {
    "hyphen":   (r'"Twin-kle twin-kle lit-tle star,"',
                 "Twin|i|d kle|t|- twin|i|d kle|t|- lit|i|d tle|t|- star,|-|-"),
    "melisma":  (r'"joy _ _ to the world"',
                 "joy|-|- _ _ to|-|- the|-|- world|-|-"),
    "three":    (r'"al-le-lu-ia"', "al|i|d le|m|d lu|m|d ia|t|-"),
    "escspace": (r'"two\\ words done"', "two words|-|- done|-|-"),
    "escunder": (r'"held\\_note"', "held_note|-|-"),
    "apos":     (r'"don\'t sayin\'"', "don't|-|- sayin'|-|-"),
    "eschyphen": (r'"rock\\-n\\-roll done"', "rock-n-roll|-|- done|-|-"),
    "dblunder":  (r'"__ end"', "__|-|- end|-|-"),
    "crlf":      (r'"a\rb"', "a|-|- b|-|-"),
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
@pytest.mark.parametrize("key", list(TOK_CASES))
def test_tokenizer(key):
    sc_literal, expected = TOK_CASES[key]
    assert _tok(sc_literal) == expected


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_xml_escape():
    script = (
        "(\n"
        '("XML:" ++ PanolaMEI.pr_xmlEscape("a & b < c > d")).postln; 0.exit;\n'
        ")\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script); path = f.name
    try:
        r = subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    assert "XML:a &amp; b &lt; c &gt; d" in r.stdout, r.stdout[-1500:]
