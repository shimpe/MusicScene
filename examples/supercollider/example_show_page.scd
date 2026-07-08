// =============================================================================
// MSScore display-only: show a GIVEN page of the notation — no cursor, no playback.
//
// `showPage(n)` engraves the score and shows page n (1-based) with the cursor line OFF and no
// audio. Once shown, `page(n)`, `nextPage` and `prevPage` flip between the pre-rendered pages.
// Contrast with `play` (which shows, plays, and follows with a cursor).
//
// Pagination note: the number of pages depends on `pageHeight` (smaller = fewer systems per page =
// more pages). This score spans TWO pages at pageHeight 300; raise it (e.g. 700) and the whole
// score fits on one page (then showPage(1) and showPage(2) look the same).
//
// REQUIRES:
//   * The MSScore quark:  Quarks.install("https://github.com/shimpe/msscore")
//     (this also installs the Panola quark it depends on), then recompile the class library.
//   * MusicScene running with Verovio (`pip install verovio`).
//
// USAGE:
//   1. Run the Godot project with MusicScene (one instance). Set ~space below to match musicscene/space.
//   2. Put the cursor in the ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   3. Page 2 appears (the closing systems, ending on the whole note) — static, no cursor, no sound.
//   4. Evaluate the flip lines (nextPage / prevPage / page) one at a time to browse pages.
//   5. Evaluate ~score.stop to clear the scene.
// =============================================================================

(
// A long melody (+ a whole-note cadence) so the score spans several pages at a small pageHeight.
~long = (1..48).collect({ |i| ["c5", "e5", "g5", "a5", "f5", "d5", "b4", "d5", "a5", "f5", "e5"].wrapAt(i) ++ "_8" }).join(" ") ++ " c6_1";

~score = MSScore(
	voices:   [~long],
	clefs:    [\treble],
	meter:    "4/4", key: \Cmajor, tempo: 96,
	scale:    0.5,
	paginate: true, pageHeight: 300,   // small page => this score spans 2 pages
	space:    "3d"                     // set "3d" to match your project's musicscene/space
);

~score.showPage(2);   // DISPLAY page 2 only (the closing systems) — no cursor, no sound
"Showing page 2 (display only). Evaluate the flip lines below to browse; ~score.stop to clear.".postln;
)


// Flip pages — evaluate a line at a time:
~score.page(1);    // jump to page 1 (opening systems)
~score.nextPage;   // -> page 2
~score.prevPage;   // -> back to page 1


// Clear the scene when done:
~score.stop;
