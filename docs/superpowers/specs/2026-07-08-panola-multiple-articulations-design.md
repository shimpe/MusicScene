# Multiple Articulations Per Note — Design

**Date:** 2026-07-08
**Component:** Panola quark (`PanolaParser.sc`, `PanolaMEI.sc`)
**Status:** Approved (brainstorm)

## Goal

Let a single note or chord carry **several articulations at once** — e.g. a note that is
both *staccato* and *accented* — using a `+`-separated list inside one `@art` value:

```
c5_4@art^staccato+accent^     // -> <note ... artic="acc stacc" .../>
```

This is a very common notation need (staccato+accent, tenuto+accent, marcato+staccato, …).

## Background: what already works, what is missing

The MEI generator is **already multi-articulation capable**. In `PanolaMEI.sc`,
`annotateExpression` accumulates a `Set` of MEI artic codes and emits them
space-separated (`artic="acc stacc"`). Today that set can only reach more than one member
by **overlapping sticky ranges**:

```
c5_4@art[acc:on] d5@art[stacc:on] e5@art[acc:off] f5   // d5 renders artic="acc stacc"
```

What is missing is a way to put **two articulations on a *single* note in one shot**.
There is no input syntax for it:

- The property-value grammar (`PanolaParser.sc`) allows only one token per value
  (`[a-zA-Z][a-zA-Z0-9:]*`), with no separator for multiple names.
- Even if you wrote `@art^stacc^@art^acc^`, the two `@art` props collapse to **last-wins**
  in `customPropertyPattern` (the shared property→pattern layer that also drives synth
  automation such as amp glides), so only `acc` would survive.

Supported articulation names (from `artCode` in `PanolaMEI.sc`, unchanged):
`staccato/stacc`, `staccatissimo/stacciss`, `accent/acc`, `tenuto/ten`,
`marcato/marc`, `spiccato/spicc`.

## Approach

Two surgical changes, both localized. No change to the synth/playback path, and **no
change to MSScore** (it calls `Panola.scoreAsMEI`, so it inherits this for free).

### 1. `PanolaParser.sc` — allow `+` inside a property value

The property value is parsed in three places (animated `{}`, static `[]`, one-shot `^^`),
each using `ScpRegexParser("[a-zA-Z][a-zA-Z0-9:]*")`. Extend the character class to include
`+`:

```
[a-zA-Z][a-zA-Z0-9:]*   ->   [a-zA-Z][a-zA-Z0-9:+]*
```

so `staccato+accent` parses as a **single** `@art` value. Because it is one `@art` prop,
it flows untouched through `customPropertyPattern("art")` → `eventsOf` → `ev[\art]` — no
last-wins collapse, no risk to the synth-automation path.

The `+` only ever appears in a value that **starts with a letter**; the value parser tries
the float parser first, so numeric values (`@amp{0.5}`) are unaffected. The change applies
to every property form and every property name, which is harmless — only articulation
assigns meaning to `+`; any other property just carries a literal string value it already
tolerated.

### 2. `PanolaMEI.sc` — split `ev[\art]` on `+` in `annotateExpression`

Rework the ~15-line articulation block so it **splits the art value on `+` into parts** and
routes each part through the existing logic:

- a part containing `:` is a **sticky toggle** (`name:on` / `name:off`) applied to the
  carried-forward `artSet`, and — preserving current behavior — applied only when the whole
  `art` value **changes** from the previous note (a static `[]` value carries forward, so
  re-applying every note would be redundant, and re-applying `:off` would be wrong);
- a **bare** part (no `:`) adds its code to **this note's** set only.

Set accumulation, `sort`, and `join(" ")` → `articStr` stay identical, so ordering is
deterministic (`accent+staccato` and `staccato+accent` both yield `artic="acc stacc"`),
duplicates dedup via the `Set`, and empty parts (a trailing `+`) are skipped. The
unknown-articulation warning is preserved, now per part.

Reference implementation:

```supercollider
var annotateExpression = { |events|
    var artSet = Set[], prevArt = "", prevDyn = "";
    events.do({ |ev|
        var art = ev[\art] ? "", dyn = ev[\dyn] ? "", noteSet, parts;
        parts = (art == "").if({ [] }, { art.split($+) });   // "staccato+accent" -> ["staccato","accent"]
        // sticky on/off toggles: apply only when the whole art value CHANGES (a static/[] value
        // carries forward, so re-applying it every note would be redundant / wrong for :off)
        if (art != prevArt) {
            parts.do({ |p|
                if (p.includes($:)) {
                    var seg = p.split($:), code = artCode.(seg[0]);
                    if (code.notNil) {
                        (seg[1] == "on").if({ artSet = artSet.add(code) }, { artSet.remove(code) });
                    } { ("PanolaMEI: unknown articulation '" ++ seg[0] ++ "'").warn };
                };
            });
        };
        prevArt = art;
        noteSet = artSet.copy;
        // bare names (no :on/:off) add to THIS note only
        parts.do({ |p|
            if ((p != "") and: { p.includes($:).not }) {
                var code = artCode.(p);
                if (code.notNil) { noteSet = noteSet.add(code) } { ("PanolaMEI: unknown articulation '" ++ p ++ "'").warn };
            };
        });
        ev[\articStr] = noteSet.asArray.sort.join(" ");
        ev[\dynMark] = ((dyn != prevDyn) and: { dyn != "" }).if({ dyn }, { nil });
        prevDyn = dyn;
    });
    events;
};
```

## Semantics summary

| Input | Result |
|-------|--------|
| `@art^staccato+accent^` (one-shot) | `artic="acc stacc"` on that note only |
| `@art^staccato:on+accent^` (one-shot) | staccato **passage** starts here, accent on **this** note only |
| `@art[staccato:on+accent]` (static) | both carry forward from here (static = passage) |
| `@art^accent+staccato^` | `artic="acc stacc"` (sorted — order-independent) |
| `@art^staccato+staccato^` | `artic="stacc"` (Set dedups) |
| `@art^staccato+bogus^` | `artic="stacc"` + one warning for `bogus` |

Playback is **unchanged**: `\art` still passes through the Pbind as a symbol; articulations
remain notation-only (staccato does not auto-shorten notes), exactly as single
articulations behave today.

## Out of scope

- Playback semantics (staccato shortening, accent velocity). Notation only.
- Any new articulation names beyond the existing `artCode` table.
- MSScore API changes (none needed).

## Testing

Extend `tools/panola_mei/test_expression.py` (its `ART` dict + `test_articulation`), which
runs sclang → Verovio and asserts on the MEI string:

1. **Combined one-shot** — `c5_4@art^staccato+accent^ d5 e5 f5` → exactly one
   `artic="acc stacc"`, and `d5`/`e5`/`f5` carry no `artic`.
2. **Combined + sticky** — `c5_4@art^staccato:on+accent^ d5 e5 f5` → first note
   `artic="acc stacc"`, following notes `artic="stacc"` (staccato persists, accent does not).
3. **Order independence** — `c5_4@art^accent+staccato^` → `artic="acc stacc"` (sorted).
4. **Regression** — the existing `oneshot`/`passage`/`layered` assertions still pass
   unchanged.

Run: `py -m pytest tools/panola_mei/ tools/msscore/ -q` (full suite green).

## Docs

Per the standing quark-doc rule: update the `@art` prose in the `PanolaMEI.sc` `[general]`
doc block and the `scoreAsMEI` arg docs (and `Panola.sc` if it references `@art`), then
regenerate schelp via `gendoc.bat` and confirm `Done.` with no `ERROR`.

## Files

- `Classes/PanolaParser.sc` — value regex, 3 occurrences (`+` in char class).
- `Classes/PanolaMEI.sc` — `annotateExpression` split-on-`+`; `@art` doc prose.
- `HelpSource/Classes/PanolaMEI.schelp` (+ `Panola.schelp` if touched) — regenerated.
- `tools/panola_mei/test_expression.py` — new combined-articulation cases.
