"""MSScore page navigation + showPage tests (msscore quark).
OSCdef-captures the OSC MSScore emits (engine points at NetAddr.langPort) -- no Godot, no audio.
Run:  py -m pytest tools/msscore/test_show_page.py -q   (skips if sclang absent)
"""
import os, pytest
from tools.msscore.test_midi_routing import _run, SCLANG

NAV_SCRIPT = r'''(
var s, got = List.new;
OSCdef(\capN, { |msg| got.add(msg) }, '/ms/scene/scoreNav');
Routine({
    s = MSScore(voices: ["c5_4 e5 g5 c6"], id: "scoreNav", host: "127.0.0.1", listenPort: NetAddr.langPort);
    s.page(4); 0.1.wait;
    s.nextPage; 0.1.wait;
    s.prevPage; 0.1.wait;
    got.do({ |m|
        if (m[1] == \page) { ("PAGE:" ++ m[2].asString).postln };
        if (m[1] == \nextpage) { "NEXT".postln };
        if (m[1] == \prevpage) { "PREV".postln };
    });
    OSCdef(\capN).free;
    0.exit;
}).play;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_page_navigation():
    r = _run(NAV_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "PAGE:4" in r.stdout, r.stdout[-1500:]
    assert "NEXT" in r.stdout, r.stdout[-1500:]
    assert "PREV" in r.stdout, r.stdout[-1500:]


# showPage: display-only. Emits the same setup as show() but cursor forced OFF, then a `page n`.
# Starts NO playback (player/clock stay nil).
SHOWPAGE_SCRIPT = r'''(
var s, got = List.new, cur = List.new;
OSCdef(\capP, { |msg| got.add(msg) }, '/ms/scene/scorePage');
OSCdef(\capPc, { |msg| cur.add(msg) }, '/ms/scene/scorePage/cursor');
Routine({
    s = MSScore(voices: ["c5_4 e5 g5 c6 d5 f5 a5 c6"], id: "scorePage", showDelay: 0.1,
                host: "127.0.0.1", listenPort: NetAddr.langPort);
    s.showPage(2);
    0.6.wait;
    got.do({ |m| if (m[1] == \page) { ("PAGE:" ++ m[2].asString).postln } });
    cur.do({ |m| if (m[1] == \show) { ("CURSOR:" ++ m[2].asString).postln } });
    ("PLAYER_NIL:" ++ s.player.isNil.asString).postln;
    ("CLOCK_NIL:" ++ s.clock.isNil.asString).postln;
    OSCdef(\capP).free; OSCdef(\capPc).free;
    0.exit;
}).play;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_show_page_display_only():
    r = _run(SHOWPAGE_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "PAGE:2" in r.stdout, r.stdout[-1500:]
    assert "CURSOR:0" in r.stdout, r.stdout[-1500:]
    assert "PLAYER_NIL:true" in r.stdout, r.stdout[-1500:]
    assert "CLOCK_NIL:true" in r.stdout, r.stdout[-1500:]


# showPage must send `page n` PROMPTLY (right after the notation setup), NOT gated behind showDelay.
# If it waits showDelay, the deferred `page n` arrives ~showDelay seconds late and overrides any
# nextPage/prevPage/page(1) the user does in the meantime -- snapping the view back to page n (the
# "stuck on the last page" bug). With a long showDelay the page command must still arrive quickly.
PROMPT_SCRIPT = r'''(
var s, got = List.new;
OSCdef(\capPr, { |msg| got.add(msg) }, '/ms/scene/scorePrompt');
Routine({
    s = MSScore(voices: ["c5_4 e5 g5 c6 d5 f5 a5 c6"], id: "scorePrompt", showDelay: 3.0,
                host: "127.0.0.1", listenPort: NetAddr.langPort);
    s.showPage(2);
    0.5.wait;   // well under showDelay (3.0): page(2) must ALREADY have been sent
    got.do({ |m| if (m[1] == \page) { ("PAGE:" ++ m[2].asString).postln } });
    OSCdef(\capPr).free;
    0.exit;
}).play;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_show_page_sends_page_promptly():
    r = _run(PROMPT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "PAGE:2" in r.stdout, r.stdout[-1500:]   # sent promptly, not after showDelay
