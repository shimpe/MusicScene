# MusicScene — Advanced Topics

A deep-mechanics companion to **[TUTORIAL.md](TUTORIAL.md)**. The tutorial teaches the everyday
commands; this document goes underneath them — the exact wire syntax, the defaults, and the edge cases
that will surprise you if you don't know them. Each section ends with a **Gotchas** box collecting the
non-obvious behavior.

This doc assumes you've read the tutorial and reuses its tiny Python helper `s(address, *args)` (defined
in TUTORIAL §2 — it sends one OSC message and prints anything MusicScene sends back). Replies and events are
shown as `# -> …` comments. For the flat command reference see **[README.md](README.md)**.

**Contents**

- Part A — Notation overlays: [1. Annotations](#1-annotations) · [2. Addressable scores](#2-addressable-scores-mpos)
- Part B — Discovering & binding: [3. discover](#3-discover) · [4. bindAll / bindGroup](#4-bindall--bindgroup) · [5. Safety & permissions](#5-safety--the-permission-model)
- Part C — Events & forwarding: [6. payload](#6-payload) · [7. Signal forwarding](#7-signal-forwarding) · [8. Emission modes & throttling](#8-emission-modes--throttling) · [9. Continuous physics events](#9-continuous-physics-events) · [10. Collision reactors](#10-collision-reactors-bouncers--portals)

---

## Part A — Notation overlays

MusicScene has **two unrelated things** that both draw "on top of" a rendered score, and they're easy to
confuse: **annotations** (§1) are freeform labels *you* place; **addressable regions** (§2) are clickable
hotspots MusicScene *extracts* from the engraved music. Different commands, different purposes.

## 1. Annotations

An annotation is a freeform **text or glyph label** drawn over a notation object, positioned in the same
page-normalized `[0,1] × [0,1]` space as everything else on the page. It's purely decorative: it has no
click bindings and isn't hit-tested. Use it to stamp "Allegro", a rehearsal letter, a fingering, or a
SMuFL glyph name onto the score.

Every subcommand is `annotation <aid> <cmd> …`, where `<aid>` is an id you choose. The annotation is
**created automatically the first time you name it** — there's no "new":

```python
# text label at the default rect
s("/ms/scene/score1/annotation", "a1", "text", "Allegro")

# move/resize it (x, y, w, h in page-normalized 0..1)
s("/ms/scene/score1/annotation", "a1", "rect", 0.12, 0.04, 0.30, 0.06)

# recolor (r, g, b, optional a)
s("/ms/scene/score1/annotation", "a1", "color", 0.85, 0.1, 0.1)

# a glyph by name (see the Gotchas about fonts)
s("/ms/scene/score1/annotation", "seg", "glyph", "segno")

# show / hide / delete
s("/ms/scene/score1/annotation", "a1", "hide")
s("/ms/scene/score1/annotation", "a1", "show")
s("/ms/scene/score1/annotation", "a1", "del")

# list the annotation ids on this object
s("/ms/scene/score1/annotations")
# -> /ms/reply annotations score1 a1 seg
```

A brand-new annotation defaults to rect `(0.1, 0.1, 0.2, 0.1)`, near-black color, font size 28. It
re-scales and re-positions automatically whenever the page re-renders, so it stays glued to its spot as
the score reflows.

> **Gotchas**
> - **Auto-create on first use.** Any subcommand naming an unseen `<aid>` creates it — a typo makes a
>   stray label, not an error.
> - **`text` wins over `glyph`.** If both are set on one annotation, the text is drawn and the glyph is
>   ignored.
> - **Glyphs render as their literal name** (e.g. the word `segno`) unless you bundle a SMuFL music font
>   and set it on Godot's `ThemeDB`. The 3D backend draws annotations with a `Label3D`.
> - **The `annotations` reply lists ids only** — no text/rect/color is echoed back (unlike `regions`,
>   which returns geometry).
> - **No permission gating** — annotations are pure presentation, never node access.

## 2. Addressable scores (mpos)

The *other* kind of overlay. Turn a notation object **addressable** and MusicScene auto-extracts clickable,
time-tagged regions from the engraved music — measures (`m1`, `m2`, …) or note elements (`n0`, `n1`, …) —
so a client can light up "measure 5" or react to a click on a specific note.

Opt in, load the score source, then query what was found:

```python
s("/ms/scene/score1", "addressable", 1)     # opt in (see Gotchas re: ordering)
# ... now load the score source (MusicXML / LilyPond / etc., per TUTORIAL §9) ...

s("/ms/scene/score1", "measures")
# -> /ms/reply measures score1 1 <x> <y> <w> <h> <time> 2 <x> <y> <w> <h> <time> ...
s("/ms/scene/score1", "elements")
# -> /ms/reply elements score1 0 <when> <line> <char> <u> <v> 1 <when> <line> <char> <u> <v> ...
```

Which backend does the extraction depends on the source format: MuseScore/MusicXML via its `.mpos`/`.spos`
export, LilyPond via an injected timing tagger, Verovio via its timemap. The generated regions are real
regions — they hit-test, so clicking one emits an input event just like a manually-created region — and
the `measures`/`elements` replies carry geometry **and** timing, unlike the id-only `annotations` reply.

The clickable regions are named `m1`, `m2`, … (measures) and `n0`, `n1`, … (elements); note the
`measures`/`elements` replies key each entry by its **bare index** (`1`, `2`, … / `0`, `1`, …), not by the
region id. A measure entry is `<index> <x> <y> <w> <h> <time>`; an element entry is
`<index> <when> <line> <char> <u> <v>` (`line`/`char` are source-coordinate hints for LilyPond).

Note the two verbs (`addressable`, `measures`, `elements`) are **verb-first** — the verb is the first OSC
*argument* (`s("/ms/scene/score1", "measures")`), whereas §1's `annotation`/`annotations` are
**address-embedded** subsystems (`/ms/scene/score1/annotation`). That inconsistency is a wart worth
remembering.

**Panola → LilyPond, via this same mechanism.** `MSScore(..., notation: \lilypond)` (the SuperCollider
side, see TUTORIAL §9E) engraves through the LilyPond source-tagging path described above — same
`addressable`/`elements`/note-level following as raw `notation lilypond`. It requires the LilyPond
engraver to be configured (`musicscene/notation/engraver/lilypond` → your LilyPond executable, §9C) and
LilyPond installed; there is no built-in fallback the way MEI/ABC have Verovio. The rendered preview
**paginates into auto-turning pages** just like Verovio: `paginate`/`pageHeight` fill pages by height,
`pageBreaks` force page boundaries, and `showPage`/`nextPage`/`prevPage` flip between them, while
`systemBreaks` still controls where systems fall *within* auto-pagination. One pathological
edge case — a tuplet whose fragment straddles a barline in a way that isn't expressible at the tuplet's
ratio — is kept as a single un-split tuplet with a warning, which can surface as a LilyPond bar-check
warning at render time; it does not affect any other note.

> **Gotchas**
> - **Enabling `addressable` after the source is loaded still works** — it triggers a re-render that
>   re-extracts the regions (for the external engraver formats). Opting in *before* the load just avoids
>   rendering the page twice.
> - **The extraction backend is format-dependent** (MuseScore mpos vs LilyPond vs Verovio); a format
>   without position data yields no regions.
> - **Distinct from annotations** — addressable regions are auto-extracted, clickable, and time-tagged;
>   annotations are hand-placed and inert. They share nothing but the word "overlay."
> - **LilyPond notation paginates like Verovio.** A LilyPond-engraved score (including
>   `MSScore notation: \lilypond`) supports `paginate`/`pageHeight` to auto-fill pages and `pageBreaks` /
>   `systemBreaks` to force page and line boundaries, with `showPage`/`nextPage`/`prevPage` page-turning
>   just like the Verovio path.

---

## Part B — Discovering & binding existing nodes

## 3. discover

Before you can drive a pre-existing project node over OSC you need its id and path. `discover` introspects
the running scene tree and hands them back, so a client doesn't hardcode node paths.

```python
s("/ms/discover")                              # every node in the scene
s("/ms/discover/type", "RigidBody2D")          # by Godot class
s("/ms/discover/group", "pegs")                # by Godot group membership
s("/ms/discover/meta", "role", "pad")          # by metadata key [and optional value]
```

The mode (`type`/`group`/`meta`) lives in the **address path**; the value (`RigidBody2D`, `pegs`, …) is an
argument. A bare `/ms/discover` returns everything. You get **one reply message per matching node**:

```python
# -> /ms/reply discover play_button /root/Main/UI/PlayButton Button PlayButton
#                            suggested_id  path                    class  name
```

`suggested_id` is the node's current OSC id if it's already bound, else its `OscExposable.suggested_id()`,
else its node name in `snake_case`. The typical flow is discover → pick → bind:

```python
s("/ms/discover/type", "AudioStreamPlayer")
# -> /ms/reply discover music /root/Main/Music AudioStreamPlayer Music
s("/ms/bind", "music", "/root/Main/Music")     # now controllable as "music"
```

> **Gotchas**
> - **Read-only and ungated** — `discover` (all/type/meta) returns *every* node, exposed or not. It leaks
>   only class/name/path; binding the result is separately gated (§5).
> - **`suggested_id` is only a suggestion.** Nothing is bound until you call `bind` — discover never
>   registers anything itself.

## 4. bindAll / bindGroup

`bind`/`bindRel` attach one id to one node. When you want many at once, use the bulk binders.

```python
# one at a time (recap)
s("/ms/bind", "play", "/root/Main/UI/PlayButton")
s("/ms/bindRel", "hat", "Percussion/HiHat")     # relative to /ms/app/root

# a whole Godot group -> ids "<group>.0", "<group>.1", ...
s("/ms/bindGroup", "pad", "pads")
# -> /ms/reply bindGroup pad.0 pad.1 pad.2

# every node whose metadata matches
s("/ms/bindAll", "meta", "role", "trigger")     # meta "role" == "trigger" (value optional)
```

`bindGroup` binds each node in the named Godot group as `<osc_group>.<i>` (0-based, in the group's
iteration order) and replies with the new ids. `bindAll meta` walks the scene for nodes carrying the given
metadata and binds each through the ordinary, permission-checked `bind()`.

Separately, at startup MusicScene **auto-binds** exposed nodes: two frames after it's ready it scans once and
binds every `OscExposable` node (whose `osc_auto_bind` and `osc_allow_bind` are true — both default true)
plus every node tagged `set_meta("osc_expose", true)`. This scan runs **once** — nodes added later are not
auto-bound; bind them explicitly.

> **Gotchas**
> - **`bindGroup` bypasses the permission gate entirely.** It binds every member of the Godot group
>   whether or not the node is OSC-exposed and regardless of `developer_mode` (see §5). Only the
>   *operations* you then perform (`call`/`prop`) are still checked.
> - **`bindAll` only understands `meta`.** Any other first argument (`bindAll group …`, `bindAll type …`)
>   **silently does nothing** — no bind, no error, no reply.
> - **Auto-bind is one-shot at startup**, not a live watch. Spawn a node after boot and you must bind it.

## 5. Safety & the permission model

An open OSC port can reach into your scene, so MusicScene gates anything that touches **pre-existing** project
nodes. (Objects MusicScene itself made with `new`/`instantiate` are always fully controllable — the gate is
about protecting *your* nodes.)

There are three layers:

1. **Five global kill-switches**, seeded from Project Settings (`musicscene/permissions/…`) and toggleable
   at runtime. Defaults: `bind_existing`, `instantiate`, `call_methods`, `set_props` = **on**;
   `free_nodes` = **off**. A switch set off blocks that operation for everyone — even in developer mode.
2. **`developer_mode`** (default off). When on, it short-circuits the per-capability checks so anything
   goes (still subject to the kill-switches above).
3. **A scene/prefix whitelist** for `instantiate` (built-in default prefix `res://osc_spawnable/`).

```python
s("/ms/app/permissions", "callMethods", 0)      # bindExisting|instantiate|callMethods|setProps|freeNodes
s("/ms/app/developer", 1)                        # blanket allow (also /ms/app/developer_mode)
s("/ms/assets/allowScene", "res://mobs/slime.tscn")
s("/ms/assets/allowPrefix", "res://spawn/")
s("/ms/assets/listAllowed")
# -> /ms/reply assets res://mobs/slime.tscn res://spawn/* ...
```

**Opting a node in.** Add an `OscExposable` child to the node you want reachable (it controls its parent by
default; set `target_path` to point elsewhere). Its exports declare intent: `osc_id`, `osc_methods`
(allow-list for `call`), `osc_properties` (allow-list for `prop` set), `osc_signals`, `osc_allow_free`,
`osc_auto_bind`, `osc_allow_bind`. Or opt in from code with `set_meta("osc_expose", true)` (plus optional
`osc_id` / `osc_methods` / `osc_allow_free` metas).

**What each operation checks:**

| Operation | Allowed when |
|---|---|
| `bind` / `bindRel` | kill-switch on **and** (developer_mode **or** the node is exposed) |
| `bindGroup` | **always** (no gate — see §4) |
| `bindAll meta` | same as `bind` (runs through it) |
| `instantiate` | kill-switch on **and** (developer_mode **or** path is whitelisted) |
| `prop <name> <val>` (set) | kill-switch on **and** (developer_mode **or** name in `osc_properties`) |
| `call <method> …` | kill-switch on **and** (developer_mode **or** method in `osc_methods`) |
| `free` | developer_mode **or** `free_nodes` **or** the node's `osc_allow_free` |
| `del` (MusicScene's own object) | **always** (it's MusicScene's to delete) |
| `getProp <name>` (read) | **always** (no gate) |
| `signal <name> <target>` | **always** (no gate — see §7) |
| `on` / `off` / `payload` | **always** (configures outbound OSC only, no node access) |
| `discover*` | **always** (read-only) |

> **Gotchas**
> - **`bindGroup` skips the gate** — the one binding path that ignores exposure and developer_mode.
> - **`getProp` and `/signal` are unrestricted**, even outside developer mode. The allow-lists gate only
>   *writes* and *calls*: `osc_properties` gates `prop` (set) and `osc_methods` gates `call`. They are
>   **not** consulted when *reading* a property (`getProp`) or *forwarding* a signal (`/signal`), and
>   `osc_signals` gates nothing at all — it's informational, feeding only the `signals`/`capabilities`
>   queries. Treat any readable property and any existing signal on a bound node as reachable.
> - **A kill-switch overrides developer_mode.** `bind_existing = 0` blocks binding even with
>   `developer 1`; the switches are the outer guard.

---

## Part C — Events & forwarding

## 6. payload

When you register a physics/area event with `on`, MusicScene sends a default set of fields. `payload` lets you
**redefine that argument list** for one event — pick exactly which computed values (and constants) go out,
in what order — without re-registering.

```python
# register: emit /synth/hit on collision, gated a little
s("/ms/scene/note1/on", "collisionEnter", "/synth/hit", "minIntensity", 0.2, "cooldown", 0.05)

# customize the outbound args for just this binding
s("/ms/scene/note1/payload", "collisionEnter", "self", "other", "otherspeed", "=bounce")

# ... note1 hits the floor, other body moving at 0.83 ...
# -> /synth/hit note1 floor 0.83 bounce
```

Field tokens are looked up **case-insensitively** in the event's data. The full vocabulary:

```
self  other  x y z  worldx worldy worldz  vx vy vz  speed  relativespeed  intensity  impulse
normalx normaly normalz  otherx othery otherz  othervx othervy othervz  otherspeed
time  beat  mass  angle  angularvelocity  layer
```

- A token beginning with `=` or `'` is a **literal** — the rest is emitted verbatim as a string
  (`=bounce` → `"bounce"`). Handy for tagging which binding fired.
- An unknown token emits `0` (not an error).
- `intensity`, `speed`, and `relativespeed` are currently the same value (collision speed); `impulse` is
  `speed × mass`.

With **no** `payload` set, the binding falls back to:

```
DEFAULT_FIELDS = self  other  intensity  x y  vx vy  time
# -> /synth/hit note1 floor 0.42 0.0 -0.8 0.0 -1.1 3.12
```

Independently, every **discrete** collision/area event (`collisionEnter/Exit`, `areaEnter/Exit`, `sleep`,
`wake`) also emits a fixed canonical message you can't reconfigure, so a monitor can always watch raw
physics (the continuous family in §9 does **not** emit this):

```
# -> /ms/event/physics <event> <self> <other> <intensity> <x> <y> <vx> <vy>
```

> **Gotchas**
> - **`payload` needs a prior `on`** for that event — calling it first is a silent no-op.
> - **Input-event payloads are ignored.** For the interaction events (`click`, `down`, `up`, `drag`,
>   `enter`, `leave`) `payload` is *stored but never applied* — they always emit `[<id>, nx, ny]` (or
>   `[<id>, region_id, u, v]` for a region hit). `payload` only shapes the physics/area family.

## 7. Signal forwarding

Two ways to turn things happening in Godot into outbound OSC:

- **Named event families** — the physics/area/interaction events, via `on` + `payload` (§6, §9).
- **The generic `/signal` escape hatch** — connect *any* Godot signal on a bound node (a `Button.pressed`,
  an `Area2D.body_entered`, your own custom signal) and relay its arguments.

```python
# default payload: <id> <signal_name> <signal args...>
s("/ms/scene/playbtn/signal", "pressed", "/ui/play")
# pressing the button -> /ui/play playbtn pressed

# custom payload tokens: self | signal | value | args | arg0..argN
s("/ms/scene/vol/signal", "value_changed", "/ui/volume", "payload", "self", "value")
# slider emits value_changed(0.42) -> /ui/volume vol 0.42
```

Payload tokens for `/signal`: `self` (the osc id), `signal` (the name), `value` (arg0), `argN` (the Nth
signal arg), `args` (splat all of them). An unrecognized token is echoed back **literally** — so any word
acts as a constant, with no `=` needed (unlike §6). Re-sending `/signal` for the same signal name replaces
the previous binding.

> **Gotchas**
> - **No permission check.** Any signal that exists on the bound node can be forwarded, developer mode or
>   not; `osc_signals` on `OscExposable` is informational only and is **not** enforced here.
> - **Arity is probed, extras are dropped.** MusicScene connects a handler matching the signal's declared
>   argument count; a signal declaring **5+ args** is connected via the 4-arg handler and the surplus args
>   are dropped.
> - **`Vector2` collapses to its `.x`.** A `Vector2`/`Vector2i` signal argument is sent as just its x
>   component (y is discarded); other non-primitive values are stringified.
> - **`off` does not disconnect a `/signal`.** `off` only clears the named event families. A signal
>   binding is removed only by re-registering that signal name, or automatically when the object is torn
>   down (unbind / del / free / clear).

## 8. Emission modes & throttling

`on` accepts option/value pairs after the target that control *when* and *how* the event is sent. They
apply to the physics/area/continuous family.

```python
s("/ms/scene/ball1/on", "collisionEnter", "/synth/hit",
  "minIntensity", 0.15,     # ignore hits softer than this (intensity == collision speed)
  "cooldown", 0.05,         # min seconds between emits
  "maxRate", 20,            # max emits per second (Hz); combined with cooldown, the larger gap wins
  "other", "peg*",          # only when the *other* body's id matches this glob
  "layer", "floor",         # only when the other body is on this collision-layer name
  "mode", "quantized",      # immediate | queued | bundle | quantized
  "quantizeGrid", 0.25)     # for mode=quantized: grid in beats
```

The **modes**:

- `immediate` (default) — send the moment the event fires.
- `queued` — collect the frame's emits and flush them as individual sends at end of frame.
- `bundle` — pack the frame's emits into a single OSC bundle.
- `quantized` — hold each message until the next grid line (`now_beat ≥ next multiple of quantizeGrid`),
  so events land on the beat. Requires the transport/beat clock to be running.

`minIntensity`, `cooldown`, `maxRate`, `other`, and `layer` are **filters** — they decide whether an emit
happens at all; `mode`/`quantizeGrid` decide its timing. `payload` (§6) then shapes each message that does
go out.

> **Gotchas**
> - **`cooldown` + `maxRate` combine** — the effective minimum gap is the larger of the two.
> - **`quantized` needs a beat clock.** With no transport running, quantized messages have no grid to land
>   on.
> - **The quantized buffer is capped** (512 pending); past that, the oldest held message is dropped
>   silently.
> - **`other` is a glob on the *other* body's id** (e.g. `peg*` matches `peg0`, `peg100`), not on `self`.

## 9. Continuous physics events

The discrete events (`collisionEnter/Exit`, `areaEnter/Exit`, `sleep`, `wake`) fire on a Godot callback.
There's also a **per-step continuous family**, checked every physics frame:

- `velocityAbove` / `velocityBelow` — fire when the body's normalized speed crosses a threshold.
- `yAbove` / `yBelow` — fire when its normalized y crosses a threshold.
- `collisionStay` / `areaStay` — re-fire while bodies remain in contact / overlap.

The threshold for the `*Above`/`*Below` events is the **`minIntensity` option** — an unusual reuse, so it's
worth spelling out:

```python
# fire once each time the ball speeds past 1.5 (normalized units)
s("/ms/scene/ball1/on", "velocityAbove", "/fx/whoosh", "minIntensity", 1.5)

# a sustained drone while anything sits inside this sensor zone, re-emitting per body, throttled
s("/ms/scene/zone1/on", "areaStay", "/drone/sustain", "cooldown", 0.1)
```

`*Above`/`*Below` are **edge-detected**: they emit once when the condition flips from false to true, not
every frame the body stays past the threshold — MusicScene tracks the previous state per binding. `*Stay`
emits **per contacting body** (each with its own cooldown/rate) and stops tracking a body once it leaves.
All of these use `on` / `payload` (§6) and the emission modes (§8); none use `/signal`.

> **Gotchas**
> - **The threshold is `minIntensity`, not a positional argument.** `on velocityAbove /addr minIntensity
>   1.5` — there is no `on velocityAbove 1.5 /addr` form.
> - **`*Above`/`*Below` are edge-triggered** — one event per crossing. If you want a message every frame
>   while past the threshold, that's not what these do.
> - **`*Stay` fans out per other-body** and prunes bodies that leave, so its emit rate scales with the
>   number of contacts (use `cooldown`/`maxRate` to tame it).

---

## 10. Collision reactors (bouncers & portals)

Bouncers and portals are **pass-through Area** objects (like zones) that act on a rigid body the instant it
enters. Create them with `new bouncer` / `new portal` — their Area is auto-enabled, and they still emit
`areaEnter`, so `on areaEnter …` bindings drive sound/scoring.

```python
# bumper: mirror-reflect + outward kick
s("/ms/scene/bump/bouncer", "strength", 3.0, "gain", 1.0, "minSpeed", 0.5)
# portal: directional random teleport
s("/ms/scene/pa/portal", "link", "pb", "pc")   # enter pa -> random of {pb, pc}
```

**Bouncer** sets the outgoing velocity to `reflect(v, n)·gain + n·strength`, where `n` is the outward
surface normal — exact for round colliders (center-to-center) and box/rect colliders (the face the body
enters, honoring rotation). `strength`/`minSpeed` are normalized units — the same scale as a collider
radius (not per-axis like a normalized velocity); `gain` is a
dimensionless restitution (1.0 = energy-preserving).

**Portal** teleports an entering body to a uniform-random one of its linked targets, preserving velocity.
Links are **directional** (`pa link pb` does not imply `pb link pa`).

> **Gotchas**
> - Reactors are **pass-through** — they never physically block a body; contain a play area with ordinary
>   static walls that have `bounce`.
> - The box-bouncer normal is chosen from the face the body is **moving into** (velocity-based), so for a
>   genuinely square box a glancing hit may reflect off the "entered" face rather than the nearest one —
>   exact for walls, an approximation for corners.
> - Portal re-entry is prevented by a short **cooldown** (~250 ms), not by the small exit nudge; the just-
>   arrived body is ignored by portals until it leaves or the cooldown lapses.
> - Only **rigid bodies** are acted on; an entering area/zone is ignored.

---

*See also: **[TUTORIAL.md](TUTORIAL.md)** (step-by-step introduction) and **[README.md](README.md)**
(complete command / reply / error reference).*
