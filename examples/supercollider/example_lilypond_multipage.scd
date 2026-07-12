// example_lilypond_multipage.scd
// -----------------------------------------------------------------------------
// True multi-page LilyPond in the app. `notation: \lilypond` now paginates into
// turnable pages exactly like the Verovio path: a small `pageHeight` fills pages
// by height, and `pageBreaks` force a new page at the listed bars. `nextPage` /
// `prevPage` / `page(n)` flip pages; the follow cursor auto-turns across pages.
//
// Note: for LilyPond, `pageBreaks` are forced breaks on top of height-based
// pagination — a very small `pageHeight` may still add extra pages; Verovio's
// `pageBreaks` instead disable auto page-fill entirely.
//
// Requires the `musicscene/notation/engraver/lilypond` project setting pointing at
// your LilyPond executable, and a fontTools-capable Python (reused from the Verovio
// engraver) so LilyPond's text is outlined for ThorVG.
// -----------------------------------------------------------------------------

// Part A — page-fill by height: a long single line, small pageHeight => several pages.
(
s.waitForBoot({
	~score = MSScore(
		voices: [ (1..48).collect({ |i| ["c5","e5","g5","a5","f5","d5"].wrapAt(i) ++ "_8" }).join(" ") ],
		clefs:  [ \treble ],
		notation: \lilypond,
		paginate: true, pageHeight: 320,     // small page => multiple auto-turning pages
		tempo: 96, scale: 1.0, instruments: [\default]
	);
	~score.play;
});
)
~score.stop;

// Part B — explicit page breaks: a new PAGE at bars 3 and 5, still with the cursor.
(
s.waitForBoot({
	~score = MSScore(
		voices: [ "c5_4 e5 g5 e5 d5_4 f5 a5 f5 e5_4 g5 b5 g5 f5_4 a5 c6 a5 g5_1",
			"c3_4 b2 a g f_8 g a_4 f e g f e d a f d g1 c2_1"],
		clefs:  [ \treble, \bass ],
		braces: [[1,2]],
		notation: \lilypond,
		paginate: true, pageHeight: 900,
		systemBreaks: [2],                    // new line at bar 2
		pageBreaks:   [3, 5],                 // new page at bars 3 and 5
		tempo: 92, scale: 2.0,
		instruments: [\default, \default]
	);
	~score.play;
});
)
~score.stop;

// Part C — display only (no cursor, no playback): show page 1, then flip pages.
(
~score = MSScore(
	voices: [ (1..148).collect({ |i| ["c5","e5","g5","a5","f5","d5"].wrapAt(i) ++ "_8" }).join(" ") ],
	clefs:  [ \treble ],
	notation: \lilypond,
	paginate: true, pageHeight: 320,
	scale: 2.0, instruments: [\default]
);
~score.showPage(1);                           // engrave + show page 1 (no sound, no cursor)
)
~score.nextPage;  // -> page 2
~score.prevPage;  // -> back
