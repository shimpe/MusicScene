// =============================================================================
// Meter-aware rhythm notation showcase (Panola -> MSScore -> MusicScene).
//
// Panola gives each note an exact duration; the Panola quark's MEI export now spells and SPLITS those
// durations meter-aware (PanolaDurationSpeller + PanolaMeter + PanolaMeterSplitter) instead of the old
// greedy decomposition. The rule: a note may span metrical boundaries no stronger than the beat it
// starts on, but must break (and tie) at any stronger interior boundary. So syncopations and
// barline-crossings engrave correctly, while notes that legitimately sit on strong beats stay whole.
//
// This file is a LIVING showcase — new measures/sections get appended as the rhythm features grow.
// Also under the hood (not a clean measure to show): an INCOMPLETE explicit *m/d tuplet is completed
// music21-style by splitting the FOLLOWING note/rest into the bracket, tied (a trailing incomplete tuplet
// with nothing after it is left partial + warned — matching music21). The faithful completion ties and
// cascades to preserve exact timing rather than making a clean single bracket. Next up: tuplets crossing
// barlines, and consolidating over-tupleted tied runs.
//
// WHAT EACH MEASURE DEMONSTRATES (watch the engraved notation, not just listen):
//   M1  Syncopation      — off-beat quarters each split into two tied eighths across the beat.
//   M2  Anti-over-split  — a dotted quarter on the downbeat stays a single dotted quarter.
//   M3  Mid-measure      — a half note starting on beat 2 splits at the 4/4 midpoint (two tied quarters).
//   M4-5 Barline tie     — a whole note crossing the barline becomes two tied half notes.
//   M6  Tuplet (intact)  — an explicit *m/d triplet still renders atomically via the unchanged path.
//   M7  Cadence          — a whole note on the downbeat stays whole.
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

	// One line per measure so each demonstration is easy to read and extend. Duration carries over
	// until changed, so each measure's first note sets its value explicitly.
	~treble = [
		"c5_8@dyn^mf^ d5_4 e5 f5 g5_8",   // M1  syncopation: e8 (q~) (q~) (q~) e8 -> tied eighths at each beat
		"c5_4. d5_8 e5_4 f5",             // M2  anti-over-split: dotted quarter on beat 1 stays whole
		"g5_4 a5_2 g5_4",                 // M3  half note on beat 2 splits at the 2.0 midpoint (quarter~quarter)
		"f5_2 e5_1 d5_2",                 // M4-5 whole note across the barline -> two tied half notes
		"c5_4*2/3 d5 e5 f5_4 g5",         // M6  explicit triplet (3-in-2) stays one <tuplet>, then two quarters
		"c5_1"                            // M7  cadence: whole note on the downbeat, kept whole
	].join(" ");

	~bass = [
		"c3_1", "c3", "e3", "f3", "f3", "c3", "c3"   // one sustained whole-note root per measure
	].join(" ");

	~score = MSScore(
		voices:      [~treble, ~bass],
		clefs:       [\treble, \bass],
		meter:       "4/4",
		key:         \Cmajor,
		braces:      [[1, 2]],            // brace the two staves into a piano grand staff
		tempo:       84,
		scale:       2.5,                 // score size in the scene — raise/lower to fit your view
		instruments: [\pnote, \pnote],
		space:       "3d"                 // set "3d" to match your project's musicscene/space
	);

	~score.play;
	"Meter-aware rhythm showcase playing — watch the ties/splits in the notation.".postln;
	"Evaluate the CLEANUP block to stop; evaluate ~dumpMEI to write the raw .mei.".postln;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
~score.stop;
"Meter-aware rhythm showcase stopped.".postln;
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
