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


# --- full-render lyrics via PanolaMEI.scoreAsMEI ------------------------------------------------
# 5 quarter-ish notes so "Twin-kle twin-kle star" (5 syllables) fills them; g5_2 is a half note.
V = r'Panola("c5_4 d5 e5 f5 g5_2")'
CHG = r'[( measure: 1, meter: "4/4", key: \Cmajor )]'

CASES = {
  # one verse, hyphens -> wordpos + con; last word single-syllable
  "basic":   r'PanolaMEI.scoreAsMEI([%s], %s, [\treble], nil, nil, nil, [[ "Twin-kle twin-kle star" ]])' % (V, CHG),
  # a rest is skipped (no syllable under it): "a b" aligns to the two notes, not the rest
  "rest":    r'PanolaMEI.scoreAsMEI([Panola("c5_4 r d5_4")], %s, [\treble], nil, nil, nil, [[ "a b" ]])' % CHG,
  # melisma: "joy" then two held notes -> only ONE <verse>, on note 1
  "melisma": r'PanolaMEI.scoreAsMEI([Panola("c5_4 d5 e5 f5")], %s, [\treble], nil, nil, nil, [[ "joy _ _ end" ]])' % CHG,
  # two verses -> two <verse> per sung note, n="1" and n="2"
  "verses":  r'PanolaMEI.scoreAsMEI([%s], %s, [\treble], nil, nil, nil, [[ "one two three four five", "un deux trois qua-tre" ]])' % (V, CHG),
  # a note tied across a barline: syllable on the FIRST fragment only. c5 lasts 6 quarters (> one 4/4 bar)
  "tied":    r'PanolaMEI.scoreAsMEI([Panola("c5_1.. d5_2")], %s, [\treble], nil, nil, nil, [[ "held done" ]])' % CHG,
  # XML-escape + literal quote via backslash: syllable  "Oh,"  contains quotes and needs no & but proves escaping path
  "escape":  r'PanolaMEI.scoreAsMEI([Panola("c5_4 d5")], %s, [\treble], nil, nil, nil, [[ "R\\&B \\\"Oh,\\\"" ]])' % CHG,
  # a chord gets its syllable INSIDE <chord> (after the note children, before </chord>)
  "chordlyr": r'PanolaMEI.scoreAsMEI([Panola("<c5_4 e5 g5> d5")], %s, [\treble], nil, nil, nil, [[ "chord next" ]])' % CHG,
  # byte-identity control: same voice, NO lyrics
  "nolyr":   r'PanolaMEI.scoreAsMEI([%s], %s, [\treble], nil, nil, nil, nil)' % (V, CHG),
  "nolyr2":  r'PanolaMEI.scoreAsMEI([%s], %s, [\treble])' % (V, CHG),
}


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_lyrics_render():
    outdir = tempfile.mkdtemp(prefix="panola_lyr_")
    try:
        _dump(outdir, CASES)
        meis = {k: open(os.path.join(outdir, k + ".mei"), encoding="utf-8").read() for k in CASES}
    finally:
        shutil.rmtree(outdir, ignore_errors=True)

    # every lyric MEI must still render in Verovio
    for k in ("basic", "rest", "melisma", "verses", "tied", "escape", "chordlyr"):
        assert render_props(meis[k])["ok"], k

    b = meis["basic"]
    assert b.count("<syl") == 5
    assert '<syl wordpos="i" con="d">Twin</syl>' in b
    assert '<syl wordpos="t">kle</syl>' in b
    assert '<syl>star</syl>' in b            # single-syllable word: no wordpos/con

    assert meis["rest"].count("<syl") == 2   # the rest consumed no syllable
    assert '<rest' in meis["rest"] and 'rest><syl' not in meis["rest"].replace(" ", "")

    assert meis["melisma"].count("<verse") == 2   # note 1 "joy" + note 4 "end"; notes 2-3 held
    assert '<syl>joy</syl>' in meis["melisma"]

    assert '<verse n="1">' in meis["verses"] and '<verse n="2">' in meis["verses"]
    assert meis["verses"].count('<verse n="2">') == 5

    assert meis["tied"].count("<syl>held</syl>") == 1   # first fragment only, not on the tied continuation

    assert meis["chordlyr"].count("<syl") == 2
    assert '<syl>chord</syl>' in meis["chordlyr"]
    assert '<verse n="1"><syl>chord</syl></verse></chord>' in meis["chordlyr"]   # verse nested in the chord, before </chord>
    assert '<syl>next</syl>' in meis["chordlyr"]

    assert '<syl>R&amp;B</syl>' in meis["escape"]        # & escaped
    assert '<syl>"Oh,"</syl>' in meis["escape"]          # backslash-escaped quotes are literal

    # byte-identity: lyrics nil renders exactly like the positional-default form
    assert meis["nolyr"] == meis["nolyr2"]
    assert "<verse" not in meis["nolyr"]
