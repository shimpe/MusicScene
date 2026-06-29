# gscore_osc

An **OSC-controlled, INScore-inspired interactive music-score / world system** for Godot 4.

External OSC clients (Max/MSP, Pure Data, SuperCollider, Python, TouchDesigner, Ableton
bridges, …) can **create, bind, control, animate, query, and receive events** from Godot scene
objects under the root namespace `/gscore`. Beyond INScore it adds **Godot 2D physics,
collision-driven OSC emission, binding to existing nodes, PackedScene instantiation, exposing
methods/properties/signals over OSC, and first-class music-notation display**.

Built as a Godot addon at `addons/gscore_osc/`. Pure GDScript. Targets **Godot 4.7** (uses
stable Godot 4.x APIs).

> Status: the vertical slice and the full v1 API are implemented and verified headlessly against
> Godot 4.7 — see [Verifying](#verifying). `10/10` OSC acceptance checks pass, plus codec, SVG
> and signal-forwarding self-tests.

---

## Table of contents

- [What it is](#what-it-is) · [Core principle](#core-principle) · [Install / start](#install--start)
- [Ports](#ports--networking) · [Coordinates](#coordinate-system) · [Creating objects](#creating-objects)
- [Notation](#music-notation) (backends, cursor, regions, annotations) · [Binding nodes](#binding-existing-godot-nodes)
- [Instantiating scenes](#instantiating-packedscenes) · [Physics & collisions](#physics--collision-events)
- [Methods/props](#controlled-method--property-access) · [Signals](#signal-to-osc-forwarding)
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
2. Press **Play**. `ExampleMain.tscn` runs, the OSC server starts, and the bundled
   `example_score.gscore` plays automatically (a score page, a red cursor sweep, a highlighted
   measure region, and a bouncing note that emits OSC on impact).
3. Send `/gscore/ping` from any OSC client → you get `/gscore/pong`.

To use it in your own project: copy `addons/gscore_osc/` in, enable the **gscore_osc** plugin in
*Project → Project Settings → Plugins* (this installs the `GScoreOSC` autoload). Configuration
lives under *Project Settings → gscore_osc/…* (see below).

### Generating the placeholder score

A placeholder engraved page (`res://scores/page1.png`) is included. To regenerate it:

```
<godot> --headless --path . --script res://tools/gen_assets.gd
```

---

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

**Notation-internal** coordinates (cursor `pos`, region/annotation `rect`) are always `[0,1]`
over the page rect, top-left origin, y-down.

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
/gscore/scene/<id> notation <format> <source>
/gscore/scene/<id> notationSource <source>
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
| `svg` | **svg** | rasterized at runtime via `Image.load_svg_from_string` (verified on 4.7) |
| `musicxml` `mei` `guido` `abc` `lilypond` `pdf` | **external** | shells out to a configured engraver → PNG/SVG, cached |

Display any engraved page produced by MuseScore, LilyPond, Verovio, Dorico, Finale or Sibelius
by exporting to PNG/SVG and pointing the image/svg backend at it.

**Multi-page** raster/SVG: put `{page}` in the source path (e.g. `res://scores/p{page}.png`);
the page count is probed automatically and `page`/`nextPage`/`prevPage` switch pages.

**External engraver** configuration (Project Settings → `gscore_osc/notation/`):

```
external_renderer_path  e.g. "C:/Program Files/MuseScore 4/bin/MuseScore4.exe"
external_renderer_args  e.g. "{input} -o {output}"      tokens: {input} {output} {format} {page}
```

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

Per object (`static → StaticBody2D`, `rigid → RigidBody2D`, `area → Area2D`):

```
/gscore/scene/<id>/physics enable <static|rigid|area>
/gscore/scene/<id>/physics mass <f> | gravityScale <f> | friction <f> | bounce <f>
/gscore/scene/<id>/physics damping <lin> <ang> | velocity <vx> <vy> | angularVelocity <f>
/gscore/scene/<id>/physics force <fx> <fy> | impulse <ix> <iy> | torque <f>
/gscore/scene/<id>/physics lockRotation <0|1> | freeze <0|1> | bindTransform <0|1>
/gscore/scene/<id>/physics layer <n_or_name> | mask <n_or_name> [...]
```

Colliders:

```
/gscore/scene/<id>/collider rect <w> <h> | circle <r> | polygon <x1> <y1> ... | auto
/gscore/scene/<id>/collider disabled <0|1> | offset <x> <y>
```

Events:

```
/gscore/scene/<id>/on <event> <target> [options...]
/gscore/scene/<id>/off <event> [target]
/gscore/scene/<id>/payload <event> <fields...>
```

Events: `collisionEnter collisionExit areaEnter areaExit sleep wake` and continuous
`velocityAbove velocityBelow yAbove yBelow` (threshold = the binding's `minIntensity`). Options:
`minIntensity <f>  cooldown <s>  maxRate <hz>  layer <name>  other <id_or_pattern>  mode <…>`.

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
/gscore/version | /gscore version    -> /gscore/reply version "0.1.0"
/gscore/info    | /gscore info       -> /gscore/reply info ...
/gscore/app coord <mode>
/gscore/app root "<path>"
/gscore/app output <host> <port>
/gscore/app developer <0|1>
/gscore/app permissions <flag> <0|1>

# scene-wide
/gscore/scene clear | list | tree
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
/gscore/scene/<id> notation <fmt> <src> | notationSource | notationFormat | render | reload
/gscore/scene/<id> page <n> | nextPage | prevPage | pages | notationInfo
/gscore/scene/<id>/cursor show|pos|color|width|map|measure|beat|time
/gscore/scene/<id>/region <rid> rect|measure|on|highlight|color
/gscore/scene/<id>/annotation <aid> text|rect|glyph|color|show|hide|del
/gscore/scene/<id>/regions | /annotations | /notationInfo | /pages | /currentPage
/gscore/notation/cache clear | info

# physics / events                                  (see "Physics & collision events")
/gscore/physics enable|pause|gravity|debug|coord     /gscore/physics/layer <n> <name>
/gscore/scene/<id>/physics enable|mass|gravityScale|friction|bounce|damping|velocity|...
/gscore/scene/<id>/collider rect|circle|polygon|auto|disabled|offset
/gscore/scene/<id>/on <event> <target> [opts]   /off   /payload   /signal

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

- Notation regions are defined manually in v1; auto-generating them from engraver bounding boxes
  is a future extension. `system`/`staff`/`measure`/`part` are stored but have no geometry yet.
- Symbolic formats (MusicXML/MEI/…) require an external engraver configured in project settings;
  there is no in-engine engraving.
- The lightweight `glyphs` backend is a stub (returns a clear error).
- `velocityAbove/Below`, `yAbove/Below`, `bindTransform` and physics `debug` are functional but
  minimal; `collisionStay`/`areaStay`/`positionEnter`/`positionExit` are not implemented in v1.
- OSC over UDP only (no TCP); no variables in the script runner.
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
  notation/  GScoreNotation(Object|Renderer|RenderResult|Cache|Region|Cursor|Annotation)
             GScoreNotationBackend(Image|Svg|MusicXML)
  physics/   GScorePhysicsWorld  GScorePhysicsAdapter  GScoreColliderBuilder  GScoreCollisionEvents
  events/    GScoreEvents  GScoreEventBinding  GScoreSignalBinding  GScoreInputEvents
  transport/ GScoreTransport  GScoreTimeMapper
  script/    GScoreScriptRunner
  nodes/     GScoreRoot  OscExposable
  examples/  ExampleMain.tscn  ExamplePhysicalNote.tscn  ExampleNotationScore.tscn  example_score.gscore
osc_spawnable/PhysicalNote.tscn        # whitelisted spawnable
scores/page1.png                       # placeholder engraved page
tools/  osc_test.py  gen_assets.gd  test_internals.gd
```
