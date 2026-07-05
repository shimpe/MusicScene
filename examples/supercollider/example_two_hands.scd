// =============================================================================
// Two-hand generative score — a SuperCollider showcase for MusicScene's LIVE notation.
//
// Two independent random "patterns" — a right hand and a left hand — invent notes and rhythms.
// Each cycle the program generates a full FOUR-MEASURE page, SHOWS it (sends the whole score at
// once) so it's on screen before it sounds, THEN plays it while a playhead cursor sweeps across the
// staff in time with the music — and repeats with a fresh page. Nothing exotic:
// notes come from a C-major pool with gentle stepwise motion, rhythms are plain (eighths, quarters,
// dotted quarters, halves).
//
// Both hands live in ONE score as a real grand staff — right hand on the treble staff, left hand on
// the bass staff, braced together. Verovio's ABC importer is single-voice, so we emit MEI (Verovio's
// native format) instead of ABC: that lets a single notation object hold both staves, and Verovio
// spaces the grand staff for us. It needs no engraver configuration — `mei` engraves with zero config
// (just `pip install verovio`).
//
//     one grand-staff score -> /ms/scene/score   (treble = R.H., bass = L.H.)
//
// Everything is synthesised locally (a soft additive tone), so no external synth is needed: sclang
// generates the music, DRAWS it over OSC, and PLAYS it.
//
// REQUIRES MusicScene with Verovio notation working — `pip install verovio`. Set ~space below to
// match your project's `musicscene/space`.
//
// USAGE:
//   1. Boot the audio server (evaluating the block below does it).
//   2. Run the Godot project with MusicScene (exactly ONE instance).
//   3. Put the cursor in the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. A four-measure grand staff appears, then plays; the next page appears as that one ends, forever.
//   5. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

    // A soft, slightly bell-like piano voice: three sine partials, a gentle tail, a touch of reverb.
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

    ~space  = "3d";   // "2d" or "3d" — match musicscene/space. 2D reads best (a score is landscape).
    ~bpm    = 84;     // tempo (quarter = 1 beat, 4 beats per 4/4 bar)
    ~lead   = 0;      // beats to show a page before it plays (just long enough to render). 0 = no pause; raise to linger.
    ~scoreScale = (~space == "3d").if({ 2.0 }, { 2.0 });   // grand-staff size — raise to enlarge
    // Where the notes actually sit on the page (measured from Verovio's layout of a 4-bar grand staff
    // with treble+bass clef and 4/4): the first note is at u~0.12 — after the clef/time signature, NOT
    // at the barline — and the music ends near u~0.98. The playhead sweeps between these.
    ~cursorStart = 0.12;
    ~cursorEnd   = 0.98;

    // C-major note pools (MIDI). Right hand sings in the treble, left hand walks the bass.
    ~rhPool = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81];   // C4 .. A5
    ~lhPool = [40, 41, 43, 45, 47, 48, 50, 52, 53, 55, 57, 59];       // E2 .. B3
    // Rhythm palettes, in beats. RH leans faster (eighths/quarters), LH slower (quarters/halves).
    ~rhRhythm = [0.5, 0.5, 0.5, 1, 1, 1.5, 2];
    ~lhRhythm = [1, 1, 2, 2, 1.5, 0.5];
    ~restProb = 0.12;   // chance any event is a rest

    // MIDI pitch-class -> note letter (C major only, so no accidentals are ever needed).
    ~pcLetter = ["C", nil, "D", nil, "E", "F", nil, "G", nil, "A", nil, "B"];

    // ---- MEI helpers: build one grand-staff score --------------------------
    // MEI `dur` is the note value (8=eighth, 4=quarter, 2=half); dur*2 (eighths) indexes this table
    // to [dur-value, dots-attribute].
    ~meiDurs = [nil, ["8", ""], ["4", ""], ["4", " dots=\"1\""], ["2", ""]];

    ~meiNote = { |dur, midi|
        var d = ~meiDurs[(dur * 2).round.asInteger];
        if(midi.isNil) {
            "<rest dur=\"" ++ d[0] ++ "\"" ++ d[1] ++ "/>"
        } {
            var pc  = midi % 12;
            var oct = (midi / 12).floor.asInteger - 1;   // MEI octave: middle C (60) = oct 4
            "<note dur=\"" ++ d[0] ++ "\"" ++ d[1] ++ " oct=\"" ++ oct.asString
                ++ "\" pname=\"" ++ ~pcLetter[pc].toLower ++ "\"/>"
        };
    };

    ~meiLayer = { |bar| bar.collect({ |ev| ~meiNote.(ev[0], ev[1]) }).join };

    // A page = four bars per hand -> one MEI grand staff (staff 1 = treble/RH, staff 2 = bass/LH).
    ~meiScore = { |rhBars, lhBars|
        var body = "";
        rhBars.size.do({ |i|
            body = body
                ++ "<measure n=\"" ++ (i + 1).asString ++ "\">"
                ++ "<staff n=\"1\"><layer n=\"1\">" ++ ~meiLayer.(rhBars[i]) ++ "</layer></staff>"
                ++ "<staff n=\"2\"><layer n=\"1\">" ++ ~meiLayer.(lhBars[i]) ++ "</layer></staff>"
                ++ "</measure>";
        });
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        ++ "<mei xmlns=\"http://www.music-encoding.org/ns/mei\" meiversion=\"4.0.0\">"
        ++ "<music><body><mdiv><score>"
        ++ "<scoreDef meter.count=\"4\" meter.unit=\"4\" key.sig=\"0\">"
        ++ "<staffGrp symbol=\"brace\" bar.thru=\"true\">"
        ++ "<staffDef n=\"1\" lines=\"5\" clef.shape=\"G\" clef.line=\"2\"/>"
        ++ "<staffDef n=\"2\" lines=\"5\" clef.shape=\"F\" clef.line=\"4\"/>"
        ++ "</staffGrp></scoreDef>"
        ++ "<section>" ++ body ++ "</section>"
        ++ "</score></mdiv></body></music></mei>";
    };

    // ---- the two generative "patterns" -------------------------------------

    // Generate one 4/4 bar for a hand: fill exactly 4 beats with random durations from the hand's
    // palette; each event is a rest (~restProb) or a note that steps near the previous one.
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

    // Play a whole page (four bars) for one hand: fork a routine so both hands sound together.
    ~playPage = { |bars, pan, amp|
        Routine({
            bars.do({ |bar|
                bar.do({ |ev|
                    if(ev[1].notNil) { Synth(\pnote, [\freq, ev[1].midicps, \amp, amp, \pan, pan]) };
                    ev[0].wait;
                });
            });
        }).play(~clock);
    };

    // Sweep the playhead left->right across the grand staff over one page (16 beats), in step with
    // playback. Linear in time (Verovio spaces the four bars ~evenly), anchored to the measured note
    // span so the cursor starts ON the first note rather than at the barline.
    ~sweepCursor = {
        Routine({
            var steps = 96;
            var dur   = 16 / steps;                    // beats per step
            var span  = ~cursorEnd - ~cursorStart;
            (steps + 1).do({ |k|
                var u = ~cursorStart + ((k / steps) * span);
                ~engine.sendMsg("/ms/scene/score/cursor", "pos", u, 0.5);
                if(k < steps) { dur.wait };
            });
        }).play(~clock);
    };

    // ---- build the score object, then run the conductor --------------------
    ~build = Routine({
        ~snd.("/ms/scene", "reset");
        ~snd.("/ms/scene/score", "new", "notation");
        ~snd.("/ms/scene/score", "background", "white");
        ~snd.("/ms/scene/score", "scale", ~scoreScale);
        if(~space == "3d") {
            ~snd.("/ms/scene/score", "pos", 0.0, 0.0, 0.0);
        } {
            ~snd.("/ms/scene/score", "pos", 0.0, 0.0);
        };
        ~snd.("/ms/scene/score/cursor", "show", 1);   // a playhead that follows the music

        // fresh state
        if(~conductor.notNil) { ~conductor.stop };
        if(~clock.notNil)     { ~clock.stop };
        ~clock = TempoClock(~bpm / 60);
        ~rhIdx = (~rhPool.size / 2).floor.asInteger;   // start each walk mid-range
        ~lhIdx = (~lhPool.size / 2).floor.asInteger;

        // The conductor: each cycle, invent a fresh 4-measure page for both hands, SHOW the whole
        // grand staff, wait ~lead beats so it renders and can be read, THEN play the four measures.
        ~conductor = Routine({
            loop {
                var rhBars = Array.fill(4, { ~genBar.(\rh) });
                var lhBars = Array.fill(4, { ~genBar.(\lh) });
                ~engine.sendMsg("/ms/scene/score", "notationData", "mei", ~meiScore.(rhBars, lhBars));
                ~engine.sendMsg("/ms/scene/score/cursor", "pos", ~cursorStart, 0.5);   // park the playhead on the first note
                ~lead.wait;                       // show the page before it sounds
                ~playPage.(rhBars, 0.22, 0.13);   // right hand
                ~playPage.(lhBars, -0.22, 0.16);  // left hand
                ~sweepCursor.value;               // playhead follows the music across the page
                16.wait;                          // four 4/4 bars
            };
        }).play(~clock);

        "".postln;
        "Two-hand generative score — a fresh four-measure grand staff is shown, then played.".postln;
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
s.freeAll;                                 // silence any still-sounding synths
~engine.sendMsg("/ms/scene", "clear");
"Two-hand score stopped.".postln;
)
