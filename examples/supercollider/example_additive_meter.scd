// =============================================================================
// Additive-meter grouping showcase (Panola -> MSScore -> MusicScene).
//
// An irregular meter written with an ADDITIVE numerator: "2+3+2/8" — seven eighths per bar, grouped
// 2 + 3 + 2. The Panola quark's MEI export reads the grouping from the meter string and makes it drive
// the notation three ways: the meter SIGNATURE prints "2+3+2", notes are BEAMED per group, and a note
// that crosses a group boundary is SPLIT and tied there (the group boundaries are strong metric points,
// like beats in a regular meter). A plain "7/8" (no "+") would stay ungrouped — every eighth its own beat.
//
// WHAT EACH MEASURE DEMONSTRATES (watch the engraved notation):
//   M1  Beaming 2+3+2   — seven straight eighths beam as three groups (2, 3, 2), not uniformly.
//   M2  Split at group 1|2 — a quarter starting off-beat in group 1 crosses the boundary at beat 1 and
//                        splits into two tied eighths.
//   M3  Split at group 2|3 — a quarter crossing the boundary at beat 2.5 splits into two tied eighths.
//   M4  Grouped cadence — quarter · dotted-quarter · quarter: the note values themselves mirror 2+3+2.
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

	// One line per measure. Duration carries over until changed. The bass mirrors the 2+3+2 grouping
	// with quarter · dotted-quarter · quarter roots.
	~treble = [
		"c5_8@dyn^mp^ e5 g5 c6 g5 e5 c5",   // M1  seven eighths -> beamed 2 + 3 + 2
		"c5_8 d5_4 f5_4 a5_8 b5_8",          // M2  d5 (off-beat quarter) crosses beat 1 -> two tied eighths
		"c5_4 d5_4 e5_4 f5_8",               // M3  e5 (quarter) crosses beat 2.5 -> two tied eighths
		"c5_4 d5_4. c5_4"                    // M4  quarter · dotted-quarter · quarter = 2+3+2 in note values
	].join(" ");

	~bass = [
		"c3_4 g2_4. c3_4",                   // grouped pedal: quarter · dotted-quarter · quarter (2+3+2)
		"g2_4 d2_4. g2_4",
		"a2_4 e2_4. a2_4",
		"c3_4 g2_4. c3_4"
	].join(" ");

	~score = MSScore(
		voices:      [~treble, ~bass],
		clefs:       [\treble, \bass],
		meter:       "2+3+2/8",           // additive numerator: seven eighths grouped 2+3+2
		key:         \Cmajor,
		braces:      [[1, 2]],            // brace the two staves into a piano grand staff
		tempo:       104,                 // a lilting 7/8 groove
		scale:       2.6,                 // score size in the scene — raise/lower to fit your view
		instruments: [\pnote, \pnote],
		space:       "3d"                 // set "3d" to match your project's musicscene/space
	);

	~score.play;
	"Additive-meter (2+3+2/8) showcase playing — watch the 2+3+2 beaming, group-boundary splits, and signature.".postln;
	"Evaluate the CLEANUP block to stop; evaluate ~dumpMEI to write the raw .mei.".postln;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
~score.stop;
"Additive-meter showcase stopped.".postln;
)


// =============================================================================
// OPTIONAL — write the raw MEI to disk (no MusicScene needed) to eyeball the notation.
// =============================================================================
(
~dumpMEI = {
	var path = Platform.defaultTempDir +/+ "panola_additive_meter.mei";
	File.use(path, "w", { |f| f.write(Panola.scoreAsMEI([Panola(~treble), Panola(~bass)],
		[( measure: 1, meter: "2+3+2/8", key: \Cmajor )], [\treble, \bass], [[1, 2]])) });
	("Wrote " ++ path).postln;
};
~dumpMEI.value;
)
