// =============================================================================
// Two-hand generative score — a SuperCollider showcase for MusicScene's LIVE notation.
//
// Two independent random "patterns" — a right hand and a left hand — invent notes and
// rhythms one bar at a time. Every bar, the program sends the LAST FOUR MEASURES of each
// hand to MusicScene as ABC, so you watch the score being written in real time while
// sclang plays it. Nothing exotic: notes come from a C-major pool with gentle stepwise
// motion, rhythms are plain (eighths, quarters, dotted quarters, halves).
//
//     right hand -> /ms/scene/rh   (treble staff)
//     left  hand -> /ms/scene/lh   (bass staff)
//
// The two staves are SEPARATE notation objects stacked like a piano grand staff. Verovio's
// ABC importer is single-voice, so one ABC string = one staff — two hands = two objects,
// the right one in treble clef, the left in bass clef (`K:C clef=bass`).
//
// Every sound is synthesised locally (a soft additive tone), so no external synth is needed:
// sclang generates the music, DRAWS it over OSC, and PLAYS it.
//
// REQUIRES MusicScene with Verovio notation working — `pip install verovio` (MEI/ABC engrave
// with zero config). Set ~space below to match your project's `musicscene/space`.
//
// USAGE:
//   1. Boot the audio server (evaluating the block below does it).
//   2. Run the Godot project with MusicScene (exactly ONE instance).
//   3. Put the cursor in the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. Two staves appear and fill in four bars at a time, scrolling as the music plays.
//   5. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

    // A soft, slightly bell-like piano voice: three sine partials, a gentle tail, a
    // touch of reverb. Amplitude/pan come from the caller (left vs right hand).
    SynthDef(\pnote, { |freq = 440, amp = 0.15, pan = 0|
        var env  = EnvGen.kr(Env.perc(0.004, 1.2, 1, -4.5), doneAction: 2);
        var tone = SinOsc.ar(freq) + (SinOsc.ar(freq * 2) * 0.35) + (SinOsc.ar(freq * 3) * 0.12);
        var sig  = tone * env * amp;
        sig = sig + (FreeVerb.ar(sig, 0.3, 0.7, 0.4) * 0.35);
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    s.sync;

    // ---- configuration ------------------------------------------------------
    ~engine = NetAddr("127.0.0.1", 7400);        // where MusicScene listens
    ~snd    = { |... m| ~engine.sendMsg(*m); 0.02.wait; };   // paced send (Routine-only)

    ~space  = "2d";   // <-- set to "3d" if your project runs MusicScene in 3D
    ~bpm    = 84;     // tempo (quarter = 1 beat, 4 beats per 4/4 bar)

    // C-major note pools (MIDI). Right hand sings in the treble, left hand walks the bass.
    ~rhPool = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81];   // C4 .. A5
    ~lhPool = [40, 41, 43, 45, 47, 48, 50, 52, 53, 55, 57, 59];       // E2 .. B3
    // Rhythm palettes, in beats. RH leans faster (eighths/quarters), LH slower (quarters/halves).
    ~rhRhythm = [0.5, 0.5, 0.5, 1, 1, 1.5, 2];
    ~lhRhythm = [1, 1, 2, 2, 1.5, 0.5];
    ~restProb = 0.12;   // chance any event is a rest

    // MIDI pitch-class -> ABC letter (C major only, so no accidentals are ever needed).
    ~pcLetter = ["C", nil, "D", nil, "E", "F", nil, "G", nil, "A", nil, "B"];

    // ---- ABC helpers --------------------------------------------------------

    // MIDI note -> ABC pitch token. Middle C (60) = "C"; up an octave = "c", "c'"; down = "C,", "C,,".
    ~abcPitch = { |midi|
        var pc   = midi % 12;
        var oct  = (midi / 12).floor.asInteger - 1;
        var base = ~pcLetter[pc] ? "C";
        if(oct >= 5) {
            base.toLower ++ ("'" ! (oct - 5)).join;
        } {
            base ++ ("," ! (4 - oct)).join;
        };
    };

    // One event [dur, midi-or-nil] -> ABC token, e.g. [1.0, 67] -> "G2", [0.5, nil] -> "z".
    // With L:1/8 the length number is the note's duration measured in eighths (dur / 0.5).
    ~abcTok = { |dur, midi|
        var len   = (dur / 0.5).round.asInteger;
        var pitch = midi.isNil.if({ "z" }, { ~abcPitch.(midi) });
        pitch ++ (len == 1).if({ "" }, { len.asString });
    };

    ~barToAbc = { |bar| bar.collect({ |ev| ~abcTok.(ev[0], ev[1]) }).join(" ") };

    // A rolling window of bars -> a complete little ABC tune for one hand.
    ~windowAbc = { |win, clef|
        var head = "X:1\nM:4/4\nL:1/8\nK:C" ++ (clef == \bass).if({ " clef=bass" }, { "" }) ++ "\n";
        head ++ win.collect({ |bar| ~barToAbc.(bar) }).join(" | ") ++ " |]";
    };

    // ---- the two generative "patterns" -------------------------------------

    // Generate one 4/4 bar for a hand: fill exactly 4 beats with random durations from the
    // hand's palette; each event is a rest (~restProb) or a note that steps near the previous
    // one (a small random walk over the pool -> melodic, not jumpy).
    ~genBar = { |hand|
        var isRh    = (hand == \rh);
        var pool    = isRh.if({ ~rhPool }, { ~lhPool });
        var rhythms = isRh.if({ ~rhRhythm }, { ~lhRhythm });
        var remaining = 4.0;
        var bar = [];
        while { remaining > 0.001 } {
            var dur  = rhythms.select({ |d| d <= (remaining + 0.001) }).choose;
            var midi = nil;
            if(~restProb.coin.not) {
                var idx = isRh.if({ ~rhIdx }, { ~lhIdx });
                idx = (idx + [-2, -1, -1, 1, 1, 2, -3, 3].choose).clip(0, pool.size - 1);
                isRh.if({ ~rhIdx = idx }, { ~lhIdx = idx });
                midi = pool[idx];
            };
            bar = bar.add([dur, midi]);
            remaining = remaining - dur;
        };
        bar;
    };

    // Play one bar (fork a short routine so both hands sound together, on the shared clock).
    ~playBar = { |bar, pan, amp|
        Routine({
            bar.do({ |ev|
                if(ev[1].notNil) { Synth(\pnote, [\freq, ev[1].midicps, \amp, amp, \pan, pan]) };
                ev[0].wait;
            });
        }).play(~clock);
    };

    // ---- build the two staves, then run the conductor -----------------------
    ~build = Routine({
        ~snd.("/ms/scene", "reset");

        ["rh", "lh"].do({ |id|
            ~snd.("/ms/scene/" ++ id, "new", "notation");
            ~snd.("/ms/scene/" ++ id, "background", "white");     // opaque paper behind the ink
        });

        // Stack right hand above left hand. (If they come out swapped, flip the two y values.)
        if(~space == "3d") {
            ~snd.("/ms/scene/rh", "pos", 0.0,  0.7, 0.0);  ~snd.("/ms/scene/rh", "scale", 0.30);
            ~snd.("/ms/scene/lh", "pos", 0.0, -0.7, 0.0);  ~snd.("/ms/scene/lh", "scale", 0.30);
        } {
            ~snd.("/ms/scene/rh", "pos", 0.5, 0.34);       ~snd.("/ms/scene/rh", "scale", 0.45);
            ~snd.("/ms/scene/lh", "pos", 0.5, 0.60);       ~snd.("/ms/scene/lh", "scale", 0.45);
        };

        // fresh state
        if(~conductor.notNil) { ~conductor.stop };
        if(~clock.notNil)     { ~clock.stop };
        ~clock = TempoClock(~bpm / 60);
        ~rhWin = []; ~lhWin = [];
        ~rhIdx = (~rhPool.size / 2).floor.asInteger;   // start each walk mid-range
        ~lhIdx = (~lhPool.size / 2).floor.asInteger;

        // The conductor: each bar, both hands invent a measure; keep only the last 4; send each
        // hand's window as ABC; play the new bar. Direct sendMsg (no pacing) keeps timing exact.
        ~conductor = Routine({
            loop {
                var rhBar = ~genBar.(\rh);
                var lhBar = ~genBar.(\lh);
                ~rhWin = (~rhWin ++ [rhBar]).keep(-4);
                ~lhWin = (~lhWin ++ [lhBar]).keep(-4);
                ~engine.sendMsg("/ms/scene/rh", "notationData", "abc", ~windowAbc.(~rhWin, \treble));
                ~engine.sendMsg("/ms/scene/lh", "notationData", "abc", ~windowAbc.(~lhWin, \bass));
                ~playBar.(rhBar, 0.22, 0.13);
                ~playBar.(lhBar, -0.22, 0.16);
                4.wait;                       // one 4/4 bar
            };
        }).play(~clock);

        "".postln;
        "Two-hand generative score running — the staves scroll four bars at a time.".postln;
        "Evaluate the CLEANUP block to stop.".postln;
        "".postln;
    });
    ~build.play;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
if(~conductor.notNil) { ~conductor.stop };
if(~clock.notNil)     { ~clock.stop };
~engine.sendMsg("/ms/scene", "clear");
"Two-hand score stopped.".postln;
)
