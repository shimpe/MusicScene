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
//     -       -> hyphen between syllables of one word   (morn-ing -> morn- ing)
//     _       -> melisma: the note holds the previous syllable (no new syllable)
//     \       -> escape the next character into the syllable ( \  = space, \_ = underscore )
//
// Lyrics are NOTATION ONLY — they never change the sound.
// REQUIRES: the Panola + MSScore quarks (Quarks.install), MusicScene running with Verovio.
// USAGE: run the Godot project (one instance), put the cursor in the ( ) block, Ctrl+Enter.
// =============================================================================

(
// A 9-note melody (3 bars of 4/4) + a bass line. Only the melody is sung (two verses);
// the bass staff stays nil. Each verse lines up one syllable per melody note, and shows
// off all three lyric features — a drawn hyphen, a melisma, and an escaped space:
//
//   note:     c5    d5    e5    f5    g5   a5    g5    f5    e5
//   verse 1:  Good  morn- ing   sing  ~    ~     a-    gain  now
//             bye                     (melisma: 'sing' held over f5 g5 a5)
//   verse 2:  Hel-  lo    eve   glow  ~    ~     till  the   end
//
//   'Good\ bye' -> ONE syllable containing a space (the '\' escapes the space)
//   'morn-ing'  -> a hyphen is drawn between the two syllables
//   'sing _ _'  -> a melisma: 'sing' rings on across the next two notes (no new syllable)
~melody = "c5_4 d5 e5_2 f5_4 g5 a5 g5 f5 e5_2.";
~bass   = "c3_1 g3_1 c3_1";

~score = MSScore(
	voices:  [ ~melody, ~bass ],
	clefs:   [ \treble, \bass ],
	braces:  [ [1, 2] ],
	meter:   "4/4", key: \Cmajor, tempo: 96,
	lyrics:  [
		// melody: two verses. In a SuperCollider string a literal backslash is written "\\", so
		// "Good\\ bye" reaches the lyric parser as  Good\ bye  -> ONE syllable "Good bye" (the '\'
		// escapes the space). 'sing _ _' / 'glow _ _' is a melisma; '-' draws the syllable hyphens.
		[ "Good\\ bye morn-ing sing _ _ a-gain now",  // verse 1
		  "Hel-lo eve glow _ _ till the end" ],        // verse 2
		nil                                            // bass: no lyrics
	],
	space:   "2d"
);

~score.show;
"Lyrics: 2 verses. 'morn-ing' draws a hyphen; 'sing _ _' holds one syllable over 3 notes; 'Good\\ bye' is one sung syllable with a space.".postln;
)


// ~score.play;    // hear it (lyrics do NOT affect the sound)
// ~score.stop;    // clear the scene
