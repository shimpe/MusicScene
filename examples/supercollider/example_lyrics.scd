// =============================================================================
// MSScore lyrics — sung text under a staff, authored as a SEPARATE line per staff.
//
//   lyrics: [ <staff 1>, <staff 2>, ... ]     parallel to `voices`
//     each entry:  a list of verse lines  [ "verse 1", "verse 2" ]   (stacked verses)
//                  a bare String           "one verse"
//                  nil                      no lyrics on that staff
//
//   In a verse line:
//     space   -> next word
//     -       -> hyphen between syllables of one word   (Twin-kle -> Twin- kle)
//     _       -> melisma: the note holds the previous syllable (no new syllable)
//     \       -> escape the next character into the syllable ( \  = space, \_ = underscore )
//
// Lyrics are NOTATION ONLY — they never change the sound.
// REQUIRES: the Panola + MSScore quarks (Quarks.install), MusicScene running with Verovio.
// USAGE: run the Godot project (one instance), put the cursor in the ( ) block, Ctrl+Enter.
// =============================================================================

(
// A melody + a bass line. Only the melody gets lyrics (two verses); the bass stays nil.
~melody = "c5_4 d5 e5 f5 g5_2 g5_4 a5 g5 f5 e5_2 e5_4 d5 c5_1";
~bass   = "c3_2 g3 c3_2 g3 c3_2 c3 c3_1";

~score = MSScore(
	voices:  [ ~melody, ~bass ],
	clefs:   [ \treble, \bass ],
	braces:  [ [1, 2] ],
	meter:   "4/4", key: \Cmajor, tempo: 96,
	lyrics:  [
		[ "Twin-kle twin-kle lit-tle star,",       // melody, verse 1
		  "Up a-bove the world so high," ],        // melody, verse 2
		nil                                        // bass: no lyrics
	],
	space:   "2d"
);

~score.show;
"Lyrics: two verses under the melody. '-' draws hyphens; try a melisma with '_' or an escaped space '\\ '.".postln;
)


// ~score.play;    // hear it (lyrics do NOT affect the sound)
// ~score.stop;    // clear the scene
