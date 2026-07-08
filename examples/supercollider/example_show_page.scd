// =============================================================================
// MSScore display-only: show a GIVEN page of the notation — no cursor, no playback.
//
// `showPage(n)` engraves the score and shows page n (1-based) with the cursor line OFF and no
// audio. Once shown, `page(n)`, `nextPage` and `prevPage` flip between the pre-rendered pages.
// Contrast with `play` (which shows, plays, and follows with a cursor).
//
// REQUIRES:
//   * The MSScore quark:  Quarks.install("https://github.com/shimpe/msscore")
//     (this also installs the Panola quark it depends on), then recompile the class library.
//   * MusicScene running with Verovio (`pip install verovio`).
//
// USAGE:
//   1. Run the Godot project with MusicScene (one instance). Set ~space below to match musicscene/space.
//   2. Put the cursor in the ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   3. Page 2 appears — static, no cursor, no sound.
//   4. Evaluate the flip lines (nextPage / prevPage / page) one at a time to browse pages.
//   5. Evaluate ~score.stop to clear the scene.
// =============================================================================

(
// A long melody so the score spans several pages (a small pageHeight => more pages).
~long = (1..48).collect({ |i| ["c5", "e5", "g5", "a5", "f5", "d5"].wrapAt(i) ++ "_8" }).join(" ");

~score = MSScore(
	voices:   [~long],
	clefs:    [\treble],
	meter:    "4/4", key: \Cmajor, tempo: 96,
	scale:    1.0,
	paginate: true, pageHeight: 700,   // small page => several pages to flip through
	space:    "3d"                     // set "3d" to match your project's musicscene/space
);

~score.showPage(2);   // DISPLAY page 2 only — no cursor, no sound
"Showing page 2 (display only). Evaluate the flip lines below to browse; ~score.stop to clear.".postln;
)


// Flip pages — evaluate a line at a time:
// ~score.nextPage;   // -> page 3
// ~score.prevPage;   // -> back a page
// ~score.page(1);    // jump to page 1


// Clear the scene when done:
// ~score.stop;
