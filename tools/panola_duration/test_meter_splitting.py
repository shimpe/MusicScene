"""SP2a meter-splitting tests for the Panola quark (PanolaMeter + PanolaMeterSplitter).
Pure sclang value computation -- no server. Run:
  py -m pytest tools/panola_duration/test_meter_splitting.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, pytest

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")


def _run(script):
    with tempfile.NamedTemporaryFile("w", suffix=".scd", delete=False, encoding="utf-8") as f:
        f.write(script)
        path = f.name
    try:
        return subprocess.run([SCLANG, path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)


# format a meter's boundaries as "off@strength" tokens joined by ; (offsets as num/den)
METER_SCRIPT = r'''(
var fmt = { |m| m.boundaries.collect({ |b| b[\offsetQL].asString ++ "@" ++ b[\strength] }).join(";") };
("M44:" ++ fmt.(PanolaMeter(4, 4))).postln;
("M34:" ++ fmt.(PanolaMeter(3, 4))).postln;
("M68:" ++ fmt.(PanolaMeter(6, 8))).postln;
("M78:" ++ fmt.(PanolaMeter(7, 8, [2,2,3]))).postln;
("LEN44:" ++ PanolaMeter(4,4).measureLengthQL.asString).postln;
("LEN68:" ++ PanolaMeter(6,8).measureLengthQL.asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_meter_boundaries():
    r = _run(METER_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "LEN44:4/1" in r.stdout, r.stdout[-1500:]
    assert "LEN68:3/1" in r.stdout, r.stdout[-1500:]
    # 4/4: 0@100 0.5@30 1@60 1.5@30 2@80 2.5@30 3@60 3.5@30 4@100
    assert "M44:0/1@100;1/2@30;1/1@60;3/2@30;2/1@80;5/2@30;3/1@60;7/2@30;4/1@100" in r.stdout, r.stdout[-1500:]
    # 3/4: 0@100 1@60 2@60 3@100 (+ subdivisions 0.5,1.5,2.5 @30)
    assert "M34:0/1@100;1/2@30;1/1@60;3/2@30;2/1@60;5/2@30;3/1@100" in r.stdout, r.stdout[-1500:]
    # 6/8: 0@100 0.5@40 1@40 1.5@70 2@40 2.5@40 3@100
    assert "M68:0/1@100;1/2@40;1/1@40;3/2@70;2/1@40;5/2@40;3/1@100" in r.stdout, r.stdout[-1500:]
    # 7/8 [2,2,3]: 0@100 0.5@40 1@75 1.5@40 2@75 2.5@40 3@40 3.5@100
    assert "M78:0/1@100;1/2@40;1/1@75;3/2@40;2/1@75;5/2@40;3/1@40;7/2@100" in r.stdout, r.stdout[-1500:]


# format a split as "type.dots/tie" components joined by + ; tie = F(from) N(to) B(both) -(none)
SPLIT_FMT = r'''
var fmtComp = { |c|
    var sp = c[\spelling], tie;
    tie = (c[\tieFromPrevious] and: { c[\tieToNext] }).if({ "B" },
        { c[\tieFromPrevious].if({ "F" }, { c[\tieToNext].if({ "N" }, { "-" }) }) });
    sp[\inexpressible].if({ "INEXPR" }, {
        sp[\components].collect({ |x|
            var t = x[\tuplets];
            x[\type].asString ++ "." ++ x[\dots] ++ (t.isEmpty.if({ "" }, { "[" ++ t[0][\actual] ++ ":" ++ t[0][\normal] ++ "]" }));
        }).join(",") ++ "/" ++ tie;
    });
};
var fmt = { |comps| comps.collect(fmtComp).join("+") };
var ev = { |onN, onD, durN, durD, isRest = false|
    ( onsetQL: PanolaRational(onN, onD), durationQL: PanolaRational(durN, durD), isRest: isRest );
};
'''

BASIC_SPLIT_SCRIPT = r'''(''' + SPLIT_FMT + r'''
("E1:"    ++ fmt.(PanolaMeterSplitter.split(ev.(3,2, 1,1), PanolaMeter(4,4)))).postln;   // 1.5,1.0 -> e+e
("HALF:"  ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 2,1), PanolaMeter(4,4)))).postln;   // 0,2   -> half
("QQ:"    ++ fmt.(PanolaMeterSplitter.split(ev.(1,1, 2,1), PanolaMeter(4,4)))).postln;   // 1,2   -> q+q
("DQ:"    ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 3,2), PanolaMeter(4,4)))).postln;   // 0,1.5 -> dotted q
("E2:"    ++ fmt.(PanolaMeterSplitter.split(ev.(1,1, 1,1), PanolaMeter(6,8)))).postln;   // 1,1   -> e+e (6/8)
("E3:"    ++ fmt.(PanolaMeterSplitter.split(ev.(1,2, 2,1), PanolaMeter(7,8,[2,2,3])))).postln; // 0.5,2 -> e+q+e
("REST:"  ++ fmt.(PanolaMeterSplitter.split(ev.(3,2, 1,1, true), PanolaMeter(4,4)))).postln;   // rest, no ties
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_basic_split():
    r = _run(BASIC_SPLIT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "E1:eighth.0/N+eighth.0/F" in r.stdout, r.stdout[-1500:]      # crosses 2.0 midpoint
    assert "HALF:half.0/-" in r.stdout, r.stdout[-1500:]                 # single half note (onset 100)
    assert "QQ:quarter.0/N+quarter.0/F" in r.stdout, r.stdout[-1500:]    # breaks at 2.0 (80 > 60)
    assert "DQ:quarter.1/-" in r.stdout, r.stdout[-1500:]                # dotted quarter, un-split
    assert "E2:eighth.0/N+eighth.0/F" in r.stdout, r.stdout[-1500:]      # crosses 1.5 compound beat
    assert "E3:eighth.0/N+quarter.0/B+eighth.0/F" in r.stdout, r.stdout[-1500:]  # crosses 1.0 and 2.0 groups
    assert "REST:eighth.0/-+eighth.0/-" in r.stdout, r.stdout[-1500:]    # rest split, NO ties


TUPLET_SPLIT_SCRIPT = r'''(''' + SPLIT_FMT + r'''
var tev = { |onN, onD, durN, durD, tcStartN, tcStartD, tcTotN, tcTotD, act, nrm|
    ( onsetQL: PanolaRational(onN, onD), durationQL: PanolaRational(durN, durD), isRest: false,
      tupletContext: ( startQL: PanolaRational(tcStartN, tcStartD), totalDurationQL: PanolaRational(tcTotN, tcTotD),
                       numberNotesActual: act, numberNotesNormal: nrm ) );
};
// triplet-eighth grid over 1.0..2.0 (3:2). note onset 4/3, dur 2/3 -> two tied triplet eighths.
("T4:" ++ fmt.(PanolaMeterSplitter.split(tev.(4,3, 2,3, 1,1, 1,1, 3,2), PanolaMeter(4,4)))).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_tuplet_split():
    r = _run(TUPLET_SPLIT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "T4:eighth.0[3:2]/N+eighth.0[3:2]/F" in r.stdout, r.stdout[-1500:]  # two tied triplet eighths


FALLBACK_SCRIPT = r'''(''' + SPLIT_FMT + r'''
var sumOK = { |comps, dn, dd|
    comps.inject(PanolaRational(0,1), { |a, c| a + c[\durationQL] }) == PanolaRational(dn, dd);
};
// 1/17 QL at onset 0 in 4/4 is NOT spellable (needs a >13 tuplet) -> drives greedy -> smallest-grid
var one17 = PanolaMeterSplitter.split(ev.(0,1, 1,17), PanolaMeter(4,4));
// sum-exactness across the earlier examples
("SUM1:" ++ sumOK.(PanolaMeterSplitter.split(ev.(3,2, 1,1), PanolaMeter(4,4)), 1, 1).asString).postln;
("SUM3:" ++ sumOK.(PanolaMeterSplitter.split(ev.(1,2, 2,1), PanolaMeter(7,8,[2,2,3])), 2, 1).asString).postln;
// an inexpressible tail piece must not crash: quantize off, an off-grid tail
("OFFGRID:" ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 5,7), PanolaMeter(4,4)))).postln;
("ONE17SUM:" ++ (one17.inject(PanolaRational(0,1), { |a, c| a + c[\durationQL] }) == PanolaRational(1,17)).asString).postln;
("ONE17MANY:" ++ (one17.size > 1).asString).postln;
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_fallback_and_sum():
    r = _run(FALLBACK_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "SUM1:true" in r.stdout, r.stdout[-1500:]     # components sum exactly to the input
    assert "SUM3:true" in r.stdout, r.stdout[-1500:]
    assert "OFFGRID:" in r.stdout, r.stdout[-1500:]      # produced a result, did not crash/hang
    assert "ONE17SUM:true" in r.stdout, r.stdout[-1500:]    # fallback result sums exactly to 1/17
    assert "ONE17MANY:true" in r.stdout, r.stdout[-1500:]   # smallest-grid fallback -> many tied pieces


OPT_SCRIPT = r'''(''' + SPLIT_FMT + r'''
// a dotted quarter that hides a strong boundary (>= dotBoundaryThreshold 80) is re-split; one that
// hides only a weak boundary is kept. onset 1.0 dur 1.5 in 4/4: dotted quarter spans beat-3 midpoint?
// span 1.0-2.5 crosses 2.0 (strength 80) -> the mandatory rule already splits at 2.0, so this yields
// quarter+eighth; assert that (no dotted value hiding the 80-boundary survives).
("NODOT:" ++ fmt.(PanolaMeterSplitter.split(ev.(1,1, 3,2), PanolaMeter(4,4)))).postln;   // -> quarter+eighth
// onset 0.0 dur 1.5: dotted quarter hides only beat-1 (60 < 80) -> kept as a single dotted quarter
("KEEPDOT:" ++ fmt.(PanolaMeterSplitter.split(ev.(0,1, 3,2), PanolaMeter(4,4)))).postln; // -> dotted quarter
0.exit;
)'''


@pytest.mark.skipif(not os.path.exists(SCLANG), reason="sclang not installed")
def test_optimize():
    r = _run(OPT_SCRIPT)
    assert "ERROR" not in r.stdout, r.stdout[-1500:]
    assert "NODOT:quarter.0/N+eighth.0/F" in r.stdout, r.stdout[-1500:]  # dot across the 80-boundary avoided
    assert "KEEPDOT:quarter.1/-" in r.stdout, r.stdout[-1500:]           # dot over a weak boundary kept
