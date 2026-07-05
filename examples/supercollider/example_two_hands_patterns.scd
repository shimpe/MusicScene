// =============================================================================
// Three-part generative score, PATTERN edition — a melody over a two-hand piano, built with the
// SuperCollider PATTERN LIBRARY (Pbrown / Prand / Pwrand / Pseq / Pbind / Ppar) rather than routines,
// in D-flat natural minor.
//
// Three independent "patterns": a pad-like MELODY on top (longer notes), and a right hand + left hand
// beneath it. Each part is a random walk over scale degrees (Pbrown), with a random bar-rhythm each
// measure (Prand over a palette of four-beat rhythms) and occasional rests (Pwrand). Every cycle the
// program pulls a full FOUR-MEASURE page from those pattern streams, shows it as ONE MEI score of THREE
// staves — the melody on top, the piano (right + left hand) braced below — then PLAYS it with a Pbind
// per part (run together by Ppar) while a playhead cursor sweeps across in time. The melody uses a soft
// sustained pad voice; the hands use a bell-like piano.
//
// KEY: "D-flat natural minor" is a theoretical key (eight flats, incl. a double flat), so it is written
// — as always — as its enharmonic equivalent C-SHARP minor: four sharps, the very same pitches.
//
//     one three-staff score -> /ms/scene/score   (melody / right hand / left hand)
//
// Same MusicScene setup as example_two_hands.scd: Verovio via `pip install verovio` (MEI engraves with
// zero config). Set ~space below to match your project's `musicscene/space`.
//
// USAGE:
//   1. Boot the audio server (evaluating the block below does it).
//   2. Run the Godot project with MusicScene (exactly ONE instance).
//   3. Put the cursor in the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. A three-staff page appears and plays with a following cursor, then the next page, forever.
//   5. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

    // The hands: a soft, bell-like piano voice (three sine partials, a gentle tail, a little reverb).
    SynthDef(\pnote, { |freq = 440, amp = 0.15, pan = 0|
        var env  = EnvGen.kr(Env.perc(0.004, 1.2, 1, -4.5), doneAction: 2);
        var tone = SinOsc.ar(freq) + (SinOsc.ar(freq * 2) * 0.35) + (SinOsc.ar(freq * 3) * 0.12);
        var sig  = tone * env * amp;
        sig = sig + (FreeVerb.ar(sig, 0.3, 0.7, 0.4) * 0.35);
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    // The melody: a warm pad — three slightly detuned saws, low-passed, a slow attack/long release
    // (gated, so it sustains for the note's length), and generous reverb.
    SynthDef(\pad, { |freq = 440, amp = 0.1, pan = 0, gate = 1|
        var env = EnvGen.kr(Env.asr(0.4, 1.0, 1.2, \sine), gate, doneAction: 2);
        var sig = VarSaw.ar(freq * [1.0, 1.006, 0.994], 0, 0.4).sum * 0.4;
        sig = LPF.ar(sig, 2200);
        sig = sig * env * amp;
        sig = sig + (FreeVerb.ar(sig, 0.5, 0.9, 0.4) * 0.6);
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    s.sync;

    // ---- configuration ------------------------------------------------------
    ~engine = NetAddr("127.0.0.1", 7400);        // where MusicScene listens
    ~snd    = { |... m| ~engine.sendMsg(*m); 0.02.wait; };   // paced send (Routine-only)

    ~space  = "3d";   // "2d" or "3d" — match musicscene/space. 2D reads best (a score is landscape).
    ~bpm    = 76;     // tempo (quarter = 1 beat, 4 beats per 4/4 bar)
    ~lead   = 0;      // beats to show a page before it plays. 0 = play as it appears; raise to linger.
    ~scoreScale = (~space == "3d").if({ 1.5 }, { 1.5 });   // score size — raise to enlarge (3 staves are tall)
    // Measured first/last note positions for a 4-bar page with a four-sharp key signature.
    ~cursorStart = 0.17;
    ~cursorEnd   = 0.97;

    // ---- scale: D-flat natural minor, written as C-sharp minor (four sharps) ----------------------
    ~semis   = [0, 2, 3, 5, 7, 8, 10];   // natural-minor step pattern (semitones from the tonic)
    ~keySig  = "4s";                     // C-sharp minor key signature
    ~melRoot = 73;                       // C#5/Db5 — melody tonic (degree 0), on top
    ~rhRoot  = 61;                       // C#4/Db4 — right-hand tonic
    ~lhRoot  = 37;                       // C#2/Db2 — left-hand tonic
    ~restProb = 0.10;                    // chance any note position is a rest
    // MIDI pitch-class -> note letter for C-sharp minor (four sharps supplied by the key signature):
    ~pcLetter = [nil, "C", nil, "D", "E", nil, "F", nil, "G", "A", nil, "B"];

    // Palettes of whole four-beat bars (each sums to 4). Melody = long notes; RH faster; LH slower.
    ~melBarRhythms = [ [4], [2, 2], [3, 1], [1, 3], [2, 1, 1] ];
    ~rhBarRhythms  = [
        [1, 1, 1, 1], [0.5, 0.5, 1, 1, 1], [0.5, 0.5, 0.5, 0.5, 2], [1, 1, 0.5, 0.5, 1],
        [2, 1, 1], [1.5, 0.5, 1, 1], [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1]
    ];
    ~lhBarRhythms  = [ [2, 2], [4], [1, 1, 2], [2, 1, 1], [1.5, 0.5, 2], [3, 1], [1, 1, 1, 1] ];

    // ---- MEI helpers: build one THREE-staff score ---------------------------
    // MEI `dur` is the note value; (beats * 2) indexes: 1=eighth 2=quarter 3=dotted-quarter 4=half
    // 6=dotted-half 8=whole -> [dur-value, dots-attribute].
    ~meiDurs = [nil, ["8", ""], ["4", ""], ["4", " dots=\"1\""], ["2", ""], nil, ["2", " dots=\"1\""], nil, ["1", ""]];

    ~degToMidi = { |root, deg| root + ((deg / 7).floor.asInteger * 12) + ~semis[deg % 7] };

    ~meiNote = { |dur, midi|
        var d = ~meiDurs[(dur * 2).round.asInteger];
        if(midi.isNil) {
            "<rest dur=\"" ++ d[0] ++ "\"" ++ d[1] ++ "/>"
        } {
            var pc  = midi % 12;
            var oct = (midi / 12).floor.asInteger - 1;
            "<note dur=\"" ++ d[0] ++ "\"" ++ d[1] ++ " oct=\"" ++ oct.asString
                ++ "\" pname=\"" ++ ~pcLetter[pc].toLower ++ "\"/>"
        };
    };

    ~meiLayer = { |bar| bar.collect({ |ev| ~meiNote.(ev[0], ev[1]) }).join };

    // staff 1 = melody, staff 2 = right hand, staff 3 = left hand; a brace joins the two piano staves.
    ~meiScore = { |melBars, rhBars, lhBars|
        var body = "";
        melBars.size.do({ |i|
            body = body
                ++ "<measure n=\"" ++ (i + 1).asString ++ "\">"
                ++ "<staff n=\"1\"><layer n=\"1\">" ++ ~meiLayer.(melBars[i]) ++ "</layer></staff>"
                ++ "<staff n=\"2\"><layer n=\"1\">" ++ ~meiLayer.(rhBars[i]) ++ "</layer></staff>"
                ++ "<staff n=\"3\"><layer n=\"1\">" ++ ~meiLayer.(lhBars[i]) ++ "</layer></staff>"
                ++ "</measure>";
        });
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        ++ "<mei xmlns=\"http://www.music-encoding.org/ns/mei\" meiversion=\"4.0.0\">"
        ++ "<music><body><mdiv><score>"
        ++ "<scoreDef meter.count=\"4\" meter.unit=\"4\" key.sig=\"" ++ ~keySig ++ "\">"
        ++ "<staffGrp>"
        ++ "<staffDef n=\"1\" lines=\"5\" clef.shape=\"G\" clef.line=\"2\"/>"
        ++ "<staffGrp symbol=\"brace\" bar.thru=\"true\">"
        ++ "<staffDef n=\"2\" lines=\"5\" clef.shape=\"G\" clef.line=\"2\"/>"
        ++ "<staffDef n=\"3\" lines=\"5\" clef.shape=\"F\" clef.line=\"4\"/>"
        ++ "</staffGrp></staffGrp></scoreDef>"
        ++ "<section>" ++ body ++ "</section>"
        ++ "</score></mdiv></body></music></mei>";
    };

    // ---- the three "patterns" (built with the pattern library) -------------
    // One bar: pull a whole 4-beat rhythm (Prand), then for each note a rest decision (Pwrand) and, if
    // a note, a scale degree from that part's random walk (Pbrown).
    ~genBar = { |rhythmStream, degStream, root|
        rhythmStream.next.collect({ |dur|
            var midi = ~rest.next.if({ nil }, { ~degToMidi.(root, degStream.next.round.asInteger) });
            [dur, midi];
        });
    };

    // Play a whole page: one Pbind per part (\type \rest for rest events), all run together by Ppar.
    ~playPage = { |melBars, rhBars, lhBars|
        var mk = { |bars, pan, amp, instr, legato|
            var events = bars.flatten(1);
            Pbind(
                \instrument, instr,
                \type,     Pseq(events.collect({ |e| e[1].isNil.if({ \rest }, { \note }) }), 1),
                \midinote, Pseq(events.collect({ |e| e[1] ? 60 }), 1),
                \dur,      Pseq(events.collect({ |e| e[0] }), 1),
                \legato, legato, \amp, amp, \pan, pan
            );
        };
        Ppar([
            mk.(melBars, 0.0,  0.11, \pad,   1.0),   // melody — pad, centred, sustained
            mk.(rhBars,  0.22, 0.11, \pnote, 0.9),   // right hand — piano
            mk.(lhBars, -0.22, 0.14, \pnote, 0.9)    // left hand — piano
        ]).play(~clock, quant: 0);
    };

    // Sweep the playhead across the score over one page (16 beats), anchored to the measured note span.
    ~sweepCursor = {
        Routine({
            var steps = 96;
            var dur   = 16 / steps;
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

        // fresh pattern streams (created here so re-evaluating the block restarts them)
        ~melDeg   = Pbrown(0,  8, 2, inf).asStream;                          // melody walk (top)
        ~rhDeg    = Pbrown(0, 13, 3, inf).asStream;                          // right-hand walk
        ~lhDeg    = Pbrown(0,  9, 2, inf).asStream;                          // left-hand walk (lower)
        ~melRhythm = Prand(~melBarRhythms, inf).asStream;
        ~rhRhythm  = Prand(~rhBarRhythms, inf).asStream;
        ~lhRhythm  = Prand(~lhBarRhythms, inf).asStream;
        ~rest      = Pwrand([true, false], [~restProb, 1 - ~restProb], inf).asStream;

        if(~conductor.notNil) { ~conductor.stop };
        if(~clock.notNil)     { ~clock.stop };
        ~clock = TempoClock(~bpm / 60);

        // The conductor: each cycle, pull a fresh 4-measure page (all three parts) from the pattern
        // streams, SHOW the three-staff score, (optionally wait ~lead), then play it and sweep the cursor.
        ~conductor = Routine({
            loop {
                var melBars = Array.fill(4, { ~genBar.(~melRhythm, ~melDeg, ~melRoot) });
                var rhBars  = Array.fill(4, { ~genBar.(~rhRhythm,  ~rhDeg,  ~rhRoot) });
                var lhBars  = Array.fill(4, { ~genBar.(~lhRhythm,  ~lhDeg,  ~lhRoot) });
                ~engine.sendMsg("/ms/scene/score", "notationData", "mei", ~meiScore.(melBars, rhBars, lhBars));
                ~engine.sendMsg("/ms/scene/score/cursor", "pos", ~cursorStart, 0.5);
                if(~lead > 0) { ~lead.wait };
                ~playPage.(melBars, rhBars, lhBars);
                ~sweepCursor.value;
                16.wait;                          // four 4/4 bars
            };
        }).play(~clock);

        "".postln;
        "Three-part PATTERN score (melody + two hands, C-sharp / D-flat minor) — running.".postln;
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
"Three-part pattern score stopped.".postln;
)
