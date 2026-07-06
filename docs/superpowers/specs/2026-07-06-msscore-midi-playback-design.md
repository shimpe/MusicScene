# MSScore MIDI (hardware-synth) playback — design

**Goal:** Let `MSScore` play its voices through **external/hardware synths over MIDI** — not only the
built-in SuperCollider synths — with the backend chosen **per voice**, so a single score can mix an SC
synth voice with one or more MIDI voices, all under the same note-accurate follow cursor.

## Context

`MSScore` (msscore quark) turns Panola string(s) into a MusicScene notation score and plays the voices.
Today `pr_startPlayback` builds one pattern per voice with `Panola#asPbind` (SC synths), wraps them in a
single `Ppar`, and plays it on a shared `TempoClock`; a separate cursor routine drives the follow cursor
from that same clock. Panola already ships `asMidiPbind(midiOut, channel, …)` — it wraps `asPbind` and
overrides `\type = \midi`, `\midiout`, `\chan`, `\midicmd = \noteOn` (blanking `\instrument`) — so a voice
becomes a hardware-synth pattern. This feature wires that alternative into `MSScore` **per voice**.

**Where it lives.** Entirely in the **msscore quark** (`MSScore.sc`). No Panola change — `asMidiPbind`
already exists. Whelk doc comments on `MSScore.sc` stay current and `HelpSource/` is regenerated (see
`panola-quark-whelk-docs`).

**Pre-implementation check.** `MSScore.quark` pins `panola@tags/0.4.0`. Confirm `asMidiPbind` exists in
the `0.4.0` tag (it is a long-standing Panola method, predating the expression/slur work). If absent, the
pin must be bumped to a Panola tag that has it before this ships.

## API — four new constructor args (all parallel to `voices`)

`MSScore.new` gains four optional arguments, each an Array with one entry per voice (top staff first):

- **`backends:`** — `\internal` (SC synth via `asPbind`, today's behavior) or `\midi` (hardware via
  `asMidiPbind`). **Default: all `\internal`** — a score with no `backends:` plays exactly as before.
- **`midiOut:`** — a **single** `MIDIOut` (shared by every `\midi` voice) **or an Array** of `MIDIOut`
  (one per voice; the entry at a `\midi` voice index must be a live `MIDIOut`; entries at `\internal`
  voices are ignored). Required whenever any voice is `\midi`.
- **`channels:`** — the MIDI channel (0–15) for each voice; consulted only for `\midi` voices.
  **Default: `channels[i] = i`** (each voice on its own channel), so one shared multitimbral device gets
  a distinct channel per staff with no configuration. Override to e.g. all-`0` for a per-device array.
- **`wrap:`** — `nil` or a Function `{ |pattern, i| … newPattern }` per voice. After `MSScore` builds a
  voice's base pattern it applies `wrap[i].(basePattern, i)` (when non-nil) and uses the result. **Default:
  all `nil`.** This is the seam for per-note MIDI control (CC / sustain pedal / program change) — see
  "The wrap hook".

`instruments:` is unchanged and now documented as the **SC-synth** knob — used only for `\internal`
voices; ignored for `\midi` voices (whose sound is chosen on the hardware / by MIDI channel).

Ownership: the **user** creates and owns the `MIDIOut` (device names are machine-specific):
`MIDIClient.init; m = MIDIOut.newByName("INTEGRA-7", "INTEGRA-7 MIDI 1")`. `MSScore` never opens devices.

## Playback semantics

The per-voice pattern build moves into a small helper `pr_voicePatterns` (so it is testable in isolation):

```supercollider
pr_voicePatterns {
    ^voices.collect({ |p, i|
        var pat = (backends[i] == \midi).if(
            { p.asMidiPbind(this.pr_midiOutFor(i), channels[i], include_tempo: false) },
            { p.asPbind(instruments[i], include_tempo: false) }
        );
        wrap[i].notNil.if({ pat = wrap[i].value(pat, i) }, { pat });
    });
}

pr_midiOutFor { |i| ^midiOut.isArray.if({ midiOut[i] }, { midiOut }); }
```

`pr_startPlayback` becomes `player = Ppar(this.pr_voicePatterns).play(clock, quant: 0)` — otherwise
unchanged. Because every voice (internal or MIDI, wrapped or not) plays in the same `Ppar` on the same
`TempoClock`, **timing and the note-accurate follow cursor are unchanged** — the cursor routine is
backend-agnostic (it only reads `clock.beats`). `show` / notation is completely untouched: MEI engraving
is independent of the playback backend, so per-note dynamics, articulation and slurs still render exactly
as now.

## Validation & errors (at `init`)

- Any Array arg that is provided (`backends`, `channels`, `wrap`, plus the existing `instruments`/`clefs`)
  must have exactly `voices.size` entries; otherwise raise an informative error naming the arg and the
  expected length. Unprovided args take their per-voice defaults above.
- If any `backends[i] == \midi`:
  - `midiOut` must be non-nil, else error: *"MSScore: a \midi voice needs a midiOut (a MIDIOut, or an
    Array of MIDIOut)."*
  - if `midiOut` is an Array it must be **parallel to `voices`** (length `voices.size`); entries at
    `\internal` voices may be `nil`, but `midiOut[i]` must be non-nil for every `\midi` voice `i`, else
    error naming the offending voice index.
- `channels[i]` outside 0–15 for a `\midi` voice → `warn` and clamp (do not crash).

Validation is **duck-typed on non-nil**, not `isKindOf(MIDIOut)`, so the routing test can pass a
placeholder object (see Testing).

## Stop — hung-note safety

MIDI notes get scheduled note-offs by SC's `\midi` event type, but stopping mid-note (or a stuck note)
can leave a hardware note sounding. `stop` gains an all-notes-off sweep: after stopping the `player`, for
each `\midi` voice send `this.pr_midiOutFor(i).allNotesOff(channels[i])` (CC 123). Duplicate
device+channel pairs are sent once. The existing `Server.default.freeAll` (for `\internal` voices) and
`/ms/scene clear` remain. Order: stop clock/player/cursor → all-notes-off → freeAll → clear.

## The wrap hook — per-note MIDI control with MSScore

Without a seam, advanced MIDI (sustain pedal, CC, program change) could not combine with `MSScore`,
because `MSScore` owns the play loop and the cursor. `wrap:` provides that seam **inside** the loop, so
the cursor stays synced. Panola custom properties ride through `asMidiPbind` into the event, so a `Pfunc`
in the wrapped pattern can read them per note:

```supercollider
// pianoVoice notes carry @ped[0] … @ped[127]; the wrap turns them into CC 64 (sustain) on the hardware
MSScore(
    voices:   [ padVoice, pianoVoice ],
    clefs:    [ \treble, \bass ],
    backends: [ \internal, \midi ],
    midiOut:  integra,                 // single shared device (or [nil, integra] per-voice)
    channels: [ 0, 1 ],
    wrap: [ nil,
        { |pat, i| Pbindf(pat, \handle, Pfunc { |ev| integra.control(ev[\chan], 64, (ev[\ped] ? 0).asInteger) }) }
    ]
).play;
```

`MSScore` assigns no built-in meaning to `@ped` (or any custom property) — the `wrap` function does. This
generalizes to any per-note-property trick without `MSScore` knowing about pedals specifically.

## Interaction with existing features

- **Follow cursor / pagination / auto page-turn:** unchanged (clock-driven).
- **Per-note expression (dyn/art/slur):** unchanged — notation only; independent of backend.
- **`\internal`-only scores (the default):** byte-for-byte identical to today.
- **`totalBeats` / `showDelay` / `tempo`:** unchanged.

## Testing

A **headless** sclang routing test (no server, no MIDI hardware) — mirrors the existing `tools/`
sclang→assert harness. It constructs an `MSScore` with `backends: [\internal, \midi]`, a **placeholder**
`midiOut` object, `channels: [0, 1]`, and a `wrap` on the MIDI voice, then calls `pr_voicePatterns` and
materializes each voice's first event with `.asStream.next(())` (which computes the event dict **without**
playing it, so nothing is sent to a server or device). Asserts:

- internal voice event has `\instrument` set and **not** `\type == \midi`;
- MIDI voice event has `\type == \midi`, `\chan == 1`, and `\midiout == the placeholder`;
- the `wrap` was applied to the MIDI voice (e.g. the wrap adds a sentinel key the test detects);
- a `\midi` voice with `midiOut: nil` raises the documented error.

Regression: the existing panola_mei suite is unaffected (MSScore playback is not exercised there).

## Docs & example

- **Whelk** on `MSScore.sc`: document the new `*new` args (`backends`, `midiOut`, `channels`, `wrap`) and
  clarify `instruments` as SC-synth-only; add a `strong::MIDI / hardware synths::` paragraph to
  `[general]` (single-or-array `midiOut`, per-voice `channels`, the `wrap` seam for CC/pedal). Regenerate
  `HelpSource/` via gendoc.
- **Example:** a script showing a mixed `\internal` + `\midi` score. Because it needs hardware, the
  `MIDIClient.init` / `MIDIOut.newByName` / MIDI-voice lines are present but commented, with a runnable
  all-`\internal` fallback, so the file loads without a device attached.

## Public API summary

No new methods on the public surface beyond the four constructor args. `play` / `stop` / `show` / `mei`
signatures are unchanged; `stop` gains the all-notes-off behavior. New private helpers: `pr_voicePatterns`,
`pr_midiOutFor`.

## Scope

- **In:** per-voice `backends` (`\internal`/`\midi`); `midiOut` as a single device or a per-voice Array;
  per-voice `channels` (default = voice index); per-voice `wrap` hook; init validation; all-notes-off on
  `stop`; whelk docs + regenerated HelpSource; a mixed-backend example; a headless routing test.
- **Out (later / not planned):** `MSScore` auto-opening MIDI devices; MIDI-clock / transport output to
  hardware; any built-in semantics for pedals/CC/program-change (the `wrap` hook is the general
  mechanism); any change to notation, the cursor, or `\internal` playback.
