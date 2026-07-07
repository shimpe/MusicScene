"""SP2b meter-aware notation tests: PanolaMeterSplitter wired into PanolaMEI's non-tuplet path.
Generates MEI via sclang, asserts on the MEI XML (note/tie counts) and that it renders.
Run:  py -m pytest tools/panola_mei/test_meter_notation.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    """Run sclang, return the MEI string produced by `expr` (a scoreAsMEI/asMEI call)."""
    d = tempfile.mkdtemp(prefix="panola_meter_")
    try:
        path = (d.replace("\\", "/") + "/s.mei")
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd")
        open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


def _notes(mei):   # count <note ...> elements (not <notedef> etc.)
    return len(re.findall(r"<note[ />]", mei))


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_mid_measure_half_note_splits_at_the_4_4_midpoint():
    # c5_4 c5_2 c5_4 in 4/4: the middle half note starts on beat 2 and spans the 2.0 half-measure
    # boundary, so it must split into two tied quarters (quarter + quarter~) rather than one half note.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4 c5_2 c5_4")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert _notes(mei) == 4, mei              # q + (q~q) + q  (was 3: q + half + q)
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_offbeat_quarter_splits_into_tied_eighths():
    # c5_8 c5_4 c5_8 in 2/4: the quarter starts on the off-beat (0.5) and spans beat 1.0, so it
    # splits into two tied eighths -> eighth + (eighth~eighth) + eighth = 4 notes.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8 c5_4 c5_8")], [( measure: 1, meter: "2/4", key: \\Cmajor )], [\\treble], nil)')
    assert _notes(mei) == 4, mei
    assert 'tie="i"' in mei and 'tie="t"' in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_half_notes_on_strong_beats_are_not_over_split():
    # c5_2 c5_2 in 4/4: each half note starts on a boundary at least as strong as any it spans
    # (onset 0 -> 100, onset 2 -> 80), so neither is split -> 2 plain half notes, no ties.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_2 c5_2")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert _notes(mei) == 2, mei
    assert 'tie="i"' not in mei and 'tie="t"' not in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_dotted_quarter_on_downbeat_stays_whole():
    # c5_4. c5_8 in 4/4: the dotted quarter is on beat 1 (onset 0) and spans only the weaker beat-1
    # boundary, so it stays a single dotted quarter (dur="4" dots="1"), not split.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4. c5_8")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert re.search(r'<note dur="4" dots="1"', mei), mei
    assert 'tie="i"' not in mei, mei
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_explicit_tuplet_path_unchanged():
    # a triplet (c5_4*2/3 = 3 quarters in the space of 2) still renders through the unchanged atomic
    # tuplet path -> one <tuplet num="3" numbase="2"> with three written quarters.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], [( measure: 1, meter: "4/4", key: \\Cmajor )], [\\treble], nil)')
    assert '<tuplet num="3" numbase="2">' in mei, mei
    assert mei.count('<note dur="4"') == 3, mei
    assert render_props(mei)["ok"], mei
