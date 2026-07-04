# Design — Advanced Topics Tutorial (`ADVANCED.md`)

**Date:** 2026-07-04 · **Status:** approved, ready for planning

## Motivation

`README.md` (flat reference) and `TUTORIAL.md` (numbered narrative walkthrough) cover the basic command
grammar of gscore's more advanced features, but not their *mechanics* or edge cases. Several genuinely
surprising behaviors are undocumented anywhere — e.g. `bindGroup` bypasses the permission gate, `bindAll`
silently no-ops on anything but `meta`, input-event `payload` is stored but never applied, `/signal`
drops a signal's 5th+ argument and collapses `Vector2` to `.x`. This tutorial gathers the obscure topics
in one place and goes deep on how they actually work, so an advanced user can rely on exact behavior.

## Deliverable

A single new file **`ADVANCED.md`** at the repo root (peer of `README.md`/`TUTORIAL.md`), linked from
`TUTORIAL.md`'s "Next steps" section and mentioned in one line of `README.md`. It is **additive** — no
existing docs are rewritten; where basics are already covered, the new doc cross-references them and
focuses on depth.

## Style & conventions

- **Assumes the reader has read `TUTORIAL.md`.** A one-paragraph preamble states this and that the doc
  reuses the tutorial's `s(address, *args)` Python helper (defined in TUTORIAL §2). No re-teaching of
  setup, ports, or the `s()` helper.
- Every example is a **Python `s(...)` call**, matching `TUTORIAL.md`, with expected replies/events shown
  as inline comments: `# -> /gscore/reply <topic> …` or `# -> <address> <args…>`.
- Each section is a `## N. Title` heading (continuously numbered 1–9 across the three parts). Where a
  subtle grammar needs it, a short raw-address line may appear in a comment, but the runnable example is
  Python.
- Each section ends with a **> Gotchas** blockquote carrying the undocumented facts (the value-add).
- Tone/format matches `TUTORIAL.md` (prose + fenced Python blocks + occasional Markdown tables).

## Structure — 9 sections in 3 parts

### Part A — Notation (score overlays)

**1. Annotations.** Freeform text/glyph labels stamped on a notation object, in page-normalized `[0,1]`
rect space; purely decorative (no hit-testing/bindings). Commands (address-embedded id + subcommand):
`/gscore/scene/<id>/annotation <aid> text "<str>" | rect <x> <y> <w> <h> | glyph <name> | color <r> <g> <b> [a] | show | hide | del`,
and query `/gscore/scene/<id>/annotations`. Cover: auto-creation on first reference to an unseen `<aid>`
(no explicit "new"); default rect `(0.1,0.1,0.2,0.1)`; `text` wins over `glyph`; glyph renders as its
literal name unless a SMuFL font is set on `ThemeDB` (2D) — 3D uses a `Label3D`; annotations re-scale with
the page automatically. Reply: `/gscore/reply annotations <id> <aid…>` (ids only — no text/rect echoed).
> Gotchas: auto-create-on-first-use; `text` overrides `glyph`; glyph is drawn as text without a bundled
> music font; no permission gating (pure presentation).

**2. Addressable / mpos scores.** The *other* notation sense — auto-extracting clickable regions from the
engraved music. `/gscore/scene/<id> addressable 1` **before** loading a source makes gscore generate
`m1..mN` measure regions (MuseScore/MusicXML via `.mpos`/`.spos`) or `n0..nK` note regions (LilyPond
timing-tagger / Verovio timemap). Query with the `measures` / `elements` verbs (reply carries real
geometry + time data). Explicitly contrast with §1: annotations are *manually placed, decorative*;
addressable regions are *auto-extracted, clickable, time-tagged*. Two independent features that share the
word "notation overlay."
> Gotchas: `addressable 1` must be set before the source loads; the extraction backend depends on the
> source format (MuseScore mpos vs LilyPond vs Verovio); `measures`/`elements` return geometry, unlike the
> `annotations` reply.

### Part B — Discovering & binding existing nodes

**3. `discover`.** Introspect the running scene tree to find bindable nodes. Forms: `discover` (all),
`discover group <g>`, `discover type <ClassName>`, `discover meta <key> [value]`. Reply is **one message
per node**: `/gscore/reply discover <suggested_id> <path> <class> <name>`. `suggested_id` = the node's
current OSC id if already bound, else its `OscExposable.suggested_id()`, else `name.to_snake_case()`.
Worked flow: `discover type Button` → pick one → `bind`. 
> Gotchas: read-only and **ungated** — returns *every* node (exposed or not); `suggested_id` is only a
> suggestion, nothing is bound until you call `bind`.

**4. `bindAll` / `bindGroup`.** Bulk binders (recap `bind`/`bindRel` first). `bindGroup <osc_group> <godot_group>`
binds every node in a Godot group, assigning ids `<osc_group>.<i>` (0-based), ownership `group_binding`;
reply `/gscore/reply bindGroup <sub_id…>`. `bindAll meta <key> [value]` binds every scene node whose
metadata matches, via the normal permission-checked `bind()`. Also: **auto-bind at startup** — two frames
after ready, gscore binds every `OscExposable` node (with `osc_auto_bind and osc_allow_bind`) and every
`osc_expose`-meta node, **once** (never re-scanned; nodes added later must be bound explicitly).
> Gotchas: **`bindGroup` bypasses the permission check entirely** (binds group members whether exposed or
> not); `bindAll` only supports the `meta` form — any other first arg silently no-ops (no error, no reply);
> auto-bind runs once at startup, not on later node additions.

**5. Safety & the permission model.** The capability gate protecting *pre-existing* project nodes (gscore's
own `new`/`instantiate` objects are always controllable). Five global kill-switches (`bind_existing`,
`instantiate`, `call_methods`, `set_props`, `free_nodes` — defaults all `true` except `free_nodes`=`false`)
seeded from Project Settings; plus `developer_mode` (off by default) which short-circuits the per-capability
checks; plus a scene/prefix whitelist for `instantiate` (built-in `res://osc_spawnable/`). Opt-in a node
with the `OscExposable` child component (`osc_id`, `target_path`, `osc_methods`, `osc_properties`,
`osc_signals`, `osc_allow_free`) or `set_meta("osc_expose", true)`. Runtime toggles:
`/gscore/app/permissions bindExisting|instantiate|callMethods|setProps|freeNodes <0|1>`,
`/gscore/app/developer <0|1>`, `/gscore/assets/allowScene "<path>"`, `/gscore/assets/allowPrefix "<prefix>"`,
`/gscore/assets/listAllowed`. Include a compact **gated-vs-not table** (bind/bindRel, bindGroup, bindAll,
instantiate, prop-set, call, free, del, getProp, signal, on/off/payload, discover).
> Gotchas: `bindGroup` skips the gate (see §4); **`getProp` (read) and `/signal` forwarding are unrestricted**
> even outside developer mode — `osc_properties`/`osc_signals` gate `prop`-set / `call` allow-lists but are
> *not* consulted by `getProp` or `/signal`; the five kill-switches override even `developer_mode` (a `false`
> switch blocks the op regardless).

### Part C — Events & forwarding

**6. `payload`.** Customize the argument list of an outbound event previously registered with `/on`, without
touching the registration. `/gscore/scene/<id>/payload <event> <token…>`. Token vocabulary (case-insensitive):
`self other x y z worldx/y/z vx vy vz speed relativespeed intensity impulse normalx/y/z otherx/y/z othervx/vy/vz
otherspeed time beat mass angle angularvelocity layer`; a token starting with `=` or `'` is a **literal**
(rest emitted verbatim); unknown tokens yield `0`. With no `payload` set, the binding falls back to
`DEFAULT_FIELDS = self other intensity x y vx vy time`. Show before/after: registration + `payload self other
otherspeed =bounce` → `/synth/hit note1 floor 0.83 bounce`. Note the always-on canonical
`/gscore/event/physics <event> <self> <other> <intensity> <x> <y> <vx> <vy>` emitted regardless of bindings.
> Gotchas: `payload` requires a prior `on` for that event (else silent no-op); **for input events
> (`click/down/up/drag/enter/leave`) `payload` is stored but never applied** — those always emit
> `[<id>, nx, ny]` (or `[<id>, region_id, u, v]` for a region hit).

**7. Signal forwarding.** Two paths: (a) the named event families (§6, via `on`/`payload`), and (b) the generic
`/gscore/scene/<id>/signal <godot_signal> <target> [payload <token…>]` escape hatch that connects *any* signal
on the bound node and relays its args. Default emission `<osc_id> <signal_name> <sig_args…>`; custom payload
tokens `self | signal | value | args | argN` (unmatched token → literal). Re-sending `/signal` for the same
signal replaces the prior binding.
> Gotchas: **no permission check** (any existing signal can be forwarded, dev-mode or not; `osc_signals` is
> informational only); connects by probing the signal's declared arity — **signals with 5+ args are connected
> via the 4-arg handler and the extras dropped**; a `Vector2` arg is **collapsed to its `.x`** (y dropped),
> other non-primitives stringified; `off` does **not** disconnect a `/signal` — it's removed only by
> re-registering that signal or on object teardown (unbind/del/free/clear).

**8. Emission modes & throttling.** Options on `/on ... <opt> <val>`: `mode immediate|queued|bundle|quantized`
(+ `quantizeGrid <beats>`), and the filters `cooldown <s>`, `maxRate <hz>`, `minIntensity <v>`, plus `other
<id-glob>` and `layer`. `queued` batches to end-of-frame sends; `bundle` packs the frame into one OSC bundle;
`quantized` holds each message until `now_beat >= next grid line` (buffer cap 512, oldest dropped). Tie back to
§6 (payload shapes each queued/bundled/quantized message).
> Gotchas: `quantized` depends on the transport/beat clock running; the quantized buffer silently drops the
> oldest message past 512; `other <glob>` filters which *other* body triggers the event (e.g. `peg*`).

**9. Continuous physics events.** Beyond the discrete `collisionEnter/Exit`, `areaEnter/Exit`, `sleep`, `wake`:
the per-step continuous family `velocityAbove/Below <v>`, `yAbove/Below <y>`, `collisionStay`, `areaStay`. These
are edge-detected (`*Above`/`*Below` fire once on threshold crossing, tracked via binding state) or per-other
tracked (`*Stay` re-emits per contacting body). All use `on`/`payload` (§6), never `/signal`.
> Gotchas: `*Above`/`*Below` are edge-triggered (one event per crossing, not per frame while past the
> threshold); `*Stay` emits per other-body and prunes bodies that leave.

## Cross-links (small edits to existing docs)

- `TUTORIAL.md` "## Next steps": add a bullet pointing to `ADVANCED.md`.
- `README.md`: one line near the top docs list / near the permissions or events section pointing to
  `ADVANCED.md` for deep mechanics.

## Verification

Docs must be accurate. After writing `ADVANCED.md`, run a **docs-vs-code fact-check pass** (a review agent
that verifies every command address, argument order, default value, reply/event shape, and each Gotcha
against the actual source — the same approach used for the 0.10.0/0.11.0 doc tasks). Fix any mismatch.
There is no automated test for prose; the fact-check pass is the gate.

## Scope / non-goals

- One file, additive; no restructuring of `README.md`/`TUTORIAL.md` beyond the two cross-link lines.
- Not a full API reference (README already is); depth on the nine listed topics only, with cross-references
  for basics.
- No version bump (docs-only, no behavior change).

## Rollout

New branch `docs/advanced-topics-tutorial` (off `main`). Merge/PR decided when finishing the branch.
