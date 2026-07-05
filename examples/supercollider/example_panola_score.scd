// =============================================================================
// Panola -> MusicScene, the simple way. Write a score as Panola string(s); MSScore turns them into
// MEI (via the Panola quark's Panola.scoreAsMEI), shows the notation in MusicScene, plays the voices,
// and follows along with a note-accurate cursor. This is the "make/play/visualize a score in a few
// lines" front door — compare the hand-rolled example_two_hands_patterns.scd.
//
// Panola has no barlines / key / clef — the bridge supplies a meter (barlines are derived from it; a
// note crossing a barline is auto-tied), a key, and a clef per staff. So the Panola strings below are
// just streams of notes (no "|"). Duration carries over until changed: "c5_4 e5 g5" = three quarters.
//
// REQUIRES:
//   * The Panola quark installed WITH PanolaMEI.sc + Panola:asMEI (Classes/ of the panola quark).
//   * MSScore.sc on SuperCollider's class path (copy examples/supercollider/MSScore.sc to your
//     Extensions folder, or add examples/supercollider via Preferences, then recompile the class lib).
//   * MusicScene running with Verovio (`pip install verovio`).
//
// USAGE:
//   1. Boot the audio server (evaluating the block below does it).
//   2. Run the Godot project with MusicScene (one instance). Set ~space below to match musicscene/space.
//   3. Put the cursor in the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. The score appears, plays, and the cursor follows the notes.
//   5. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

	// A soft, bell-like piano voice (same shape as the other examples).
	SynthDef(\pnote, { |freq = 440, amp = 0.2, pan = 0|
		var env = EnvGen.kr(Env.perc(0.005, 1.4, 1, -4), doneAction: 2);
		var sig = (SinOsc.ar(freq) + (SinOsc.ar(freq * 2) * 0.3) + (SinOsc.ar(freq * 3) * 0.1)) * env * amp;
		sig = sig + (FreeVerb.ar(sig, 0.3, 0.7, 0.4) * 0.3);
		Out.ar(0, Pan2.ar(sig, pan));
	}).add;
	s.sync;

	~score = MSScore(
		voices: [
			"(c5_4 e5 g5_4. c6_8 g5_4 e5 c5_8 d5 e5 g5_16 g-5_16 f5_4 a5 c6 a5 g5_2 c5_2)*2",   // right hand (treble)
			"(c3_2 g3 c3_2 e3 f3_2 g3 c3_1)*2"                            // left hand (bass)
		],
		clefs:  [\treble, \bass],
		meter:  "4/4",
		key:    \Cmajor,
		braces: [[1, 2]],                 // brace the two staves into a piano grand staff
		tempo:  88,
		scale:  2.0,                        // score size in the scene — raise/lower to fit your view
		instruments: [\pnote, \pnote],
		space:  "3d"                      // set "3d" to match your project's musicscene/space
	);

	~score.play;
	"Panola score playing in MusicScene — the cursor follows the notes.".postln;
	"Evaluate the CLEANUP block to stop.".postln;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
~score.stop;
"Panola score stopped.".postln;
)
