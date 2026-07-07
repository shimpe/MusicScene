// =============================================================================
// Mid-piece meter / key / clef CHANGES showcase (Panola -> MSScore -> MusicScene).
//
// A score no longer needs one fixed meter, key and clef for the whole piece. This short piano étude
// changes all three MID-PIECE and engraves each change correctly:
//
//   * METER change  — a `changes` list switches 4/4 -> 3/4 at bar 5. The bar length itself changes:
//                     from bar 5 a bar is three quarter-beats, barlines/beaming follow, and a new meter
//                     signature is printed. (Note DURATIONS are authored as-is; only the notation regroups.)
//   * KEY change    — the same `changes` list switches C major -> G major at bar 3. A new key signature
//                     (one sharp) is printed there; from bar 3 an authored f# needs NO accidental (it is
//                     in the key), so the very same letter "f" prints as f-natural in bars 1-2 and as
//                     f-sharp from bar 3 — driven purely by the signature. Pitches are NEVER transposed;
//                     accidentals are only respelled for the new key.
//   * CLEF change   — inline in the Panola stream, so it can happen MID-MEASURE. Tag a note @clef^treble^
//                     (or \bass / \alto / \tenor) and that staff switches clef at that note. Here the LEFT
//                     hand climbs into treble register in bar 4 and switches to a treble clef on beat 2,
//                     then drops back to bass clef at bar 5 — the classic hand-crossing notation.
//
// The `changes` list carries each field forward until the next change: give a `meter:` and/or `key:` at
// the (1-based) measure where it takes effect; omitted fields keep their current value.
//
// WHAT EACH MEASURE DEMONSTRATES (watch the engraved notation):
//   M1-2  4/4, C major        — the baseline. RH melody, LH half-note roots. "f" prints as f-natural.
//   M3    KEY -> G major       — one-sharp signature appears; the RH f# now prints with no accidental.
//   M4    inline CLEF change   — LH plays beat 1 low in bass clef, then @clef^treble^ switches to treble
//                               clef mid-bar for a rising answer (d5 up top).
//   M5    METER -> 3/4         — bars are now three beats; LH @clef^bass^ drops back to the bass clef.
//   M6    cadence in 3/4       — a dotted half in each hand under the new meter and key.
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

	// One line per measure. Duration carries over until changed. The key/meter changes are NOT in the
	// Panola strings — they are the score-level `changes` list below. Only the CLEF change is inline
	// (@clef^...^), because it may fall mid-measure.
	~treble = [
		"c5_4 e5 g5 e5",      // M1  4/4, C major
		"f5_4 d5 g5 e5",      // M2  "f" prints as f-natural (C major)
		"d5_4 f#5 a5 f#5",    // M3  KEY -> G major: the same "f" now prints as f-sharp with NO accidental
		"g5_4 b5 a5 f#5",     // M4  still G major
		"g5_4 a5 b5",         // M5  METER -> 3/4: three beats to the bar
		"d6_2."               // M6  cadence (dotted half = 3 beats)
	].join(" ");

	~bass = [
		"c3_2 g3_2",                    // M1  half-note roots, bass clef
		"d3_2 b2_2",                    // M2
		"g2_2 d3_2",                    // M3  (key change is score-level, nothing to write here)
		"g2_4 g4_4@clef^treble^ b4 d5", // M4  beat 1 low (bass clef); beat 2 switches to TREBLE clef mid-bar
		"g2_4@clef^bass^ b2 d3",        // M5  back to BASS clef; three beats (3/4)
		"g2_2."                         // M6  cadence root (dotted half = 3 beats)
	].join(" ");

	~score = MSScore(
		voices:      [~treble, ~bass],
		clefs:       [\treble, \bass],   // INITIAL clefs; the inline @clef changes it from here
		changes:     [ ( measure: 1, meter: "4/4", key: \Cmajor ),   // initial meter + key
		               ( measure: 3, key: \Gmajor ),                 // key change; meter carries over (4/4)
		               ( measure: 5, meter: "3/4" ) ],                // meter change; key carries over (G major)
		braces:      [[1, 2]],           // brace the two staves into a piano grand staff
		tempo:       92,
		scale:       1.0,                // score size in the scene — raise/lower to fit your view
		instruments: [\pnote, \pnote],
		space:       "3d"                // set "3d" to match your project's musicscene/space
	);

	~score.play;
	"Mid-piece changes showcase playing — watch the key signature (bar 3), the meter (bar 5), and the".postln;
	"left-hand clef change (bar 4). Evaluate the CLEANUP block to stop; evaluate ~dumpMEI to write the .mei.".postln;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
~score.stop;
"Mid-piece changes showcase stopped.".postln;
)


// =============================================================================
// OPTIONAL — write the raw MEI to disk (no MusicScene needed) to eyeball the notation.
// =============================================================================
(
~dumpMEI = {
	var path = Platform.defaultTempDir +/+ "panola_midpiece_changes.mei";
	File.use(path, "w", { |f| f.write(Panola.scoreAsMEI([Panola(~treble), Panola(~bass)],
		[ ( measure: 1, meter: "4/4", key: \Cmajor ),
		  ( measure: 3, key: \Gmajor ),
		  ( measure: 5, meter: "3/4" ) ], [\treble, \bass], [[1, 2]])) });
	("Wrote " ++ path).postln;
};
~dumpMEI.value;
)
