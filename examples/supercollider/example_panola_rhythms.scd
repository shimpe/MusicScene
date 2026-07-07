// =============================================================================
// CHALLENGING complex-rhythm notation showcase (Panola -> MSScore -> MusicScene).
//
// A deliberately hard rhythmic étude that exercises the Panola quark's rhythm engine: exotic tuplets
// (7:4, 9:8, 5:4), dense syncopation, and long off-beat notes that must be split and tied per the meter.
// Panola gives each note an exact duration; the MEI export spells + SPLITS it meter-aware
// (PanolaDurationSpeller + PanolaMeter + PanolaMeterSplitter) and brackets tuplet fragments
// (music21-style). A note may span metrical boundaries no stronger than the beat it starts on, but must
// break (and tie) at any stronger interior boundary — so syncopations and off-beat holds engrave
// correctly, while explicit *m/d tuplets render as real <tuplet> brackets.
//
// Under the hood (not shown as a clean measure): an INCOMPLETE explicit *m/d tuplet is completed
// music21-style by splitting the FOLLOWING note/rest into the bracket, tied (a trailing incomplete tuplet
// with nothing after it is left partial + warned, matching music21). Next still to come: consolidating
// over-tupleted tied runs, and nested tuplets.
//
// WHAT EACH MEASURE THROWS AT THE ENGINE (watch the engraved notation):
//   M1   Septuplet 7:4   — seven 16ths in the space of four, filling beat 1, then three quarters.
//   M2   Nonuplet 9:8    — nine 16ths in the space of eight, spanning two beats, then a half note.
//   M3   Quintuplets 5:4 — two five-in-four 16th runs (one per beat), then a half note.
//   M4   Syncopation     — off-beat quarters, each split into two tied eighths across the beat.
//   M5   Off-beat hold   — a half note starting on a 16th off-beat splits at every beat it crosses.
//   M6   Mixed tuplet    — a 3:2 triplet mixing a quarter + an eighth, then a syncopated half note.
//   M7-8 Tuplet OVER a barline — a 7:4 septuplet on the "and" of beat 4 spans the barline: it splits into
//                          TWO tied <tuplet> brackets (one per bar), the straddling 16th cut into two
//                          tied 32nds across the barline.
//   M9   Cadence         — a whole note on the downbeat, kept whole.
//
// REQUIRES:
//   * The MSScore quark:  Quarks.install("https://github.com/shimpe/msscore")
//     (this also installs the Panola quark it depends on), then recompile the class library.
//   * MusicScene running with Verovio (`pip install verovio`).
//
// USAGE:
//   1. Boot the audio server (evaluating the block below does it).
//   2. Run the Godot project with MusicScene (one instance). Set ~space below to match musicscene/space.
//   3. Put the cursor in the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. The score appears, plays, and the cursor follows the notes.
//   5. To stop, evaluate the CLEANUP block at the bottom.
//
// TIP: to inspect the raw notation without MusicScene, evaluate ~dumpMEI at the bottom to write an .mei
//      file you can open in Verovio / any MEI viewer.
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

	// One line per measure so each challenge is easy to read and extend. Duration carries over until
	// changed, so each measure's first note sets its value (and any *m/d tuplet ratio) explicitly.
	~treble = [
		"c5_16*4/7@dyn^mf^ d5 e5 f5 g5 a5 b5 c6_4 d6 e6",   // M1  septuplet 7:4 (beat 1) + three quarters
		"c6_16*8/9 b5 a5 g5 f5 e5 d5 c5 b4 a4_2",           // M2  nonuplet 9:8 (beats 1-2) + a half note
		"c5_16*4/5 d5 e5 f5 g5 a5_16*4/5 b5 c6 d6 e6 f6_2", // M3  two quintuplets 5:4 (beat 1, beat 2) + half
		"c5_8 d5_4 e5 f5 g5_8",                             // M4  off-beat quarters -> tied eighths (syncopation)
		"c5_16 d5_2 e5_4 f5_8 g5_16",                       // M5  a half on a 16th off-beat splits at each beat
		"c5_4*2/3 d5_8*2/3 e5_2 f5_4",                      // M6  mixed 3:2 triplet (quarter+eighth) + syncopated half
		"c5_4 d5 e5 f5_8 g5_16*4/7 a5 b5 c6 d6 e6 f6 e6_8 d6_4 c6 b5",  // M7-8 septuplet 7:4 across the barline
		"c5_2*3 r_2"                                        // M9  cadence: whole note on the downbeat, spilling over to next bar.
	].join(" ");

	~bass = [
		"c3_1", "a2", "f2", "g2", "c3", "g2", "e2", "f2", "c3_1*2",   // one sustained root per measure (M7-8 span two)
	].join(" ");

	~score = MSScore(
		voices:      [~treble, ~bass],
		clefs:       [\treble, \bass],
		meter:       "4/4",
		key:         \Cmajor,
		braces:      [[1, 2]],            // brace the two staves into a piano grand staff
		tempo:       72,                  // moderate, so the fast tuplets stay audible/visible
		scale:       2.3,                 // score size in the scene — raise/lower to fit your view
		instruments: [\pnote, \pnote],
		space:       "3d"                 // set "3d" to match your project's musicscene/space
	);

	~score.play;
	"Challenging rhythm showcase playing — watch the tuplets, ties, and off-beat splits in the notation.".postln;
	"Evaluate the CLEANUP block to stop; evaluate ~dumpMEI to write the raw .mei.".postln;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
~score.stop;
"Challenging rhythm showcase stopped.".postln;
)


// =============================================================================
// OPTIONAL — write the raw MEI to disk (no MusicScene needed) to eyeball the notation.
// =============================================================================
(
~dumpMEI = {
	var path = Platform.defaultTempDir +/+ "panola_rhythms.mei";
	File.use(path, "w", { |f| f.write(Panola.scoreAsMEI([Panola(~treble), Panola(~bass)],
		"4/4", \Cmajor, [\treble, \bass], [[1, 2]])) });
	("Wrote " ++ path).postln;
};
~dumpMEI.value;
)
