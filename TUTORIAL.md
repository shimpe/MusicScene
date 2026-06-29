# gscore_osc — Getting Started Tutorial

This walks you through using the **gscore_osc** addon in a brand-new Godot project, first in
**2D** and then in **3D**. By the end you'll be creating objects, displaying a music score,
driving physics, and receiving collision/interaction events — all over OSC from an external
client.

> Same OSC API in both dimensions. The only difference is one project setting (`gscore_osc/space`)
> and whether your main scene is a `Node2D` or a `Node3D`.

- [0. Prerequisites](#0-prerequisites)
- [1. Install the addon](#1-install-the-addon-into-a-new-project)
- [2. A tiny OSC client](#2-a-tiny-osc-client)
- [3. Smoke test: ping](#3-smoke-test-ping)
- [4. Getting started in 2D](#4-getting-started-in-2d)
- [5. Getting started in 3D](#5-getting-started-in-3d)
- [Displaying scores — every source option](#displaying-scores--every-source-option)
- [6. Driving it from a `.gscore` script](#6-driving-it-from-a-gscore-script)
- [7. Connecting from Max / Pd / SuperCollider](#7-connecting-from-max--pd--supercollider)
- [8. Permissions & safety](#8-permissions--safety)
- [9. Troubleshooting](#9-troubleshooting)

---

## 0. Prerequisites

- **Godot 4.4+** (developed and verified on **4.7**).
- The **`addons/gscore_osc/`** folder from this repository.
- An **OSC client**. This tutorial uses a tiny Python script (section 2); Max/Pd/SuperCollider
  notes are in section 7.

You do **not** need any third-party Godot OSC library — gscore_osc has its own UDP OSC codec.

---

## 1. Install the addon into a new project

1. **Create a project**: Godot Project Manager → *New Project* → e.g. `MyScoreWorld` → *Create & Edit*.
2. **Copy the addon**: copy the `addons/gscore_osc/` folder into your project so you have
   `res://addons/gscore_osc/`. (Drag it into the FileSystem dock, or copy on disk and let Godot
   import it.)
3. **Enable the plugin**: *Project → Project Settings → Plugins* → enable **gscore_osc**.
   Enabling it installs an **autoload singleton** named **`GScoreOSC`** (the controller that runs
   the OSC server and owns every subsystem).
4. **Verify**: press **Play** (you can run an empty scene for now and dismiss the "no main scene"
   prompt by picking any scene, or just continue to section 4). In the **Output** panel you should
   see:

   ```
   [GScoreOSC] OSC server listening on udp:7400, replies -> 127.0.0.1:7401
   [GScoreOSC] ready (space=2d). Send /gscore/ping to test.
   ```

That's it — the OSC server is live on **UDP 7400** (it sends replies/events to the last sender's
IP on **UDP 7401**).

> **Settings are optional.** gscore_osc reads every setting with a sensible default, so it works
> with zero configuration. You only need to add a setting when you want to change a default — most
> importantly `gscore_osc/space = "3d"` for the 3D walkthrough (section 5).

---

## 2. A tiny OSC client

Save this as **`gosc.py`** somewhere handy. It sends `/gscore/...` messages and prints anything
gscore_osc sends back. (A fuller version ships at `tools/osc_test.py` in this repo.)

```python
# gosc.py — minimal OSC client for gscore_osc
import socket, struct, threading, time

HOST, SEND_PORT, RECV_PORT = "127.0.0.1", 7400, 7401

def _pad(b): return b + b"\x00" * ((4 - len(b) % 4) % 4)
def _ostr(s): return _pad(s.encode() + b"\x00")

def msg(addr, *args):
    tt, payload = ",", b""
    for a in args:
        if isinstance(a, bool):  tt += "T" if a else "F"
        elif isinstance(a, int): tt += "i"; payload += struct.pack(">i", a)
        elif isinstance(a, float): tt += "f"; payload += struct.pack(">f", a)
        else: tt += "s"; payload += _ostr(str(a))
    return _ostr(addr) + _ostr(tt) + payload

def _rstr(d, i):
    e = d.index(b"\x00", i); s = d[i:e].decode("utf-8", "replace"); i = e + 1
    return s, i + ((4 - i % 4) % 4)

def decode(d):
    if d[:8] == b"#bundle\x00":
        out, i = [], 16
        while i + 4 <= len(d):
            n = struct.unpack_from(">i", d, i)[0]; i += 4
            out += decode(d[i:i+n]); i += n
        return out
    addr, i = _rstr(d, 0)
    if i >= len(d): return [(addr, [])]
    tt, i = _rstr(d, i); args = []
    for c in tt[1:]:
        if c == "i": args.append(struct.unpack_from(">i", d, i)[0]); i += 4
        elif c == "f": args.append(round(struct.unpack_from(">f", d, i)[0], 4)); i += 4
        elif c in "sS": v, i = _rstr(d, i); args.append(v)
        elif c == "T": args.append(True)
        elif c == "F": args.append(False)
        elif c in "htd": i += 8
    return [(addr, args)]

_recv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
_recv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
_recv.bind((HOST, RECV_PORT)); _recv.settimeout(0.3)
_send = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

def _listen():
    while True:
        try: data, _ = _recv.recvfrom(65535)
        except socket.timeout: continue
        for a, ar in decode(data): print("  <-", a, ar)
threading.Thread(target=_listen, daemon=True).start()

def s(addr, *args):
    _send.sendto(msg(addr, *args), (HOST, SEND_PORT))
    print("->", addr, list(args)); time.sleep(0.05)

if __name__ == "__main__":
    import code; code.interact(local=globals())   # interactive: type s("/gscore/ping")
```

Run it with `python gosc.py` (or `py gosc.py` on Windows) for an interactive prompt where you can
type `s("/gscore/ping")`, or `import gosc` from your own script.

---

## 3. Smoke test: ping

With your Godot project **running**, in the `gosc.py` prompt:

```python
s("/gscore/ping")          # ->  <- /gscore/pong []
s("/gscore/version")       # ->  <- /gscore/reply ['version', '0.1.0']
s("/gscore/info")          # ->  <- /gscore/reply ['info', 'gscore_osc', ...]
```

If you see `<- /gscore/pong`, you're connected. If not, jump to [Troubleshooting](#9-troubleshooting).

---

## 4. Getting started in 2D

### 4.1 Make a 2D main scene

1. *Scene → New Scene → 2D Scene* (creates a `Node2D` root). Rename it `Main`, **save** as
   `res://Main.tscn`.
2. *Project → Project Settings → Application → Run* → set **Main Scene** to `res://Main.tscn`.

You don't need a camera. gscore_osc parents the objects it creates under its own autoload node and
renders them in the viewport.

> 2D is the default (`gscore_osc/space` defaults to `"2d"`), so there's nothing else to configure.

### 4.2 Coordinates

Default **normalized** coordinates: `x ∈ [-1,1]` left→right, `y ∈ [-1,1]` bottom→top (y-up), with
`(0,0)` at the viewport centre. (You can switch to `pixels`/`world` with `/gscore/app/coord`.)

### 4.3 Create your first objects

Press **Play**, then from `gosc.py`:

```python
s("/gscore/scene/title", "new", "text", "Hello, score-world")
s("/gscore/scene/title", "pos", 0.0, 0.8)
s("/gscore/scene/title", "color", 1.0, 1.0, 1.0, 1.0)

s("/gscore/scene/box", "new", "rect")
s("/gscore/scene/box", "pos", -0.4, 0.0)
s("/gscore/scene/box", "color", 0.3, 0.7, 1.0, 1.0)

s("/gscore/scene/ball", "new", "circle")
s("/gscore/scene/ball", "pos", 0.4, 0.0)
s("/gscore/scene/ball", "scale", 1.5)
```

You should see a title, a blue rectangle, and a circle appear. Every object shares the same
commands: `show/hide`, `pos/x/y`, `size/scale/rotate`, `opacity/color`, `del`, etc. Query them:

```python
s("/gscore/scene/list")              # <- reply scene/list title box ball
s("/gscore/scene/ball", "dump")      # <- reply dump ball circle created_by_osc pos ...
s("/gscore/scene/ball", "capabilities")
```

### 4.4 Animate with the transport

`map` interpolates a property over transport time:

```python
s("/gscore/scene/ball", "map", 0.0, 4.0, "x", 0.4, -0.9)   # slide x over 4 seconds
s("/gscore/transport", "tempo", 120.0)
s("/gscore/transport", "play")
```

### 4.5 Display a music score

Point a `notation` object at any PNG (export one from MuseScore/LilyPond/Verovio, or use the
bundled `res://scores/page1.png` if you copied it):

```python
s("/gscore/scene/score", "new", "notation")
s("/gscore/scene/score", "notation", "png", "res://scores/page1.png")
s("/gscore/scene/score", "pos", 0.0, 0.0)
s("/gscore/scene/score", "scale", 0.9)
# a red playback cursor (page coords are [0,1])
s("/gscore/scene/score/cursor", "show", 1)
s("/gscore/scene/score/cursor", "color", 1.0, 0.0, 0.0, 0.8)
s("/gscore/scene/score/cursor", "map", 0.0, 8.0, "x", 0.05, 0.95)   # sweep with transport
# a clickable region over measure 1
s("/gscore/scene/score/region", "m1", "rect", 0.1, 0.25, 0.2, 0.1)
s("/gscore/scene/score/region", "m1", "highlight", 1)
s("/gscore/scene/score/region", "m1", "on", "click", "/score/measure")
s("/gscore/scene/score", "notationInfo")   # <- reply notationInfo score png ... image 1
```

Click the highlighted region in the Godot window → you receive `/score/measure score m1 <u> <v>`.

> SVG works too (`notation svg "res://scores/page.svg"`). MusicXML/MEI/LilyPond route to an
> external engraver you configure in Project Settings (`gscore_osc/notation/external_renderer_*`).

### 4.6 Physics and collision → OSC

```python
# a static floor
s("/gscore/scene/floor", "new", "rect")
s("/gscore/scene/floor", "pos", 0.0, -0.8)
s("/gscore/scene/floor", "size", 1.8, 0.05)
s("/gscore/scene/floor/physics", "enable", "static")
s("/gscore/scene/floor/collider", "rect", 1.8, 0.05)

# a bouncing note that emits OSC when it lands
s("/gscore/scene/note1", "new", "circle")
s("/gscore/scene/note1", "pos", 0.0, 0.9)
s("/gscore/scene/note1/physics", "enable", "rigid")
s("/gscore/scene/note1/collider", "circle", 0.05)
s("/gscore/scene/note1/physics", "bounce", 0.7)
s("/gscore/scene/note1/on", "collisionEnter", "/synth/hit", "minIntensity", 0.05, "cooldown", 0.05)
s("/gscore/scene/note1/payload", "collisionEnter", "self", "other", "intensity", "x", "y", "time")

# turn on gravity (normalized: negative y = down)
s("/gscore/physics", "enable", 1)
s("/gscore/physics", "gravity", 0.0, -0.6)
```

The note falls and on impact you receive e.g. `/synth/hit note1 floor 0.42 0.0 -0.8 3.12`, plus a
canonical `/gscore/event/physics ...`. Map intensity to a synth and you have a physical score.

### 4.7 Bind an existing node and forward its signal

To control nodes that already exist in your scene, mark them **exposed**:

1. In `Main.tscn`, add a **Button** (Control). Add a child **Node**, attach the script
   `res://addons/gscore_osc/nodes/OscExposable.gd` to it (or add it via *Add Node → OscExposable*),
   and set its `osc_id` to `playButton`. Leave `osc_auto_bind` on.
2. Press Play. The button is auto-bound. Forward its `pressed` signal:

   ```python
   s("/gscore/scene/playButton/signal", "pressed", "/ui/play")
   ```

   Click the button → you receive `/ui/play playButton pressed`.

To bind a node on demand instead of auto-binding, point the addon at a root and use a relative
path:

```python
s("/gscore/app/root", "/root/Main")
s("/gscore/bindRel", "myNode", "SomeChild/Path")
```

> By default only **exposed** nodes can be bound (safe default). For quick prototyping, set
> `gscore_osc/developer_mode = true` to bind/call/set anything.

---

## 5. Getting started in 3D

Everything you just learned applies — objects become 3D, coordinates gain a `z`, and notation
renders on a quad in world space.

### 5.1 Switch to 3D

Add the project setting **`gscore_osc/space = "3d"`**. Two easy ways:

- **Editor:** *Project → Project Settings*, turn on *Advanced Settings*, in the property box type
  `gscore_osc/space`, set type *String*, value `3d`, click **Add**.
- **Text:** add to `project.godot`:

  ```ini
  [gscore_osc]
  space="3d"
  ```

The setting is read once at startup, so **restart** the running project after changing it.

### 5.2 Make a 3D main scene

1. *Scene → New Scene → 3D Scene* (creates a `Node3D` root). Rename `Main`, save as
   `res://Main3D.tscn`, and set it as the **Main Scene**.
2. (Optional) add a `DirectionalLight3D` so any *non-gscore* meshes are lit. gscore_osc's own
   primitives use unshaded materials, so they're visible without a light.

When you Play, gscore_osc **auto-creates a `Camera3D`** if your scene doesn't have one, looking at
the origin. You'll see in the console:

```
[GScoreOSC] auto-created Camera3D at z=10.4
[GScoreOSC] ready (space=3d). Send /gscore/ping to test.
```

### 5.3 3D coordinates

Normalized `x/y/z ∈ [-1,1]`, y-up, **+z toward the camera**, mapped to a world cube of half-extent
5 units. Commands take an optional `z`.

### 5.4 Create 3D objects

```python
s("/gscore/scene/box", "new", "rect")          # rect -> a flat quad
s("/gscore/scene/box", "pos", -0.4, 0.2, 0.0)
s("/gscore/scene/box", "rotate", 0, 30, 0)     # full Euler degrees (x y z)

s("/gscore/scene/ball", "new", "circle")       # circle -> a sphere
s("/gscore/scene/ball", "pos", 0.4, 0.2, 0.0)
s("/gscore/scene/ball", "color", 0.95, 0.55, 0.45, 1.0)

s("/gscore/scene/label", "new", "text", "3D score-world")  # text -> Label3D
s("/gscore/scene/label", "pos", 0.0, 0.8, 0.0)
```

### 5.5 Notation on a quad in world space

```python
s("/gscore/scene/score", "new", "notation")
s("/gscore/scene/score", "notation", "png", "res://scores/page1.png")
s("/gscore/scene/score", "pos", -0.4, 0.1, 0.0)
s("/gscore/scene/score", "rotate", 0, -18, 0)   # angle the page in 3D
s("/gscore/scene/score/cursor", "show", 1)
s("/gscore/scene/score/cursor", "map", 0.0, 8.0, "x", 0.05, 0.95)
s("/gscore/scene/score/region", "m1", "rect", 0.1, 0.25, 0.2, 0.1)
s("/gscore/scene/score/region", "m1", "highlight", 1)
s("/gscore/scene/score/region", "m1", "on", "click", "/score/measure")
s("/gscore/transport", "play")
```

The cursor, region and annotations live on the quad's surface and rotate/scale with it. Clicking
the region uses a camera ray vs the quad plane and emits `/score/measure score m1 <u> <v>`.

### 5.6 3D physics + colliders

3D adds `box` and `sphere` colliders (and accepts `rect`→box, `circle`→sphere):

```python
# floor: a flat box
s("/gscore/scene/floor", "new", "rect")
s("/gscore/scene/floor", "pos", 0.0, -0.7, 0.0)
s("/gscore/scene/floor", "scale", 3, 0.15, 3)
s("/gscore/scene/floor/physics", "enable", "static")
s("/gscore/scene/floor/collider", "box", 0.9, 0.05, 0.9)

# falling note (sphere)
s("/gscore/scene/note1", "new", "circle")
s("/gscore/scene/note1", "pos", 0.0, 0.8, 0.0)
s("/gscore/scene/note1/physics", "enable", "rigid")
s("/gscore/scene/note1/collider", "sphere", 0.1)
s("/gscore/scene/note1/physics", "bounce", 0.7)
s("/gscore/scene/note1/on", "collisionEnter", "/synth/hit", "minIntensity", 0.05)
s("/gscore/scene/note1/payload", "collisionEnter", "self", "other", "intensity", "x", "y", "z", "time")

s("/gscore/physics", "enable", 1)
s("/gscore/physics", "gravity", 0.0, -0.6, 0.0)
```

### 5.7 Binding & clicking in 3D

Expose existing 3D nodes exactly as in 2D (`OscExposable` child with an `osc_id`). Click-picking
on objects uses the camera ray vs the object's bounding box, so any visible 3D object with a
`click`/`down`/`up`/`drag` binding is interactive:

```python
s("/gscore/scene/ball/on", "click", "/hit/ball")
```

### Switching back to 2D

Set `gscore_osc/space = "2d"` (and choose a `Node2D` main scene) and restart. Same OSC scripts,
2D rendering.

---

## Displaying scores — every source option

The PNG examples above are just one way to get a score onto a notation object. A score source can
be a **file path**, **inline data sent over OSC**, or **symbolic music that gscore engraves at
run-time** — all through the same commands (works identically in 2D and 3D):

```
/gscore/scene/<id> notation <format> <source_or_data>   # path OR inline data (auto-detected)
/gscore/scene/<id> notationData <format> <data>         # force inline data (text or blob bytes)
/gscore/scene/<id> notationSource <source_or_data>      # change source, keep format
/gscore/scene/<id> render | reload                       # re-render current source
/gscore/scene/<id> page <n> | nextPage | prevPage | pages
/gscore/scene/<id> notationInfo                          # <- reply notationInfo <id> <fmt> <src> <backend> <pages>
```

Formats: **`png` `jpg` `webp` `bmp`** (raster) · **`svg`** · **`musicxml` `mei` `lilypond` `abc`**
(symbolic — these need an engraver, see C). `source_or_data` is treated as a **file path** unless
it looks like data (starts with markup `<…`, contains newlines, or is an OSC blob); use
`notationData` to force the inline interpretation.

### A. Raster images (PNG / JPG / WEBP / BMP)

The most robust option — always displays.

```python
s("/gscore/scene/score","notation","png","res://scores/page1.png")   # bundled
s("/gscore/scene/score","notation","png","user://out/page1.png")     # written at run-time
s("/gscore/scene/score","notation","png","D:/scores/page1.png")      # absolute path
```

**Multi-page**: put `{page}` in the path; gscore probes how many exist.

```python
s("/gscore/scene/score","notation","png","res://scores/p{page}.png")
s("/gscore/scene/score","nextPage")
s("/gscore/scene/score","pages")     # <- reply pages score <count>
```

**Raw bytes over OSC** (a generated image, no file on disk) — send the PNG bytes as an OSC **blob**.
Mind the UDP datagram cap (~64 KB), so this suits small images / per-system updates:

```python
# minimal blob-aware send (extends gosc.py):
def osc_blob_msg(addr, *args):
    tt, payload = ",", b""
    for a in args:
        if isinstance(a, (bytes, bytearray)):
            b = bytes(a); tt += "b"
            payload += struct.pack(">i", len(b)) + b + b"\x00"*((4-len(b)%4)%4)
        elif isinstance(a, float): tt += "f"; payload += struct.pack(">f", a)
        elif isinstance(a, int):   tt += "i"; payload += struct.pack(">i", a)
        else: tt += "s"; payload += _ostr(str(a))
    return _ostr(addr) + _ostr(tt) + payload

png = open("measure.png","rb").read()
_send.sendto(osc_blob_msg("/gscore/scene/score","notation","png",png), (HOST, SEND_PORT))
```

### B. SVG

```python
# bundled under res:// — Godot imports it (best reliability; shows a FileSystem thumbnail)
s("/gscore/scene/score","notation","svg","res://scores/score.svg")
# a file written at run-time (rasterized via Godot's ThorVG)
s("/gscore/scene/score","notation","svg","user://gen/score.svg")
# an inline SVG STRING generated at run-time (e.g. Verovio in your client) — no file needed
svg = '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="300">...</svg>'
s("/gscore/scene/score","notation","svg",svg)
```

The page renders at native pixel size centred on the object — **scale it down if it overflows**:
`s("/gscore/scene/score","scale",0.3)`. If a runtime SVG fails to rasterize (some engraver SVGs
use features ThorVG can't handle), import it under `res://` or render to PNG.

### C. Symbolic music (MusicXML / MEI / LilyPond / ABC) — gscore runs the engraver

gscore can shell out to an external engraver to turn symbolic music into pages, then display and
**cache** the result. Configure a per-format command in *Project Settings*
(`gscore_osc/notation/engraver/<format>`), using these tokens: `{input} {output} {outbase}
{outdir} {format} {page}`. Quote paths that contain spaces.

```ini
[gscore_osc]
notation/engraver/musicxml="\"C:/Program Files/MuseScore 4/bin/MuseScore4.exe\" {input} -o {output} -T 10 -r 200"
notation/engraver/lilypond="\"C:/Program Files/lilypond-2.25.81/bin/lilypond.exe\" --png -dcrop=#t -dresolution=200 -o {outbase} {input}"
notation/engraver/abc="abcm2ps {input} -O {outbase}"
notation/engraver_output="png"   ; what your command writes: "png" (default) or "svg"
```

> **Call the engraver directly** — no helper script needed. gscore automatically finds the file the
> engraver actually wrote (it looks for `{output}` plus the common `.cropped`, `-page{N}` and `-N`
> variants that LilyPond/MuseScore produce), so you usually only need to set the engraver's path.
> Quote paths that contain spaces. `res://`/`user://` paths are resolved too, so a bundled wrapper
> script (`tools/ly_to_score.py`, `tools/mscore_to_score.py`) is a portable, auto-detecting
> alternative if you'd rather not hard-code the engraver path.
>
> This project ships **working defaults for LilyPond and MuseScore** — if either is installed, the
> matching format works immediately (set your install path).

#### MuseScore — works out of the box

With MuseScore 4 installed and the default `musicxml` setting above (point it at your MuseScore
binary), engrave **MusicXML / .mxl / .mscz** immediately — from a file or inline:

```python
# from a file (any format MuseScore imports)
s("/gscore/scene/score","notation","musicxml","res://scores/example.musicxml")
# inline, generated at run-time
s("/gscore/scene/score","notationData","musicxml","<?xml ...><score-partwise> ... </score-partwise>")
```

MuseScore is called directly with `-T` (trim to the music); gscore picks up its `out-1.png` page
automatically. (Prefer auto-detecting the binary? Use the bundled `tools/mscore_to_score.py`
wrapper instead.) Note: MuseScore 4 occasionally crashes on a cold start under headless automation —
since rendered pages are cached, a retry succeeds and repeats are instant.

#### LilyPond — works out of the box

With LilyPond installed and the default setting above (point it at your `lilypond` binary), engrave
immediately — from a `.ly` file or inline (send the LilyPond source as the data):

```python
# from a .ly file
s("/gscore/scene/score","notation","lilypond","res://scores/example.ly")
# inline / runtime-generated — read the source from a file or build it (mind backslash escaping!)
ly = open("snippet.ly", encoding="utf-8").read()
s("/gscore/scene/score","notationData","lilypond",ly)
```

The default command runs LilyPond with `-dcrop=#t` (tight bounding box, no A4 whitespace); LilyPond
writes `…cropped.png`, which gscore prefers automatically. For **SVG** output use
`-dbackend=svg … -o {outbase} {input}` and set `engraver_output="svg"`. (Prefer auto-detecting the
binary? Use the bundled `tools/ly_to_score.py` wrapper instead.)

(Or set the generic fallback `notation/external_renderer_path` + `notation/external_renderer_args`
used for any symbolic format.) Then point at a file **or send inline source**:

```python
# from a file
s("/gscore/scene/score","notation","musicxml","user://flute.musicxml")
# inline, generated at run-time
xml = '<?xml version="1.0"?><score-partwise> ... </score-partwise>'
s("/gscore/scene/score","notationData","musicxml",xml)
```

gscore writes inline source to a temp file, runs your command, caches the page under
`user://gscore_cache/notation/`, and displays it. The engraver runs **once** per
(source, format, page) — repeats are cache hits.

**Engraver tips.** MuseScore and LilyPond are handled by the bundled wrappers
(`tools/mscore_to_score.py`, `tools/ly_to_score.py`) — they deal with per-page output naming and
trimming so you don't have to. For other tools (Verovio `verovio -f musicxml -t png -o {outbase}
{input}`, ABC via `abcm2ps`/`abc2svg`, etc.), wrap anything that names its own outputs in a small
`input output` script — see `tools/mscore_to_score.py` / `tools/stub_engraver.py` for the exact
contract gscore expects.

### D. The run-time-generation workflow (the common case)

Pick by score size and tooling:

1. **File + path** (no size limit, best for full pages): your generator writes
   `user://gen/score.(svg|png)`, then `notation svg "user://gen/score.svg"`. Regenerate and call
   `render`/`reload` (or send `notation` again) to refresh.
2. **Inline data over OSC** (no temp file; small/medium or per-measure): `notation svg <svg-string>`
   or `notationData musicxml <xml>`. Watch the ~64 KB UDP cap.
3. **gscore engraves symbolic data** (you push MusicXML/LilyPond/ABC, gscore renders): configure
   the engraver (C), then `notation musicxml <path-or-inline>`.

You can also drive it from inside Godot (GDScript), e.g. after generating a file:

```gdscript
GScoreOSC.script_runner.run_text('/gscore/scene/score notation svg "user://gen/score.svg"')
```

### Addressable scores — clickable measures (MuseScore)

For MusicXML via MuseScore, gscore can make the score **addressable**: it reads MuseScore's measure
positions, crops to the music, and auto-creates a clickable region per measure.

```python
s("/gscore/scene/score","addressable",1)                       # enable
s("/gscore/scene/score","notation","musicxml","res://scores/example.musicxml")
# ...a moment later (engraving is async)...
s("/gscore/scene/score","measures")    # <- reply measures score 1 <u v w h time> 2 <...> ...
```

Each measure becomes region `m1…mN`; clicking one emits `/gscore/event/measure score m<n> <u> <v>`
(bind your own with `region m3 on click /my/addr`). Drive **cursor following** from your sequencer by
sending the current measure as the music plays — optionally with a beat fraction within the bar:

```python
s("/gscore/scene/score/cursor","show",1)
s("/gscore/scene/score/cursor","measure",3)       # jump cursor to bar 3
s("/gscore/scene/score/cursor","measure",3,0.5)   # halfway through bar 3
```

(v1 is MuseScore measure-level; note-level / Verovio / LilyPond addressing is future work.)

### Cache management

```python
s("/gscore/notation/cache","info")    # <- reply notation/cache info <count> <bytes> <dir>
s("/gscore/notation/cache","clear")
```

### Quick reference — source forms

| You have… | Command |
|---|---|
| Bundled PNG/SVG | `notation png "res://scores/x.png"` · `notation svg "res://scores/x.svg"` |
| A file written at run-time | `notation png "user://…"` / absolute path |
| Multi-page raster | `notation png "res://scores/p{page}.png"` + `nextPage` |
| A generated SVG string | `notation svg "<svg…>"` |
| Generated image bytes | OSC blob: `notation png <bytes>` |
| Symbolic music (file) | configure engraver, `notation musicxml "user://x.musicxml"` |
| Symbolic music (inline) | `notationData musicxml "<…>"` |

## 6. Driving it from a `.gscore` script

Instead of sending messages one by one, put them in a text file — one OSC-style command per line,
`#` for comments, quoted strings stay strings:

`res://my_score.gscore`
```text
# A tiny scene
/gscore/scene clear
/gscore/scene/score new notation
/gscore/scene/score notation png "res://scores/page1.png"
/gscore/scene/score scale 0.9
/gscore/scene/score/cursor show 1
/gscore/scene/score/cursor map 0 8 x 0.05 0.95
/gscore/transport play
```

Run it over OSC:

```python
s("/gscore/script/load", "res://my_score.gscore")
```

…or from GDScript (e.g. in your `Main` scene's `_ready`, after a short delay so the autoload has
booted):

```gdscript
await get_tree().create_timer(0.5).timeout
GScoreOSC.script_runner.run_file("res://my_score.gscore")
```

The bundled examples (`addons/gscore_osc/examples/ExampleMain.tscn` and `ExampleMain3D.tscn`) do
exactly this.

---

## 7. Connecting from Max / Pd / SuperCollider

gscore_osc speaks plain OSC over UDP. Send to **`127.0.0.1:7400`** and listen on **`7401`**.

- **Max/MSP:** `[udpsend 127.0.0.1 7400]` and `[udpreceive 7401]`. Build messages like
  `/gscore/scene/ball new circle`. Floats/ints are inferred from your atoms; wrap text in quotes
  for paths.
- **Pure Data:** `[netsend -u -b]` to `127.0.0.1 7400` with `[oscformat]`, and `[netreceive -u -b]`
  on `7401` with `[oscparse]`.
- **SuperCollider:**

  ```supercollider
  n = NetAddr("127.0.0.1", 7400);
  n.sendMsg("/gscore/scene/ball", "new", "circle");
  n.sendMsg("/gscore/scene/ball", "pos", 0.0, 0.5);
  // listen for events:
  OSCdef(\hit, { |m| m.postln }, "/synth/hit");
  ```

To make gscore_osc send replies/events to a **specific** host/port (e.g. a different machine):

```
/gscore/app/output 192.168.1.50 9001
```

---

## 8. Permissions & safety

Conservative defaults keep an open OSC port from doing anything dangerous:

- **Bind** only OSC-exposed nodes (add `OscExposable` or `set_meta("osc_expose", true)`).
- **Instantiate** only whitelisted scenes — `res://osc_spawnable/` is allowed by default; add more
  with `/gscore/assets/allowPrefix "res://my_prefab/"` or `/gscore/assets/allowScene "<path>"`.
- **Call methods / set properties** only on exposed members (`osc_methods`, `osc_properties` on
  `OscExposable`).
- **Free nodes** is off.

For frictionless local prototyping, set `gscore_osc/developer_mode = true` to relax all of this.

---

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| No `[GScoreOSC] ready` in Output | Enable the **gscore_osc** plugin (Project Settings → Plugins); make sure the `GScoreOSC` autoload exists. |
| No `/gscore/pong` | Check the client sends to `127.0.0.1:7400` and **listens on 7401**. A firewall prompt may block UDP — allow it. |
| Replies go nowhere on a remote box | Set the target: `/gscore/app/output <host> <port>`. |
| Objects don't appear (2D) | They're created at the viewport centre in normalized coords; make sure your main scene is running and nothing covers them. Try `s("/gscore/scene/title","new","text","hi")`. |
| Nothing visible (3D) | Confirm `space="3d"` (console says `space=3d`) and that a camera exists (the addon auto-creates one). Objects spawn near the origin inside a ±5-unit cube. |
| `permission_denied` on bind/call/instantiate | The node/member/scene isn't exposed/whitelisted. Expose it, whitelist it, or enable developer mode. |
| 3D changes ignored | `gscore_osc/space` is read once at startup — **restart** after changing it. |
| MusicXML/MEI fails with `load_failed` | Configure an external engraver in `gscore_osc/notation/external_renderer_*`, or pre-render to PNG/SVG. |
| SVG score not visible | Put the `.svg` under `res://` (it loads via Godot's import — confirm it shows a thumbnail in the FileSystem dock). The page renders at native size centred on the object, so **scale it down** (`/gscore/scene/score scale 0.3`) if it overflows. If the SVG shows no thumbnail, ThorVG can't rasterize it — export to PNG instead. Check the Output panel for a `load_failed` warning. |

---

## Next steps

- Full command list and reply/error reference: **[README.md](README.md)** (API reference section).
- Worked examples: `addons/gscore_osc/examples/` (2D and 3D) and `tools/osc_test.py`.
- Architecture/design notes: `docs/superpowers/specs/`.
