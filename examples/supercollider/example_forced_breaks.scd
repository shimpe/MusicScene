// =============================================================================
// MSScore forced page & system breaks — control where pages and lines break.
//
//   pageBreaks:   [n, ...]  -> a new PAGE starts at those bars (MEI <pb/>). This is MANUAL
//                             pagination: you control every page boundary and auto page-fill is
//                             OFF (Verovio can't mix the two). pageHeight sets the page size.
//   systemBreaks: [n, ...]  -> a new SYSTEM (line) starts at those bars (MEI <sb/>). Auto
//                             pagination is KEPT (pages still fill by pageHeight).
//
// REQUIRES: the MSScore quark (Quarks.install), MusicScene running with Verovio.
// USAGE: run the Godot project (one instance), set ~space, put the cursor in the ( ) block, Ctrl+Enter.
//        showPage(n) shows a given page; page(n)/nextPage/prevPage flip.
// =============================================================================

(
// Two 4-bar phrases (8 bars) + a whole-note cadence. Force a PAGE break at bar 5 (second phrase on
// its own page) and a SYSTEM break at bar 3 (so bars 1-2 and 3-4 are separate lines on page 1).
~voice = "c5_4 e5 g5 e5 d5_4 f5 a5 f5 e5_4 g5 b5 g5 f5_4 a5 c6 a5 " ++
         "g5_4 e5 c5 e5 f5_4 d5 b4 d5 e5_4 c5 g4 c5 c5_1";

~score = MSScore(
	voices:       [~voice],
	clefs:        [\treble],
	meter:        "4/4", key: \Cmajor, tempo: 92,
	scale:        1.0,
	paginate:     true, pageHeight: 900,
	systemBreaks: [4],   // new LINE at bar 4 (page 1)
	pageBreaks:   [5],   // new PAGE at bar 5
	space:        "3d"   // set "3d" to match your project's musicscene/space
);

~score.showPage(1);   // page 1 = bars 1-4 (two lines: 1-3 | 4); page 2 = bars 5-9
"Forced breaks: page break at bar 5, line break at bar 4. Try ~score.showPage(2) / nextPage.".postln;
)


~score.showPage(2);   // the second page (bars 5-9)
~score.stop;          // clear the scene
