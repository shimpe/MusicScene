# Panola / MSScore Lyrics — Design

**Date:** 2026-07-10
**Status:** approved (pending written-spec review)

## Goal

Add sung lyrics to engraved scores. A voice's syllables are authored as a
**separate line parallel to the pitch string** (never inline in the Panola
string), aligned syllable-by-syllable to the non-rest notes, and engraved as MEI
`<verse>/<syl>`. Lyrics are **notation-only** — they never affect sound, never
enter `asPbind`.

## Decisions (from brainstorming)

1. **Separate parallel line**, not inline `@lyric` (the property value regex
   `[a-zA-Z][a-zA-Z0-9:+]*` bans punctuation and spaces).
2. **Per staff, a list of verse lines** → stacked `<verse n="1">`, `<verse n="2">`, …
3. **Standard fidelity**: hyphenation + melisma. No extender lines (the "rich" tier).
4. **Backslash escaping** for whitespace / quotes / metacharacters inside a syllable.

## 1. Authoring API

A new **trailing** argument `lyrics` (default `nil`) is threaded, unchanged, through
every engraving surface. `nil` everywhere ⇒ output is **byte-identical** to today.

```supercollider
// PanolaMEI.scoreAsMEI / Panola.scoreAsMEI: lyrics is indexed by staff (parallel to voices)
Panola.scoreAsMEI(voices, changes, clefs, braces, pageBreaks, systemBreaks,
    lyrics: [
        [ "Twin-kle twin-kle lit-tle star,",   // staff 1, verse 1
          "Up a-bove the world so high," ],    // staff 1, verse 2
        nil                                     // staff 2, no lyrics
    ]);

// single voice
Panola("c d e f").asMEI("4/4", \Cmajor, \treble, lyrics: [ "one two three four" ]);

// MSScore constructor
MSScore(voices: [...], lyrics: [[ "Twin-kle twin-kle lit-tle star," ]], ...);
```

**Shape.** `lyrics` is an Array indexed by staff (same order as `voices`). Each
entry is one of:

- `nil` — no lyrics on that staff.
- an Array of verse-line Strings — `[ "verse 1", "verse 2", … ]`.
- a bare String — shorthand for a single verse (`"foo"` ≡ `["foo"]`).

`lyrics` shorter than `voices` ⇒ the remaining staves get none. `lyrics` longer
than `voices` ⇒ the extra entries are ignored with a `warn`.

## 2. Lyrics-line grammar & alignment

Each verse String is tokenized **character by character** (a naive `split` cannot
honour escapes). Three metacharacters are recognized **only when unescaped**:

| Unescaped | Meaning |
| --- | --- |
| whitespace (run) | word separator (also ends the current syllable) |
| `-` | syllable separator inside a word (a hyphen is drawn) |
| `_` (a whole whitespace-delimited token, by itself) | melisma slot — the next note holds the previous syllable |

**Backslash escaping.** `\x` contributes the literal character `x` to the current
syllable and suppresses any metacharacter meaning. So `\ ` = a literal space
inside a syllable, `\-` = a literal hyphen, `\_` = a literal underscore (never a
melisma), `\"` = a literal quote, `\\` = a literal backslash. Apostrophes and
other punctuation are ordinary characters and need **no** escaping (`don't`,
`sayin'`, `star,`).

> SC-source caveat: a backslash in a SuperCollider string literal is itself an
> escape. To deliver a literal backslash-space to the tokenizer, the source must
> read `"\\ "`. The tokenizer operates on the runtime string, not the source.

**Alignment.** Tokenizing a verse yields a flat stream of *slots*, each either a
syllable (with a word-position) or a melisma. Walk the voice's events in order;
each **non-rest** note/chord consumes the next slot:

- syllable slot → a `<syl>` on that note.
- melisma slot (`_`) → the note gets **no** `<verse>` (holds the previous syllable).
- **rest** → consumes no slot (skipped).

**Word position.** A word (whitespace-delimited, hyphen-split) with more than one
syllable gives its first syllable `wordpos="i" con="d"`, each middle syllable
`wordpos="m" con="d"`, and its last syllable `wordpos="t"` (no `con`). A
single-syllable word gets neither attribute. `con="d"` is what makes Verovio draw
the connecting hyphen.

**Mismatch.** More slots than notes ⇒ the extras are dropped with a `warn`
(`"PanolaMEI: N lyric syllables past the end of voice V verse W — dropped"`).
Fewer slots than notes ⇒ the trailing notes are left blank, **silently** (a
natural instrumental tail).

## 3. MEI output

A `<note>` / `<chord>` that carries a syllable stops being self-closing:

```xml
<note dur="4" oct="5" pname="c"><verse n="1"><syl wordpos="i" con="d">Twin</syl></verse></note>
<note dur="4" oct="5" pname="g"><verse n="1"><syl>star,</syl></verse></note>
```

Multiple verses ⇒ multiple `<verse n="1">`, `<verse n="2">`, … inside the one
note. `<rest>` never carries lyrics.

**Tied / split notes.** A note split across a barline becomes several tied
fragments. The syllable lands on the **first fragment only**, reusing the existing
guard `tie.isNil or: { tie == "i" }` (the same guard articulation already uses).
The carried remainder of a split note must have its `\lyrics` cleared, exactly as
`\dynMark` / `\slur` / `\hairpin` are cleared at `PanolaMEI.sc:376`.

**Byte-identity.** When an event has no syllable (lyrics `nil`, a melisma, a rest,
or a trailing blank note), `meiElement` emits the **old self-closing form**
unchanged. With `lyrics: nil` no `<verse>` is ever produced and every existing
score renders byte-for-byte as before.

## 4. Components / files

All lyrics semantics live in **PanolaMEI** (which already owns `@dyn`/`@art`/slur/
hairpin/clef). Panola and MSScore only pass `lyrics` through — a smaller PanolaLyrics
class was rejected (the grammar is trivially small: whitespace / `-` / `_` / `\`).

- **`PanolaMEI.sc`**
  - `*pr_parseLyricLine(line)` — pure classmethod, the char-level tokenizer.
    Returns an Array of slots `( syl: "text", wordpos: "i"|"m"|"t"|nil, con: "d"|nil )`
    or `( melisma: true )`. Unit-testable in isolation.
  - `alignLyrics(events, verseLines)` — attaches `ev[\lyrics]` (an Array indexed by
    verse; each entry a slot or `nil`) to each event, skipping rests.
  - `meiElement` gains the ability to emit `<verse>` children when the event has a
    syllable **and** the tie guard allows it; the note/chord becomes non-self-closing
    in that case only.
  - `scoreAsMEI` gains the trailing `lyrics` arg; `eventsOf`/`voiceToMeasures`
    receive the per-voice verse lines; clear `\lyrics` on the carried remainder at
    the split site.
- **`Panola.sc`** — `asMEI` and `*scoreAsMEI` gain a trailing `lyrics` arg, passed through.
- **`MSScore.sc`** — a `lyrics` instance variable, a trailing `*new`/`init` arg, and
  `mei` passes it to `Panola.scoreAsMEI`.

## 5. Testing

- **Tokenizer (`pr_parseLyricLine`)**: hyphen → wordpos `i`/`m`/`t` + `con`;
  single-word → no wordpos; standalone `_` → melisma; `\ ` → space in a syllable;
  `\-`/`\_` → literal; `\"`/`\\` → literal quote/backslash; apostrophe unescaped.
- **Full render**: `<syl>` count vs non-rest notes; melisma → no `<verse>` on that
  note; rest → skipped; tied note → syllable on first fragment only; multi-verse →
  N `<verse>` per note with correct `n`; overflow → warn + drop; underflow → blank.
- **Byte-identity**: an existing score with `lyrics: nil` renders identical bytes.
- **MSScore**: `lyrics:` reaches `.mei`; per-staff `nil` leaves that staff unsylled.

## 6. Standing-rule follow-through (not optional)

- Update whelk doc comments on every edited `.sc` (Panola `asMEI`/`scoreAsMEI`,
  PanolaMEI `scoreAsMEI`, MSScore) **and regenerate the schelp** via whelk.
- Add a runnable `.scd` example demonstrating lyrics (a verse with hyphenation,
  melisma, an escaped space, and two verses) — every feature ships in an example.
- Mention lyrics in the MusicScene README and TUTORIAL notation sections.
- Version bump / CHANGELOG happen at release time (separate, on request).

## Out of scope (YAGNI)

Extender lines (`__`), elision, inline `@lyric`, per-syllable font/style, lyrics in
`asPbind`, right-to-left text.
