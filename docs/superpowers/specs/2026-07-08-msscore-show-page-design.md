# MSScore — display a given page (no cursor, no playback) — Design

**Date:** 2026-07-08
**Component:** MSScore quark (`MSScore.sc`); MusicScene example + docs
**Status:** Approved (brainstorm)

## Goal

A one-call way to **display a specific page** of a score in MusicScene — no follow cursor,
no audio playback, just the engraved page — plus lightweight page navigation:

```
~score = MSScore(voices: [...], paginate: true, pageHeight: 900);
~score.showPage(3);   // display page 3: no cursor, no synths, no clock
~score.showPage;      // page 1, display only
~score.nextPage;      // -> page 4
~score.prevPage;      // -> page 3
~score.page(1);       // jump to page 1
```

## Background: what already exists

- **`show`** builds the MEI and sends the notation setup over OSC (create `notation` node,
  `background`, `scale`, `pos`, `cursor show <showCursor>`, `paginate <flag> <pageHeight>`,
  `addressable 1`, `notationData mei <m>`) from a `Routine`. It does **not** play — `play` is
  `show` + a delayed `pr_startPlayback`. So display-without-playback already exists; what's
  missing is (a) forcing the cursor off and (b) going to a chosen page.
- **Godot side needs no change.** `OscDispatcher` routes `page` / `nextpage` / `prevpage` to
  `MSNotationObject._go_page`, which is **1-based**, **clamps** out-of-range to `[1, pages]`,
  and — when the score isn't paginated — re-renders the requested page. `paginate` defaults
  true, so distinct pre-rendered pages are the normal case.
- **Test seam:** `tools/msscore/test_midi_routing.py` points MSScore's `engine` NetAddr at
  sclang's own port (`NetAddr.langPort`) and `OSCdef`-captures the emitted messages — no Godot
  or audio server needed. `showPage` is tested the same way.

## API

Four public methods on `MSScore`:

| Method | Effect |
|--------|--------|
| `showPage(pageNumber = 1)` | Display the score with the cursor **off** and **no playback**, then go to `pageNumber`. The display-only entry point. |
| `page(pageNumber = 1)` | On an already-shown score, jump to `pageNumber` (`/ms/scene/<id> page n`). |
| `nextPage` | Flip forward (`/ms/scene/<id> nextpage`). |
| `prevPage` | Flip back (`/ms/scene/<id> prevpage`). |

Page numbers are **1-based**; out-of-range is clamped by MusicScene. Distinct pages require a
paginated score (`paginate` true, the default); with `paginate` false MusicScene re-renders the
requested page (usually a single page → clamps to 1).

## Behavior of `showPage`

- Emits the **same** notation setup as `show`, but with the cursor line forced **off**
  (`cursor show 0`) regardless of the `showCursor` instance var — "no cursor" was the explicit
  requirement.
- Starts **no** playback: no `pr_startPlayback`, no `clock` / `player` / `cursorRoutine`. After
  `showPage`, those runtime-state vars stay `nil`.
- Sends the page jump **after** the notation loads: inside one `Routine` it emits the setup,
  waits `showDelay` (the existing render-settle delay `play` already uses), then sends `page n`.
  Non-blocking, like `show` / `play`.
- `stop` still works to clear the scene (`/ms/scene clear`); it is a no-op for the (absent)
  playback state.

## Implementation (`MSScore.sc`)

DRY + byte-safe refactor so `show` and `showPage` share one setup emitter:

1. **Extract `pr_emitSetup(cursorOn)`** — a private method containing the exact body of the
   current `show` `Routine` (the `snd` closure + the eight `snd.(...)` calls), with the cursor
   line driven by the `cursorOn` argument instead of `showCursor`. It is meant to run **inside**
   a `Routine` (it uses `0.02.wait`).
2. **`show`** becomes `Routine({ this.pr_emitSetup(showCursor); }).play;` — emits byte-identical
   messages (guarded by the existing `test_show_cursor_hidden` / `test_show_cursor_default`).
3. **`showPage(pageNumber = 1)`** — `Routine({ this.pr_emitSetup(false); showDelay.wait; this.page(pageNumber); }).play;`
4. **`page(pageNumber = 1)`** — `engine.sendMsg("/ms/scene/" ++ id, "page", pageNumber);`
5. **`nextPage`** — `engine.sendMsg("/ms/scene/" ++ id, "nextpage");`
6. **`prevPage`** — `engine.sendMsg("/ms/scene/" ++ id, "prevpage");`

The nav methods are single synchronous sends (no `Routine` needed). Each new method gets a whelk
doc block; regenerate `MSScore.schelp` via `gendoc.bat`.

## Out of scope

- Any Godot / MusicScene-side change (the page verbs already exist).
- Playback, cursor-follow, or page-turn-on-play behavior (unchanged; that's `play`).
- Querying the page count from SC (`pages` / `currentpage` replies exist over OSC already; not
  wrapped here — YAGNI).

## Testing

New `tools/msscore/test_show_page.py`, using the `OSCdef`-capture pattern (set `showDelay: 0.1`
so the test is fast; point `listenPort: NetAddr.langPort`):

1. **showPage emits page + cursor-off, no playback** — `s = MSScore(..., id: "scorePage", showDelay: 0.1, listenPort: NetAddr.langPort)`, capture `/ms/scene/scorePage` and `/ms/scene/scorePage/cursor`; `s.showPage(2)`; wait ~0.5 s; assert a captured `page` message with arg `2`, a `cursor show 0` message, and `s.player.isNil` and `s.clock.isNil` (no playback started).
2. **nav methods** — `s.page(4)`, `s.nextPage`, `s.prevPage`; assert the captured verbs/args (`page 4`, `nextpage`, `prevpage`) on `/ms/scene/<id>`.

Run: `py -m pytest tools/msscore/ tools/panola_mei/ -q` (full suite green; the `show` cursor
tests must still pass, proving the refactor kept `show` byte-identical).

## SuperCollider example

Per [[illustrate-features-in-examples]]: add `examples/supercollider/example_show_page.scd` —
build a multi-page score (a long single voice, or reuse a longer Panola string) with
`paginate: true` and a small `pageHeight`, then `showPage(2)` to display a chosen page with no
cursor/playback, and demonstrate `nextPage` / `prevPage` in comments. Header explains it is a
pure display mode (contrast with `play`).

## Docs

whelk doc blocks for `showPage` / `page` / `nextPage` / `prevPage`; regenerate `MSScore.schelp`
(`Done.`, no `ERROR`). Add a CHANGELOG entry on ship. No backlog change.

## Files

- `Classes/MSScore.sc` — `pr_emitSetup`, refactor `show`, add `showPage`/`page`/`nextPage`/`prevPage` + whelk docs.
- `HelpSource/Classes/MSScore.schelp` — regenerated.
- `tools/msscore/test_show_page.py` — new tests.
- `examples/supercollider/example_show_page.scd` — new example.
- `CHANGELOG.md` — on ship.
