# gscore_osc

[![CI](https://github.com/shimpe/MusicScene/actions/workflows/ci.yml/badge.svg)](https://github.com/shimpe/MusicScene/actions/workflows/ci.yml)
![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf)
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue)

An **OSC-controlled, INScore-inspired interactive music-score / world system** for Godot 4.

External OSC clients (Max/MSP, Pure Data, SuperCollider, Python, TouchDesigner, Ableton
bridges, …) can **create, bind, control, animate, query, and receive events** from Godot scene
objects under the root namespace `/gscore`. Beyond INScore it adds **Godot 2D physics,
collision-driven OSC emission, binding to existing nodes, PackedScene instantiation, exposing
methods/properties/signals over OSC, and first-class music-notation display**.

Built as a Godot addon at `addons/gscore_osc/`. Pure GDScript. Targets **Godot 4.7** (uses
stable Godot 4.x APIs). **Works in both 2D and 3D** — selectable via the `gscore_osc/space`
project setting; the same OSC API drives both (see [Dimensions](#dimensions-2d-and-3d)).

> Status: the full v1 API is implemented and verified headlessly against Godot 4.7 in **both 2D
> and 3D** — see [Verifying](#verifying). `10/10` OSC acceptance checks pass in each mode, plus
> codec, SVG and signal-forwarding self-tests. The project ships defaulting to **3D**.

> **New here?** Start with the step-by-step **[TUTORIAL.md](TUTORIAL.md)** — it walks through using
> the addon in a fresh project, in both 2D and 3D, with a copy-paste OSC client.

---

## Table of contents

- [What it is](#what-it-is) · [Core principle](#core-principle) · [Install / start](#install--start)
- [Ports](#ports--networking) · [Coordinates](#coordinate-system) · [Creating objects](#creating-objects)
- [Notation](#music-notation) (backends, cursor, regions, annotations) · [Binding nodes](#binding-existing-godot-nodes)
- [Instantiating scenes](#instantiating-packedscenes) · [Physics & collisions](#physics--collision-events)
- [Physics joints](#physics-joints) · [Sensors & trigger zones](#sensors--trigger-zones)
- [Camera control](#camera-control) · [Methods/props](#controlled-method--property-access) · [Signals](#signal-to-osc-forwarding)
- [Transport](#transport--time-mapping) · [Script runner](#script-runner) · [Permissions](#permissions--safety)
- [Errors](#errors) · [API reference](#api-reference) · [Limitations](#known-limitations)

---

## What it is

Every OSC-controlled object is an addressable entity in a live score-world:

```
visual object
  + optional notation / media content
  + optional physics body
  + optional sensor / event emitter
  + optional OSC behaviour
```

The API is object-oriented and reads like a tree:

```
/gscore/scene/note1/physics enable rigid
/gscore/scene/note1/on collisionEnter /synth/hit
/gscore/scene/score notation png "res://scores/page1.png"
```

## Core principle

**OSC identity is separate from Godot node identity.** Clients address stable OSC ids:

```
/gscore/scene/cursor
/gscore/scene/note42
/gscore/scene/floor
/gscore/scene/score
```

…and never need to know whether that id was created over OSC, instantiated from a `.tscn`, or
bound to `/root/Main/Stage/Cursor`. The `GScoreRegistry` maps id ⇄ wrapped node and tracks
ownership (`created_by_osc`, `instantiated_by_osc`, `bound_existing`, `auto_bound`,
`group_binding`).

---

## Install / start

The addon is wired to run **out of the box**:

1. Open the project in Godot 4.7. The plugin is enabled and the `GScoreOSC` autoload is
   registered in `project.godot`.
2. Press **Play**. The project defaults to **3D** (`ExampleMain3D.tscn`): the OSC server starts,
   a Camera3D is auto-created, and `example_score_3d.gscore` plays automatically — a notation
   page on a quad in world space, a red cursor sweep, a highlighted measure region, and a note
   that falls onto a floor and emits OSC on impact.
3. Send `/gscore/ping` from any OSC client → you get `/gscore/pong`.

To run the **2D** example instead, set `gscore_osc/space = "2d"` and the main scene to
`ExampleMain.tscn` (Project Settings), or drop an `override.cfg` with those values.

To use it in your own project: copy `addons/gscore_osc/` in, enable the **gscore_osc** plugin in
*Project → Project Settings → Plugins* (this installs the `GScoreOSC` autoload). Configuration
lives under *Project Settings → gscore_osc/…* (see below).

### Generating the placeholder score

A placeholder engraved page (`res://scores/page1.png`) is included. To regenerate it:

```
<godot> --headless --path . --script res://tools/gen_assets.gd
```

---

## Dimensions: 2D and 3D

The whole framework runs in either **2D** or **3D**, chosen once at boot by the project setting
`gscore_osc/space` (`"2d"` | `"3d"`, default `"3d"`). The OSC API is identical; only the spatial
behaviour differs, behind a backend (`GScoreSpatial2D` / `GScoreSpatial3D`):

| | 2D | 3D |
|---|---|---|
| objects | `Node2D` primitives (`_draw`) | `MeshInstance3D` (rect→quad, circle→sphere, line), `Sprite3D`, `Label3D` |
| physics | `RigidBody2D`/`StaticBody2D`/`Area2D` | `RigidBody3D`/`StaticBody3D`/`Area3D` |
| colliders | `rect`, `circle`, `polygon` | `box`/`rect`, `sphere`/`circle`, `auto` |
| notation | textured node in 2D | textured **quad in world space** (placed/rotated in 3D) |
| camera | none needed | auto-created `Camera3D` if the scene has none |
| picking | 2D hit-test | camera ray vs object AABB / notation quad plane |

Everything else — OSC server, dispatcher, registry, object wrapper, events, signals, transport,
script runner, permissions — is shared. `pos`/`scale`/`velocity`/`gravity`/etc. simply accept an
extra `z` in 3D (e.g. `pos x y z`, `gravity 0 -0.6 0`).

## Ports / networking

UDP. Defaults (Project Settings → `gscore_osc/network/`):

| Setting | Default | Meaning |
|---|---|---|
| `listen_port` | `7400` | port the server receives OSC on |
| `send_host` | `127.0.0.1` | fallback reply/event host (used until a client has sent something) |
| `send_port` | `7401` | port replies and events are sent to |
| `autostart` | `true` | start the server on boot |

Replies/events are sent to the **most recent sender's IP** on `send_port`. Override at runtime
with `/gscore/app/output <host> <port>`.

---

## Coordinate system

Default **normalized score space**:

```
x: -1.0 left   0 center   1.0 right
y: -1.0 bottom 0 center    1.0 top   (y-up)
```

The viewport maps to the full `[-1,1] × [-1,1]` square. Switch modes:

```
/gscore/app/coord normalized   # default
/gscore/app/coord pixels        # raw viewport pixels, top-left origin, y-down
/gscore/app/coord world         # global Node2D coords (== pixels with no camera)
```

Physics has its own independent mode:

```
/gscore/physics coord normalized|pixels|world
```

In **3D** (`space = "3d"`), normalized space is x/y/z ∈ `[-1,1]` (y-up, +z toward the camera)
mapped to a world cube of half-extent 5 units; `world` mode uses raw Godot units, and `pixels`
falls back to world. Commands take an optional z (`pos x y z`, `scale sx sy sz`,
`gravity gx gy gz`); a single `rotate <deg>` spins in-plane about Z, `rotate x y z` sets full
Euler degrees.

**Notation-internal** coordinates (cursor `pos`, region/annotation `rect`) are always `[0,1]`
over the page rect, top-left origin, y-down (same in 2D and 3D).

---

## Creating objects

```
/gscore/scene/<id> new <type> [args...]
```

Built-in types: `group  text  rect  circle  line  image  sprite  area  notation`

```
/gscore/scene/title new text "Hello"
/gscore/scene/box   new rect
/gscore/scene/ball  new circle
/gscore/scene/logo  new image "res://assets/logo.png"
/gscore/scene/score new notation
```

Generic commands work on **every** object type:

```
/gscore/scene/<id> show | hide | del | unbind | free
/gscore/scene/<id> pos <x> <y>      x <f>   y <f>   z <f>
/gscore/scene/<id> size <w> <h>     width <f>   height <f>
/gscore/scene/<id> scale <s>        scale <sx> <sy>     rotate <deg>
/gscore/scene/<id> opacity <f>      color <r> <g> <b> [a]      text "<str>"
/gscore/scene/<id> get <prop> | get * | dump | capabilities | exists
```

Lifecycle semantics: **`unbind`** drops the OSC registration but leaves the node alive;
**`del`** frees the node if it was OSC-created/instantiated, otherwise just unbinds; **`free`**
force-frees, but only if permitted.

---

## Music notation

Notation is a **first-class object type**. A notation object can be positioned, scaled, hidden,
given physics, clicked, and queried like anything else.

```
/gscore/scene/score new notation
/gscore/scene/score notation png "res://scores/page1.png"
/gscore/scene/score pos 0 0
/gscore/scene/score scale 0.9
```

Notation commands:

```
/gscore/scene/<id> notation <format> <source_or_data>   # file path OR inline data (auto-detected)
/gscore/scene/<id> notationData <format> <data>         # force inline text/blob-bytes data
/gscore/scene/<id> notationSource <source_or_data>
/gscore/scene/<id> notationFormat <format>
/gscore/scene/<id> render | reload
/gscore/scene/<id> page <n> | nextPage | prevPage | pages
/gscore/scene/<id> system <n> | staff <n> | measure <n> | part <id>
/gscore/scene/<id> notationInfo
```

### Notation backends

`format` selects a backend behind `GScoreNotationRenderer`:

| Format | Backend | Notes |
|---|---|---|
| `png` `image` `jpg` `jpeg` `webp` `bmp` | **image** | always available; the canonical v1 backend |
| `svg` | **svg** | `res://` SVGs use Godot's own import (reliable, matches the editor preview); other paths rasterize at runtime via `Image.load_svg_from_string` |
| `musicxml` `mei` `guido` `abc` `lilypond` `pdf` | **external** | shells out to a configured engraver → PNG/SVG, cached |

Display any engraved page produced by MuseScore, LilyPond, Verovio, Dorico, Finale or Sibelius
by exporting to PNG/SVG and pointing the image/svg backend at it.

**Runtime-generated scores** (the default for many setups) are first-class — a `source` may be:

- a **file path** (`res://`, `user://`, or absolute) written at run-time;
- **inline data** sent over OSC — an SVG/MusicXML/LilyPond/ABC **string**, or raster **bytes** as
  an OSC blob (use `notationData` to force, or just send markup/blob and it's auto-detected);
- **symbolic music** that gscore engraves on the fly via a configured external engraver (below).

See the tutorial's [Displaying scores](TUTORIAL.md#displaying-scores--every-source-option) section
for every form with examples.

**SVG tips.** Put the `.svg` under `res://` so Godot imports it — if it shows a thumbnail in the
FileSystem dock, the notation backend will display it. Notation renders at the page's native pixel
size centred on the object, so a large page can overflow the screen: scale it down (e.g.
`/gscore/scene/score scale 0.3`). If a non-`res://` SVG fails at runtime (some engraver SVGs use
features ThorVG can't rasterize), import it under `res://` or export to PNG.

**Multi-page** raster/SVG: put `{page}` in the source path (e.g. `res://scores/p{page}.png`);
the page count is probed automatically and `page`/`nextPage`/`prevPage` switch pages.

**External engraver** configuration (Project Settings → `gscore_osc/notation/`). Set a per-format
command (preferred) or the generic fallback; works for a file path or inline symbolic data (gscore
writes inline source to a temp file, runs the command, and caches the output):

```
engraver/musicxml      "C:/Program Files/MuseScore 4/bin/MuseScore4.exe" {input} -o {output} -T 10 -r 200
engraver/lilypond      "C:/Program Files/lilypond-2.25.81/bin/lilypond.exe" --png -dcrop=#t -dresolution=200 -o {outbase} {input}
engraver/mei           py "res://tools/verovio_render.py" {input} {output} --page {page}      (pip install verovio)
engraver/abc           py "res://tools/verovio_render.py" {input} {output} --page {page}
engraver_output        "png" (default) | "svg"        tokens: {input} {output} {outbase} {outdir} {format} {page}
engraver_output/<fmt>  per-format override (e.g. .../mei = "svg")
external_renderer_path + external_renderer_args        generic fallback for any symbolic format
```

Engraving runs **asynchronously** — the engraver is launched in the background (`OS.create_process`)
and polled, so the app stays responsive (verified: ~2 ms OSC latency during a multi-second
MuseScore render). The notation object shows an "engraving…" placeholder and swaps the page in when
ready; results are cached so repeats are instant.

**Call the engraver directly** — no helper script. gscore finds the file the engraver actually wrote
(`{output}` plus the usual `.cropped` / `-page{N}` / `-N` variants LilyPond/MuseScore emit) and
caches it, so you normally just set the engraver's path. Quote paths with spaces; `res://`/`user://`
in a command are resolved too. **LilyPond and MuseScore ship working defaults** — set your install
path and `notation musicxml/lilypond "<path-or-inline>"` (or `notationData`) works. Portable,
auto-detecting wrappers are also bundled (`tools/ly_to_score.py`, `tools/mscore_to_score.py`).
(MuseScore 4 can crash on a cold headless start; results are cached, so a retry succeeds.)

Rendered pages are cached under `user://gscore_cache/notation/`:

```
/gscore/notation/cache clear
/gscore/notation/cache info
```

### Notation cursor

A vertical playback cursor in page-normalized `[0,1]` coords:

```
/gscore/scene/<id>/cursor show <0|1>
/gscore/scene/<id>/cursor pos <x> <y>
/gscore/scene/<id>/cursor color <r> <g> <b> [a]
/gscore/scene/<id>/cursor width <f>
/gscore/scene/<id>/cursor map <t0> <t1> <property> <from> <to>      # property: x|y|opacity
/gscore/scene/<id>/cursor measure <n> | beat <b> | time <s>          # stored; drive via pos/map in v1
```

### Notation regions

Addressable rectangles (page-normalized `[0,1]`) that can highlight and emit click events:

```
/gscore/scene/<id>/region <rid> rect <x> <y> <w> <h>
/gscore/scene/<id>/region <rid> measure <n> [staff]
/gscore/scene/<id>/region <rid> on <event> <target_osc_address>
/gscore/scene/<id>/region <rid> highlight <0|1>
/gscore/scene/<id>/region <rid> color <r> <g> <b> [a]
/gscore/scene/<id>/regions
```

Clicking a region with an `on click` binding emits, e.g.:

```
/score/measure score m1 <u> <v>
```

### Addressable notation (auto measure regions)

For MusicXML/MEI via **MuseScore**, gscore can extract real measure positions and make the score
addressable automatically — no manual rects:

```
/gscore/scene/<id> addressable 1            # enable, then (re)load a MusicXML source
/gscore/scene/<id> notation musicxml "res://score.musicxml"   # or notationData musicxml <inline>
/gscore/scene/<id> measures                  # -> reply measures <id> <n u v w h time> ...
/gscore/scene/<id>/cursor measure <n> [beatFraction]          # jump cursor to a measure
```

It renders the full page, reads MuseScore's `.mpos` position export (one batched, async MuseScore
run), crops to the music, and creates a clickable region `m1…mN` per measure (each emits
`/gscore/event/measure <id> m<n> <u> <v>` on click). `measures` replies each measure's
page-normalized rect and time position, so a client can drive cursor-following by sending
`cursor measure <n>` as the music plays.

For **LilyPond** the same `addressable 1` gives **note-level** addressing with automatic following:
gscore injects a Scheme tagger so every note carries its musical moment, renders the point-and-click
SVG, and extracts each note's time, source `line:char`, and position.

```
/gscore/scene/<id> addressable 1
/gscore/scene/<id> notation lilypond "res://score.ly"      # or notationData lilypond <inline>
/gscore/scene/<id> elements                  # -> reply elements <id> <n when line char u v> ...
/gscore/scene/<id>/cursor follow 1           # cursor tracks the transport across the notes
```

Each note becomes region `n0…nK` (clicking emits `/gscore/event/note <id> n<i> <u> <v>`), and with
`cursor follow 1` + a playing transport the cursor moves note-to-note and emits
`/gscore/event/note <id> n<i> <when> <line> <char>` as it passes each one — full score-following,
driven entirely by gscore.

**Verovio** (for MEI/ABC, `pip install verovio`) gives the same note-level addressing + following and
is the cleanest source: its SVG tags every note with a stable id and `renderToTimemap()` provides
each note's exact time, so no source-tagging is needed. Configure `engraver/mei` (and `abc`) to the
bundled `tools/verovio_render.py` (the default), then `addressable 1` + `notation mei "…"` →
`elements`, note hotspots, and `cursor follow 1` work just like LilyPond. (Verovio also reads
MusicXML, so you can point `engraver/musicxml` at it instead of MuseScore if you prefer.)

### Notation annotations

Lightweight text/glyph overlays (move/scale with the score):

```
/gscore/scene/<id>/annotation <aid> text "<str>"
/gscore/scene/<id>/annotation <aid> rect <x> <y> <w> <h>
/gscore/scene/<id>/annotation <aid> glyph <name>
/gscore/scene/<id>/annotation <aid> color <r> <g> <b> [a]
/gscore/scene/<id>/annotation <aid> show | hide | del
/gscore/scene/<id>/annotations
```

> Glyphs render as text. Bundle a SMuFL music font and set it on `ThemeDB` for real glyphs.

### Notation in 3D

With `space = "3d"` a notation object renders its page on a textured **QuadMesh in world space**;
`pos x y z` / `rotate x y z` / `scale` place and orient it freely, and the cursor, regions and
annotations are 3D children on the quad surface (so they move/scale/rotate with it). Region click
events use a camera ray ↔ quad-plane intersection. The OSC commands are identical to 2D.

### Notation as a physics object

Notation objects accept physics like anything else:

```
/gscore/scene/page1/physics enable rigid
/gscore/scene/page1/collider rect 0.8 1.1
/gscore/scene/page1/on collisionEnter /score/pageHit
```

---

## Binding existing Godot nodes

```
/gscore/app/root "<absolute_node_path>"          # base for relative binds
/gscore/bind <id> "<absolute_node_path>"
/gscore/bindRel <id> "<relative_node_path>"
/gscore/bindGroup <osc_group_id> <godot_group>
/gscore/bindAll meta <key> [value]
/gscore/scene/<id> bind "<abs>" | bindRel "<rel>" | unbind
```

By default only **exposed** nodes can be bound (see [Permissions](#permissions--safety)). Mark a
node exposed by adding an `OscExposable` child, or by metadata:

```gdscript
# OscExposable child (controls its parent; set target_path to "." to expose itself):
osc_id, osc_auto_bind, osc_allow_bind, osc_allow_free, osc_methods, osc_properties, osc_signals

# or metadata:
node.set_meta("osc_expose", true)
node.set_meta("osc_id", "mainCursor")
```

Nodes with `OscExposable` and `osc_auto_bind = true` are **auto-bound on startup**.

### Discovery

```
/gscore/discover
/gscore/discover group <group_name>
/gscore/discover type <class_name>
/gscore/discover meta <key> [value]
```

Each match replies `/gscore/reply discover <suggested_id> <node_path> <class> <name>`.

---

## Instantiating PackedScenes

```
/gscore/scene/<id> instantiate "<scene_path>" [parent]
```

Only **whitelisted** scenes/prefixes are allowed. `res://osc_spawnable/` is whitelisted by
default; add more:

```
/gscore/assets/allowScene "<path>"
/gscore/assets/allowPrefix "<path_prefix>"
/gscore/assets/listAllowed
```

```
/gscore/scene/note42 instantiate "res://osc_spawnable/PhysicalNote.tscn"
```

---

## Physics & collision events

Global:

```
/gscore/physics enable <0|1>      pause <0|1>      debug <0|1>
/gscore/physics gravity <gx> <gy>
/gscore/physics coord <normalized|pixels|world>
/gscore/physics/layer <number> <name>
```

> Gravity is applied by gscore as an explicit per-body force, so it responds immediately and is
> fully under OSC control. Set e.g. `gravity 0 -1` to make things fall.

> `debug 1` shows Godot's collision shapes **and** draws a per-joint overlay (a line between the two
> bodies, a pivot marker, and the working axis for a hinge/slider) — joints have no visual of their
> own, so this is how you see them. `debug 0` removes both.

Per object (`static → StaticBody2D`, `rigid → RigidBody2D`, `area → Area2D`):

```
/gscore/scene/<id>/physics enable <static|rigid|area>
/gscore/scene/<id>/physics mass <f> | gravityScale <f> | friction <f> | bounce <f>
/gscore/scene/<id>/physics damping <lin> <ang> | velocity <vx> <vy> | angularVelocity <f>
/gscore/scene/<id>/physics force <fx> <fy> | impulse <ix> <iy> | torque <f>
/gscore/scene/<id>/physics lockRotation <0|1> | freeze <0|1> | bindTransform <0|1>
/gscore/scene/<id>/physics layer <n_or_name> | mask <n_or_name> [...]
```

Colliders (2D: `rect`/`circle`/`polygon`; 3D: `box`/`rect`→box, `sphere`/`circle`→sphere). Enabling
physics **auto-creates a collision shape matching the visible mesh** (like `collider auto`), so a body
can collide and be sensed by areas out of the box; a `collider` command replaces the automatic shape.
Collider *sizes* use the physics coordinate mode (in normalized 3D they are ×5 the world half-extent),
so match them to the visual — or just rely on the automatic shape:

```
/gscore/scene/<id>/collider rect <w> <h> | circle <r> | polygon <x1> <y1> ... | auto
/gscore/scene/<id>/collider box <w> <h> [d] | sphere <r>          # 3D
/gscore/scene/<id>/collider disabled <0|1> | offset <x> <y> [z]
```

Events:

```
/gscore/scene/<id>/on <event> <target> [options...]
/gscore/scene/<id>/off <event> [target]
/gscore/scene/<id>/payload <event> <fields...>
```

Events: `collisionEnter collisionExit areaEnter areaExit sleep wake` and continuous
`velocityAbove velocityBelow yAbove yBelow` (threshold = the binding's `minIntensity`);
`collisionStay` (each body currently touching — per-body throttled by `maxRate`);
`areaStay` (each body inside an area zone, per-body throttled — see
[Sensors & trigger zones](#sensors--trigger-zones)).

Options: `minIntensity <f>  cooldown <s>  maxRate <hz>  other <id_or_pattern>
layer <name|number>  mode immediate|queued|bundle|quantized  quantizeGrid <beats>`.
`layer` fires only when the other body is on that collision layer (name registered via
`/gscore/physics/layer`, or the bit number). `mode`: `immediate` (default); `queued` flushes at
end of frame; `bundle` packs the frame's events as one OSC bundle; `quantized` holds until the
next transport beat (`quantizeGrid <beats>`, default 1; transport must be playing).

Payload fields: `self other x y worldX worldY vx vy speed relativeSpeed intensity impulse
normalX normalY time beat mass angle angularVelocity`. Default:
`self other intensity x y vx vy time`.

A canonical message is also emitted for every physics event:

```
/gscore/event/physics <event> <self> <other> <intensity> <x> <y> <vx> <vy>
```

Example:

```
/gscore/scene/note1/on collisionEnter /synth/hit minIntensity 0.2 cooldown 0.05
/gscore/scene/note1/payload collisionEnter self other intensity x y time
# -> /synth/hit note1 floor 0.42 0.0 -0.8 3.12
```

### Interaction events

```
/gscore/scene/<id>/on click|down|up|drag|enter|leave <target>
```

Any visual object or notation region is clickable (centralized hit-testing — no per-object
Area2D needed). Canonical: `/gscore/event/input <event> <self> <x> <y>`.

---

## Physics joints

Joints constrain two physics bodies and live in their own namespace `/gscore/joint/<id>` with
their own id space (separate from scene objects). Both endpoints must have physics enabled; at
least one must be non-static.

```
/gscore/joint/<id> new <type> <a> <b>
/gscore/joint/<id> <property> [args...]
/gscore/joint/<id> del | info
/gscore/joints list
```

**Types — native per space:**

| Space | Types |
|-------|-------|
| 2D | `pin`  `spring`/`dampedSpring`  `groove`  `distance` |
| 3D | `pin`  `hinge`  `slider`  `coneTwist`  `generic6dof` |

**Properties:**

| Property | Meaning |
|----------|---------|
| `stiffness <0..1>` / `damping <0..1>` | Spring feel (normalized, mapped per backend) |
| `restLength <norm>` | Spring equilibrium length (normalized, coord-mapped) |
| `limit <lower> <upper>` | Angular joints: degrees; linear (slider/groove): normalized length |
| `motor <speed> <torque>` | 2D `pin`: target velocity (torque is a no-op). 3D `hinge`: velocity + max impulse |
| `axis <x> <y> <z>` | 3D working axis for `hinge`/`slider`/`coneTwist` (default A→B) |
| `dof <linX\|linY\|linZ\|angX\|angY\|angZ\|lin\|ang\|all>` | `generic6dof` DOF selector |
| `breakForce <0..1>` | Snaps joint when overstretched; emits `/gscore/event/jointBreak <id> <a> <b>` |

> `breakForce` is an overstretch proxy — Godot exposes no joint reaction force, so the joint snaps
> when endpoints are pulled too far apart (most effective on spring/distance/slider; a rigid `pin`
> effectively never snaps). The 2D `pin` `motor` torque argument is a no-op (not exposed by Godot's
> 2D pin motor).

**2D example — note hanging on a spring:**

```
/gscore/scene/anchor/physics enable static
/gscore/scene/note/physics enable rigid
/gscore/joint/string1 new dampedSpring anchor note
/gscore/joint/string1 stiffness 0.8
/gscore/joint/string1 damping 0.1
/gscore/joint/string1 restLength 0.4
```

**3D example — swinging hinge:**

```
/gscore/scene/post/physics enable static
/gscore/scene/arm/physics enable rigid
/gscore/joint/hinge1 new hinge post arm
/gscore/joint/hinge1 axis 0 0 1
/gscore/joint/hinge1 limit -60 60
/gscore/joint/hinge1 motor 2.0 0.5
```

---

## Sensors & trigger zones

An **area** object (`physics enable area` + a collider) acts as a sensor: it reports when other
bodies enter, leave, or remain inside it — useful for form sections, presence triggers, and spatial
gates.

```
/gscore/scene/zoneA/physics enable area
/gscore/scene/zoneA/collider rect 0.4 0.3
/gscore/scene/zoneA/on areaEnter /form/section
/gscore/scene/zoneA/on areaExit  /form/leave
/gscore/scene/zoneA/on areaStay  /zone/presence maxRate 20
```

`areaEnter`/`areaExit` fire as bodies cross the boundary. `areaStay` fires every physics frame for
each body currently inside, throttled **per body** by `maxRate`.

Use `other*` payload fields to stream each contained body's position and velocity
(`otherx othery otherz othervx othervy othervz otherspeed`); `x`/`y`/`speed` describe the zone
itself. Filters (`other <id|prefix*>`, `layer <name|number>`) restrict which bodies fire events.

**Literal payload tags** — prefix a payload token with `=` (or `'`) to embed a constant string:

```
/gscore/scene/zoneA/payload areaEnter self other =A
# -> /form/section zoneA note17 A
```

---

## Camera control

**3D only** — ignored in 2D (no camera). Positions and look-at points use the same normalized
coordinates as everything else (`x/y/z ∈ [-1,1]`); FOV is degrees.

```
/gscore/camera pos <x> <y> <z>                  # move camera (normalized, stops tracking)
/gscore/camera lookAt <x> <y> <z>               # aim at a point (stops tracking)
/gscore/camera up <x> <y> <z>                   # override the up vector
/gscore/camera fov <degrees>                     # field of view
/gscore/camera projection <perspective|orthographic>
/gscore/camera orthoSize <norm>                  # orthographic extent (normalized)
/gscore/camera target <id>                       # re-aim each frame at a scene object (stays put)
/gscore/camera follow <id> [dist]                # chase-cam: keep current offset, aim at object
/gscore/camera reset                             # restore default framing, clear tracking
/gscore/camera info                              # -> /gscore/reply camera pos x y z fov projection tracking ...
```

`target` keeps the camera stationary and re-aims it each frame; `follow` also moves it, preserving
the offset from when the call was made (`dist` overrides that distance). Any `pos`/`lookAt`/`reset`
command stops tracking. If a tracked object is removed, tracking stops automatically.

### Scene clear vs reset

```
/gscore/scene clear   # removes objects/joints/time-maps; keeps global config (physics, gravity, camera)
/gscore/scene reset   # full "like first run" reset: clear + disable physics + zero gravity +
                      # reset camera + drop buffered events + restore default coord modes.
                      # Safety config (permissions, whitelist, developer mode) and transport preserved.
```

---

## Controlled method / property access

Only members exposed via `OscExposable` / metadata are reachable (unless developer mode is on):

```
/gscore/scene/<id> prop <property> <value...>
/gscore/scene/<id> getProp <property>
/gscore/scene/<id> call <method> [args...]
```

Multi-value `prop`/`call` args coerce by count: 2 → `Vector2`, 3 → `Vector3`, 4 → `Color`.
Denied access replies `/gscore/error permission_denied <address> <message>`.

---

## Signal-to-OSC forwarding

```
/gscore/scene/<id>/signal <godot_signal> <target> [payload <tokens...>]
```

Default payload: `<osc_id> <signal_name> <signal_args...>`. Payload tokens:
`self | signal | value | args | arg0..argN`.

```
/gscore/scene/button/signal pressed /ui/buttonPressed
# pressing the button -> /ui/buttonPressed button pressed
```

---

## Transport & time mapping

```
/gscore/transport play | stop | pause
/gscore/transport seek <seconds> | tempo <bpm>
/gscore/transport time | beat | state
```

Map transport time onto any property:

```
/gscore/scene/<id> map <t0> <t1> <property> <from> <to>
/gscore/scene/cursor map 0 60 x -0.9 0.9
/gscore/scene/score/cursor map 0 60 x 0.05 0.95
```

---

## Script runner

One OSC-style command per line; `#` comments; quoted strings stay strings; numbers/bools auto-type.

```
/gscore/script/run "<one line>"
/gscore/script/load "<path.gscore>"
```

See `addons/gscore_osc/examples/example_score.gscore`.

---

## Permissions & safety

Conservative defaults (Project Settings → `gscore_osc/permissions/`):

| Capability | Default |
|---|---|
| `bindExisting` | on, but **only exposed nodes** unless developer mode |
| `instantiate` | on, but **only whitelisted** scenes/prefixes |
| `callMethods` | on, but **only exposed methods** |
| `setProps` | on, but **only exposed properties** |
| `freeNodes` | **off** |

Toggle at runtime:

```
/gscore/app/permissions bindExisting|instantiate|callMethods|setProps|freeNodes <0|1>
/gscore/app/developer <0|1>          # developer mode relaxes restrictions for local prototyping
```

Set `gscore_osc/developer_mode = true` (Project Settings) for unrestricted local prototyping.

---

## Errors

```
/gscore/error <code> <address> <message>
```

Codes: `unknown_object  unknown_property  bad_arguments  unsupported_type  load_failed
permission_denied  internal_error`.

---

## API reference

Replies use `/gscore/reply <topic> ...`. Compact map:

```
# system
/gscore ping                         -> /gscore/pong
/gscore/version | /gscore version    -> /gscore/reply version "0.5.0"
/gscore/info    | /gscore info       -> /gscore/reply info ...
/gscore/app coord <mode>
/gscore/app root "<path>"
/gscore/app output <host> <port>
/gscore/app developer <0|1>
/gscore/app permissions <flag> <0|1>

# scene-wide
/gscore/scene clear | reset | list | tree
/gscore/scene/list                   -> /gscore/reply scene/list <ids...>
/gscore/scene/tree                   -> /gscore/reply scene/tree <id type ownership path ...>

# object lifecycle / transform / style / query   (see "Creating objects")
/gscore/scene/<id> new <type> [args] | instantiate "<path>" [parent]
/gscore/scene/<id> bind "<abs>" | bindRel "<rel>" | unbind | del | free
/gscore/scene/<id> show|hide|pos|x|y|z|size|width|height|scale|rotate|opacity|color|text
/gscore/scene/<id> get <p> | get * | dump | capabilities | exists
/gscore/scene/<id> methods | properties | signals
/gscore/scene/<id> prop <p> <v...> | getProp <p> | call <m> [args]
/gscore/scene/<id> map <t0> <t1> <prop> <from> <to>

# notation                                          (see "Music notation")
/gscore/scene/<id> notation <fmt> <src_or_data> | notationData | notationSource | notationFormat | render | reload
/gscore/scene/<id> page <n> | nextPage | prevPage | pages | notationInfo
/gscore/scene/<id> addressable <0|1> | measures | elements   # MuseScore measures / LilyPond notes
/gscore/scene/<id>/cursor show|pos|color|width|map|measure|beat|time|follow
/gscore/scene/<id>/region <rid> rect|measure|on|highlight|color
/gscore/scene/<id>/annotation <aid> text|rect|glyph|color|show|hide|del
/gscore/scene/<id>/regions | /annotations | /notationInfo | /pages | /currentPage
/gscore/notation/cache clear | info

# physics / events                                  (see "Physics & collision events")
/gscore/physics enable|pause|gravity|debug|coord     /gscore/physics/layer <n> <name>
/gscore/scene/<id>/physics enable|mass|gravityScale|friction|bounce|damping|velocity|...
/gscore/scene/<id>/collider rect|circle|polygon|auto|disabled|offset
/gscore/scene/<id>/on <event> <target> [opts]   /off   /payload   /signal

# camera (3D only)
/gscore/camera pos <x> <y> <z> | lookAt <x> <y> <z> | up <x> <y> <z>
/gscore/camera fov <deg> | projection <perspective|orthographic> | orthoSize <norm>
/gscore/camera target <id> | follow <id> [dist] | reset | info

# binding / discovery / assets / transport / script
/gscore/bind | /gscore/bindRel | /gscore/bindGroup | /gscore/bindAll meta
/gscore/discover [group|type|meta] ...
/gscore/assets allowScene|allowPrefix|listAllowed
/gscore/transport play|stop|pause|seek|tempo|time|beat|state
/gscore/script run "<line>" | load "<path>"
```

---

## Verifying

No external dependencies. With Godot 4.7 on `PATH` (or use the full binary path):

```bash
# 1. parse/import check + boot the project headlessly
godot --headless --path . --quit-after 300

# 2. internal self-tests (OSC codec roundtrip + SVG backend)
godot --headless --path . --script res://tools/test_internals.gd

# 3. full over-the-wire acceptance test:
#    terminal A:
godot --headless --path .
#    terminal B:
py tools/osc_test.py
#    -> prints replies/events and "10/10 checks passed"
```

`tools/osc_test.py` is a dependency-free reference OSC client for Python.

---

## Known limitations

- Manual notation regions are still supported, and addressable regions are auto-generated from
  engraver output: measures (MuseScore) and notes (LilyPond / Verovio), with cursor following.
  `system`/`staff`/`part` addressing is not auto-generated yet.
- Symbolic formats (MusicXML/MEI/…) require an external engraver configured in project settings;
  there is no in-engine engraving.
- The lightweight `glyphs` backend is a stub (returns a clear error).
- `velocityAbove/Below`, `yAbove/Below`, `bindTransform` and physics `debug` are functional but
  minimal. `positionEnter`/`positionExit` were intentionally not implemented — use area zones
  (`areaEnter`/`areaExit`/`areaStay`) or `yAbove`/`yBelow` instead.
- OSC over UDP only (no TCP); no variables in the script runner.
- The 2D/3D mode is global per run (`gscore_osc/space`), chosen at boot — not per-object, and not
  switchable at runtime.
- In 3D: `pixels` coord mode falls back to world units; click picking uses the object's axis-
  aligned bounding box (not exact mesh geometry); a single `Camera3D` is auto-created only if the
  scene has none.
- A bound RigidBody2D with non-zero `gravity_scale` will receive both Godot's gravity and
  gscore's applied gravity — set its `gravity_scale` to 0, or use OSC-created bodies.
- SVG rasterization depends on the Godot build's SVG module (present in standard 4.7 builds).

---

## Project layout

```
addons/gscore_osc/
  plugin.cfg, plugin.gd
  core/      OscServer  OscPacket  OscDispatcher  GScoreRegistry  GScoreObject
             GScoreFactory  GScorePermissions  GScoreCoordinateMapper  GScorePrimitive2D
             GScoreSpatial2D  GScoreSpatial3D          # spatial backends (2D / 3D)
  notation/  GScoreNotation(Object|Renderer|RenderResult|Cache|Region|Cursor|Annotation)
             GScoreNotationObject3D  GScoreNotationRegion3D   # 3D notation
             GScoreNotationBackend(Image|Svg|MusicXML)
  physics/   GScorePhysicsWorld  GScorePhysicsAdapter  GScoreColliderBuilder  GScoreCollisionEvents
  events/    GScoreEvents  GScoreEventBinding  GScoreSignalBinding  GScoreInputEvents
  transport/ GScoreTransport  GScoreTimeMapper
  script/    GScoreScriptRunner
  nodes/     GScoreRoot  OscExposable
  examples/  ExampleMain.tscn / .gd          (2D)   example_score.gscore
             ExampleMain3D.tscn / .gd        (3D)   example_score_3d.gscore
             ExamplePhysicalNote.tscn  ExampleNotationScore.tscn / .gd
osc_spawnable/PhysicalNote.tscn  PhysicalNote3D.tscn   # whitelisted spawnables
scores/page1.png                       # placeholder engraved page
tools/  osc_test.py  gen_assets.gd  test_internals.gd
        ly_to_score.py  mscore_to_score.py  verovio_render.py   # engraver wrappers
```

## Requirements

- **Godot 4.7** (uses stable Godot 4.x APIs).
- Optional, only for symbolic-notation engraving (PNG/SVG display needs none of these):
  - **MuseScore 4** — MusicXML rendering + addressable measures.
  - **LilyPond 2.24+** — `.ly` rendering + note-level addressing/following.
  - **Verovio** (`pip install verovio`) — MEI/ABC/MusicXML rendering + note-level addressing/following.
  - **Python 3** — for the bundled engraver wrappers and `tools/osc_test.py`.

## License

gscore_osc is licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE).

