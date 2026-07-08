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
