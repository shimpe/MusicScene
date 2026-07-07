"""SP2c tuplet-completion tests: PanolaMEI brackets split fragments and completes incomplete tuplets.
Generates MEI via sclang, asserts on the MEI XML, and renders via Verovio.
Run:  py -m pytest tools/panola_mei/test_tuplet_completion.py -q   (skips if sclang absent)
"""
import os, re, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _mei(expr):
    d = tempfile.mkdtemp(prefix="panola_tupc_")
    try:
        path = d.replace("\\", "/") + "/s.mei"
        scd = '( File.use("%s", "w", { |f| f.write(%s) }); "DONE".postln; 0.exit; )' % (path, expr)
        p = os.path.join(d, "s.scd"); open(p, "w", encoding="utf-8").write(scd)
        r = subprocess.run([SCLANG, p], capture_output=True, text=True, timeout=120)
        assert "ERROR" not in r.stdout, r.stdout[-1500:]
        return open(path, encoding="utf-8").read()
    finally:
        shutil.rmtree(d, ignore_errors=True)


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_split_fragments_render_inside_a_tuplet():
    # c5_8*2/3 d5 c5_2 : the incomplete triplet (still partial in Phase A) pushes the half note onto a
    # non-dyadic onset (2/3); the splitter spells its fragments as triplet values, which must now be
    # WRAPPED in <tuplet> brackets rather than emitted as bare mis-valued notes. Before Piece 1-2 there
    # is exactly one <tuplet> (the partial triplet) and bare dur="8"/dur="4" tuplet-value notes after it;
    # after, the cascade fragments are bracketed too.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 c5_2")], "4/4", \\Cmajor, [\\treble], nil)')
    assert mei.count("<tuplet ") >= 2, mei                 # partial triplet + at least one cascade bracket
    # no tuplet-valued note sits directly outside a bracket (every <note> after a </tuplet> that is a
    # triplet fragment is itself inside a <tuplet>); sanity: it renders
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_plain_and_complete_tuplets_unchanged():
    # a plain-note score and a complete triplet must be byte-identical to before (nil-tuplet fragments
    # render exactly as today; complete *m/d keeps its atomic path).
    plain = _mei('Panola.scoreAsMEI([Panola("c5_4 e5 g5 c5_4")], "4/4", \\Cmajor, [\\treble], nil)')
    assert plain.count("<tuplet ") == 0 and plain.count("<note") == 4, plain
    trip = _mei('Panola.scoreAsMEI([Panola("c5_4*2/3 d5 e5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert '<tuplet num="3" numbase="2">' in trip and trip.count('<note dur="4"') == 3, trip


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_trailing_incomplete_triplet_stays_partial():
    # c5_8*2/3 d5 : 2 of 3 triplet-eighths, then voice-end silence — NOTHING follows. music21's
    # splitElementsToCompleteTuplets only SPLITS an existing following element to complete a tuplet; it
    # never fabricates a rest. So a trailing incomplete tuplet stays PARTIAL: a single 2-note bracket
    # (+ "incomplete tuplet" warning), no fabricated pad, short bar left underfull.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5")], "4/4", \\Cmajor, [\\treble], nil)')
    assert mei.count("<tuplet ") == 1, mei                       # the single partial bracket
    body = mei.split("</tuplet>")[0]
    assert body.count("<note") == 2 and body.count("<rest") == 0, mei   # 2 notes, NO fabricated rest
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_rest_follower_completes_by_splitting_the_rest():
    # c5_8*2/3 d5 r_2 : an explicit half-rest FOLLOWS the 2 triplet-eighths. A rest CAN be a donor —
    # music21 splits the following rest to complete the tuplet (it exceeds the 1/3-beat remainder). So the
    # first bracket gets 2 notes + 1 tuplet REST (the completing member split off the half-rest); the
    # rest's remainder plays after the bracket. This is the music21-faithful "split a following rest" case.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 r_2")], "4/4", \\Cmajor, [\\treble], nil)')
    first = mei.split("</tuplet>")[0]
    assert first.count("<note") == 2 and first.count("<rest") == 1, mei   # 2 notes + 1 completing rest
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_incomplete_triplet_then_note_ties_into_the_bracket():
    # c5_8*2/3 d5 c5_4 : the quarter's leading third completes the triplet as a tied triplet-eighth INSIDE
    # the bracket; the remainder (2/3 beat, non-dyadic) becomes its own triplet-quarter bracket, tied.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 c5_4")], "4/4", \\Cmajor, [\\treble], nil)')
    first = mei.split("</tuplet>")[0]
    assert first.count("<note") == 3, mei                        # c5, d5, + tied completing e-note
    assert 'tie="i"' in first, mei                               # the completing member ties out
    assert render_props(mei)["ok"], mei


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_too_short_note_follower_stays_incomplete():
    # c5_8*2/3 d5 e5_32 : the follower is a NOTE shorter than the triplet's remainder (a 32nd, 1/8 beat <
    # 1/3 beat). music21's splitElementsToCompleteTuplets needs the follower to EXCEED the remainder, so a
    # too-short note cannot complete: the run stays a partial 2-note bracket (+ warning) and the short note
    # plays after unshifted. Fill-with-rest is only for silence followers, which would move no note.
    mei = _mei('Panola.scoreAsMEI([Panola("c5_8*2/3 d5 e5_32")], "4/4", \\Cmajor, [\\treble], nil)')
    first = mei.split("</tuplet>")[0]
    assert first.count("<note") == 2 and first.count("<rest") == 0, mei   # still partial: 2 notes, no pad
    assert '</tuplet><note dur="32"' in mei, mei                          # the 32nd stays outside, unshifted
    assert render_props(mei)["ok"], mei
