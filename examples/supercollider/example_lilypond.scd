// =============================================================================
// Panola -> LilyPond. Panola can render the SAME notation as a standalone LilyPond (.ly) file
// (renders with `lilypond file.ly`), in addition to MEI/Verovio. This is a SECOND, independent
// notation engine, not a replacement — MSScore picks it per-score with `notation: \lilypond`.
//
// TWO parts:
//   PART A — no server, no Godot: build a .ly String with Panola.scoreAsLilypond(...) directly
//            and render it standalone via the `lilypond` command-line tool.
//   PART B — inside MusicScene: MSScore(..., notation: \lilypond) renders the SAME kind of score
//            through the LilyPond engraver and shows it in the running Godot app.
//
// The feature spread below (tuplet, dynamics, slur, mid-piece meter change, lyrics, a forced
// system break) mirrors what example_lyrics.scd and example_midpiece_changes.scd each show
// individually — here they all go through the LilyPond path instead of Verovio/MEI.
// =============================================================================


// =============================================================================
// PART A — pure Panola -> LilyPond text. No audio server, no Godot required.
// =============================================================================
(
~ly = Panola.scoreAsLilypond(
	[ Panola("c5_4@dyn^mf^ e5@slur^start^ g5 c6@slur^end^ g5_8*2/3 e5 c5 d5_2"),
	  Panola("c3_2 g3 c3_1") ],
	[ ( measure: 1, meter: "4/4", key: \Cmajor ) ],
	[ \treble, \bass ], [[1, 2]],
	nil, nil,
	[ [ "la la la la" ], nil ]
);
~ly.postln;
"Part A: a standalone LilyPond document (dyn 'mf', a slur, an eighth triplet, a half note, a two-staff brace).".postln;

// To render it standalone (no MusicScene, no SuperCollider server):
// File.use(Platform.defaultTempDir +/+ "score.ly", "w", { |f| f.write(~ly) });
// then in a shell:
//   "C:/Program Files/lilypond-2.25.81/bin/lilypond.exe" score.ly    ->  score.pdf
)


// =============================================================================
// PART B — MSScore(..., notation: \lilypond) inside the running MusicScene (Godot) app.
//
// PREREQUISITES (both required for this part; Part A above needs neither):
//   1. LilyPond must be installed (e.g. from https://lilypond.org).
//   2. The LilyPond engraver must be configured as a Godot project setting:
//        musicscene/notation/engraver/lilypond = "C:/Program Files/lilypond-2.25.81/bin/lilypond.exe"
//      (Project > Project Settings > musicscene/notation/engraver/lilypond, or set it via script.)
//
// CONSTRAINT: with notation: \lilypond the preview is a SINGLE cropped image — there is no
// auto page-turn. `paginate` / `showPage` / `nextPage` are Verovio-only (the default
// notation: \verovio engine). `systemBreaks` / `pageBreaks` still work — they lay out where
// the systems (lines) fall WITHIN that one image; they just never split it into several pages.
//
// USAGE: run the Godot project (one instance) with MusicScene, put the cursor in the ( ) block
// below, and Ctrl+Enter.
// =============================================================================

(
// Same feature spread as example_lyrics.scd / example_midpiece_changes.scd, through LilyPond:
//   dyn 'mf'/'f', a slur, an eighth triplet, a mid-piece meter change (4/4 -> 3/4 at bar 3),
//   a forced system break at bar 3, and a sung lyric line under the melody.
~melody = "c5_4@dyn^mf^ d5@slur^start^ e5 f5@slur^end^ g5_8*2/3 a5 g5 f5_4 e5_4 d5_4 c6_4@dyn^f^ b5 a5 g5_2.";
~bass   = "c3_1 g3_1 c3_2. g2_2.";

~score = MSScore(
	voices:       [ ~melody, ~bass ],
	clefs:        [ \treble, \bass ],
	braces:       [ [1, 2] ],
	changes:      [ ( measure: 1, meter: "4/4", key: \Cmajor ),   // bars 1-2: 4/4, C major
	                 ( measure: 3, meter: "3/4" ) ],                // bars 3-4: METER -> 3/4
	systemBreaks: [3],                                              // a new line/system starts at bar 3
	tempo:        96,
	scale:        1.0,
	lyrics:       [ "Ly-ly-pond sings a bright new song to-day with a tu-plet", nil ],
	notation:     \lilypond,                                        // render through LilyPond, not Verovio
	space:        "3d"
);

~score.play;
"Part B: LilyPond engraving inside MusicScene — one cropped image; watch the system break at bar 3.".postln;
)


~score.stop;    // clear the scene
