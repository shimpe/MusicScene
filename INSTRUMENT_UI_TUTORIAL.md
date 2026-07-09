# Exposing a Software-Instrument Interface over OSC with MusicScene

This tutorial builds a **software-synth front panel** — knobs, a piano keyboard, an enable toggle, a
level meter — in a fresh Godot project, and makes it playable from **SuperCollider** or **Python**.

You will write **no GDScript at all.**

The panel is an ordinary Godot scene assembled from the
[**MusicControls**](https://github.com/shimpe/MusicControls) addon. MusicScene turns each control
into an addressable OSC object, and your sound engine decides — at runtime, over OSC — which Godot
signal becomes which musical message:

```
   Godot + MusicScene                                 SuperCollider or Python
   ───────────────────                                ───────────────────────
   /ms/scene/cutoff/signal value_changed  <──── setup ──── "forward that knob to /synth/param"
                                          
   knobs, keyboard,   ──── /synth/param cutoff 880 ────>  oscillators, filters,
   toggle, meter      <─── /ms/scene/meter call ... ────  envelopes, your DSP
   (the interface)                                        (the instrument)
```

Nothing in Godot knows what a filter is. Nothing in the engine knows what a knob looks like. The
mapping between them lives in six lines of your engine's start-up code, and you can change it without
reopening Godot.

> **Prefer a standalone project with no MusicScene dependency?** MusicControls ships its own
> tutorial that wires the same panel to OSC with about 250 lines of GDScript:
> [OSC_TUTORIAL.md](https://github.com/shimpe/MusicControls/blob/main/OSC_TUTORIAL.md). Section 11
> compares the two.

- [0. Prerequisites](#0-prerequisites)
- [1. Install both addons](#1-install-both-addons)
- [2. Build the panel](#2-build-the-panel)
- [3. Expose a control](#3-expose-a-control)
- [4. Boot and discover](#4-boot-and-discover)
- [5. Forward signals to musical addresses](#5-forward-signals-to-musical-addresses)
- [6. Drive the panel from the engine](#6-drive-the-panel-from-the-engine)
- [7. Where the messages go](#7-where-the-messages-go)
- [8. React in SuperCollider](#8-react-in-supercollider)
- [9. React in Python](#9-react-in-python)
- [10. Details that bite](#10-details-that-bite)
- [11. When to use which route](#11-when-to-use-which-route)
- [12. Beyond a control surface](#12-beyond-a-control-surface)
- [13. Troubleshooting](#13-troubleshooting)

---

## 0. Prerequisites

- **Godot 4.4+** (developed and verified on **4.7**).
- The **`addons/musicscene/`** folder from this repository.
- The **`addons/music_controls/`** folder from [MusicControls](https://github.com/shimpe/MusicControls).
- A sound engine: **SuperCollider 3.13+** (section 8) or **Python 3.9+** (section 9).

Two runnable engines ship with this repository and are used verbatim below:

| File | What it is |
|---|---|
| [`examples/supercollider/example_control_surface.scd`](examples/supercollider/example_control_surface.scd) | A real subtractive synth driven by the panel |
| [`examples/python/example_control_surface.py`](examples/python/example_control_surface.py) | A no-audio engine that prints state and drives the meter |

---

## 1. Install both addons

1. **New project.** Godot Project Manager → *New Project* → e.g. `MyInstrument`.
2. Copy both addon folders in, so you have `res://addons/musicscene/` and
   `res://addons/music_controls/`.
3. *Project → Project Settings → Plugins* → enable **MusicScene** and **MusicControls**.
   Enabling MusicScene installs the **`MusicSceneOSC`** autoload, which runs the OSC server.
4. Add one project setting: **`musicscene/space = "2d"`**. A control panel is a `Control` tree, not a
   3D world; in `3d` mode MusicScene would helpfully add a camera and a light you do not want.

Press **Play** once. The Output panel should say:

```
[MusicSceneOSC] OSC server listening on udp:7400, replies -> 127.0.0.1:7401
[MusicSceneOSC] ready (space=2d). Send /ms/ping to test.
```

---

## 2. Build the panel

Make a new scene with a `Control` root named `Panel`, save it as `res://panel.tscn`, and set it as
the main scene. Then add controls with the *Add Node* dialog — every MusicControls class is
registered with `class_name`, so they appear by name.

The scene used by the examples in this tutorial:

```
Panel                     Control
└── Column                VBoxContainer
    ├── Filter            ModulePanel        title="Filter", show_enable_toggle=true
    │   └── Knobs         HBoxContainer
    │       ├── Cutoff    SynthKnob          min=20  max=20000  default=1200
    │       │                                scale_mode=frequency  parameter_type=frequency  unit=Hz
    │       └── Reso      SynthKnob          min=0   max=100     default=15  parameter_type=percent
    ├── Wave              SynthSelector      options=[Sine, Saw, Square, Noise]  default_index=1
    ├── Keys              PianoKeyboard      start_note=48  octave_count=3
    └── Meter             LevelMeter         stereo=true
```

Run it. You have a working, good-looking panel that does absolutely nothing. No script is attached
to any of it, and none ever will be.

---

## 3. Expose a control

MusicScene will not touch a node unless you say so. The permission marker is a node: select a
control, add a child of type **`OscExposable`**, and fill in its inspector.

For `Cutoff`:

| Property | Value | Meaning |
|---|---|---|
| `osc_id` | `cutoff` | the name it answers to: `/ms/scene/cutoff …` |
| `osc_auto_bind` | `true` | bind it when the scene loads |
| `osc_properties` | `{"value": "float"}` | `prop` / `getProp` may read and write `value` |
| `osc_methods` | *(empty)* | `call` may invoke nothing |
| `osc_signals` | `["value_changed"]` | advisory — see the warning below |

Leave `osc_id` empty and the node's name is used, snake_cased (`Cutoff` → `cutoff`). The
`OscExposable` controls its **parent** by default, which is why it goes *under* the knob.

Do the same for the rest:

| Node | `osc_id` | `osc_properties` | `osc_methods` |
|---|---|---|---|
| `Filter` | `filter` | `{"enabled": "bool"}` | |
| `Cutoff` | `cutoff` | `{"value": "float"}` | |
| `Reso` | `reso` | `{"value": "float"}` | |
| `Wave` | `wave` | `{"selected": "int"}` | |
| `Keys` | `keys` | | `["highlight_note", "clear_highlights"]` |
| `Meter` | `meter` | | `["set_stereo_level", "clear_peak"]` |

`osc_properties` gates `prop` and `getProp`; `osc_methods` gates `call`. Ask for something you did not
list and you get an error rather than silence:

```
/ms/error permission_denied /ms/scene/filter/prop "Property not exposed: enabled"
```

> **The allow-lists gate writes and calls, not reads.** `osc_properties` gates `prop` (set) and
> `osc_methods` gates `call` — both enforced. But `getProp` reads *any* property of a bound node, and
> **`osc_signals` gates nothing at all**: listing a signal only makes `/ms/scene/<id> signals` report
> it, and any signal the node has can be forwarded, listed or not. Deciding to bind a node is the real
> security decision; after that, treat every readable property and every signal as reachable.

---

## 4. Boot and discover

Run the project. MusicScene waits until the main scene is in the tree, then binds everything it finds:

```
[MusicSceneOSC] auto-bound 6 exposed node(s)
[MusicSceneOSC] ready (space=2d). Send /ms/ping to test.
```

From your engine, ask what is there:

```
/ms/discover
```

```
/ms/reply discover panel   /root/Panel              Control  Panel
/ms/reply discover cutoff  /root/Panel/.../Cutoff   Control  Cutoff
/ms/reply discover keys    /root/Panel/.../Keys     Control  Keys
...
```

`/ms/discover` lists *every* node in the scene, not just the exposed ones — including the
`OscExposable` markers themselves, which show up with generated names like `@node@2`. Filter with
`/ms/discover type SynthKnob` if you only want the controls. To ask a single object what it offers:

```
/ms/scene/cutoff properties      -> /ms/reply properties cutoff value
/ms/scene/meter methods          -> /ms/reply methods meter set_stereo_level clear_peak
```

**Auto-binding only sees the main scene at start-up.** A control you instantiate later is not bound.
Reach it by path instead:

```
/ms/bind late "/root/Panel/Column/Late"
```

---

## 5. Forward signals to musical addresses

This is the whole trick. One message per control, sent once when your engine starts:

```
/ms/scene/<id>/signal <godot_signal> <osc_address> [payload <token> ...]
```

From then on, whenever that Godot signal fires, MusicScene emits `<osc_address>` with the payload you
described. The payload tokens:

| Token | Becomes |
|---|---|
| `self` | the control's `osc_id` |
| `signal` | the signal's name |
| `value` | the signal's **first** argument |
| `arg0`, `arg1`, … | the Nth argument |
| `args` | all arguments, spliced in |
| anything else | itself, as a literal string |

With no `payload` clause you get `<osc_id> <signal_name> <args...>`.

The six lines that turn the panel into an instrument:

```supercollider
n = NetAddr("127.0.0.1", 7400);
n.sendMsg("/ms/scene/cutoff/signal", "value_changed", "/synth/param", "payload", "self", "value");
n.sendMsg("/ms/scene/reso/signal",   "value_changed", "/synth/param", "payload", "self", "value");
n.sendMsg("/ms/scene/wave/signal",   "value_changed", "/synth/wave",  "payload", "value");
n.sendMsg("/ms/scene/filter/signal", "enable_toggled", "/synth/filter", "payload", "value");
n.sendMsg("/ms/scene/keys/signal",   "note_pressed",  "/synth/note/on",  "payload", "arg0", "arg1");
n.sendMsg("/ms/scene/keys/signal",   "note_released", "/synth/note/off", "payload", "arg0");
```

Turning the Cutoff knob now sends `/synth/param cutoff 880.0`. Both knobs share one address and are
told apart by `self`, so a single handler in your engine serves every knob you ever add — and because
`self` is the `osc_id`, adding a knob means adding one line here, not editing Godot.

Pressing a key sends `/synth/note/on 60 0.78` (velocity comes from where on the key you clicked).

---

## 6. Drive the panel from the engine

Two verbs point the other way.

**`call` invokes a method** listed in `osc_methods`. Arguments are passed through untouched:

```
/ms/scene/meter call set_stereo_level 0.5 0.42     # two floats, not a Vector2
/ms/scene/keys  call highlight_note 60 1           # the int 1 lands in a `bool` parameter
/ms/scene/keys  call clear_highlights
```

That is how the meter moves and how the keyboard lights up. Note what this buys you: the keys show
what the engine is *sounding*, not what you clicked. Trigger a note from a sequencer and the panel
lights up too; kill the engine and the keys stay dark.

**`prop` writes a property** listed in `osc_properties`, and `getProp` reads one:

```
/ms/scene/cutoff prop value 3000       # the knob turns
/ms/scene/cutoff getProp value         # -> /ms/reply getProp cutoff value 3000.0
/ms/scene/filter prop enabled 0        # the module dims
```

Which makes preset recall trivial: write the values into the UI, and the UI's own signals tell your
engine what happened. You do not need a separate "apply preset" path.

---

## 7. Where the messages go

MusicScene listens on **UDP 7400** and sends replies and events to the **last sender's IP** on the
port(s) from `musicscene/network/send_port` — **7401** by default.

That is fine for Python: bind 7401 and you are done, no configuration at all.

It is *not* fine for SuperCollider, because `sclang` listens on **57120** and cannot easily be told to
listen elsewhere. Redirect MusicScene instead, at engine start-up:

```supercollider
NetAddr("127.0.0.1", 7400).sendMsg("/ms/app/output", "127.0.0.1", NetAddr.langPort);
```

Everything MusicScene emits — your `/synth/...` events, `/ms/reply`, `/ms/error` — now arrives on
sclang's own port. (The alternative, `thisProcess.openUDPPort(7401)` plus `OSCdef(..., recvPort: 7401)`,
also works if you would rather not move MusicScene's output.)

**Always listen for `/ms/error`.** MusicScene answers mistakes instead of failing quietly, and a typo
in an `osc_id` is otherwise invisible:

```supercollider
OSCdef(\msError, { |msg| "MusicScene error: %".format(msg[1..]).warn }, '/ms/error');
```

---

## 8. React in SuperCollider

Full, runnable version:
[`examples/supercollider/example_control_surface.scd`](examples/supercollider/example_control_surface.scd).
Run the Godot project, then evaluate that file.

Every knob-controlled quantity is a `SynthDef` argument, which is what lets a knob move a **held** note
rather than only the next one:

```supercollider
SynthDef(\surfaceVoice, { |out = 0, note = 60, vel = 0.8, gate = 1,
	wave = 1, cutoff = 1200, reso = 15, filterOn = 1|
	var freq = note.midicps;
	var sig = Select.ar(wave.clip(0, 3), [
		SinOsc.ar(freq), Saw.ar(freq), Pulse.ar(freq, 0.5), WhiteNoise.ar
	]);
	var rq = (1 - (reso / 100)).clip(0.05, 1.0);
	var env = EnvGen.kr(Env.adsr(0.01, 0.15, 0.7, 0.3), gate, doneAction: 2);
	sig = Select.ar(filterOn.clip(0, 1), [sig, RLPF.ar(sig, cutoff.clip(20, 20000), rq)]);
	Out.ar(out, Pan2.ar(sig * vel * env * 0.2, 0));
}).add;
```

Because the `osc_id`s were chosen to match those argument names, one handler serves every knob:

```supercollider
// The osc_id travels as the first argument, so one handler serves every knob.
OSCdef(\param, { |msg|
	var id = msg[1].asSymbol, value = msg[2];
	~params[id] = value;
	~voices.do { |voice| voice.set(id, value) };
	"param % = %".format(id, value.round(0.001)).postln;
}, '/synth/param');
```

An OSC string arrives in sclang as a **Symbol**, so `msg[1]` is already `\cutoff` and can be handed
straight to `voice.set`. Notes create and release voices, and light the keys on the way:

```supercollider
OSCdef(\noteOn, { |msg|
	var note = msg[1].asInteger, vel = msg[2];
	~voices[note] !? { |old| old.set(\gate, 0) };
	~voices[note] = Synth(\surfaceVoice,
		[\note, note, \vel, vel] ++ ~params.getPairs, ~meter, \addBefore);
	ms.sendMsg("/ms/scene/keys", "call", "highlight_note", note, 1);   // light the key
	"note on  %".format(note).postln;
}, '/synth/note/on');
```

`~params.getPairs` splats the whole dictionary into the `Synth` argument list — `[\cutoff, 1200,
\reso, 15, …]` — because the ids and the `SynthDef` argument names are the same words.

The meter is a synth at the tail of the node order, reporting amplitude 30 times a second:

```supercollider
SynthDef(\surfaceMeter, { |rate = 30|
	var sig = In.ar(0, 2);
	SendReply.kr(Impulse.kr(rate), '/level', [Amplitude.kr(sig[0]), Amplitude.kr(sig[1])]);
}).add;

// `call` invokes a method listed in the control's OscExposable.osc_methods.
OSCdef(\level, { |msg|
	ms.sendMsg("/ms/scene/meter", "call", "set_stereo_level", msg[3], msg[4]);
}, '/level');
```

`SendReply` prepends the node id and a reply id, which is why the amplitudes are `msg[3]` and `msg[4]`.

---

## 9. React in Python

Full, runnable version:
[`examples/python/example_control_surface.py`](examples/python/example_control_surface.py). Standard
library only, no audio — it prints the patch state and drives the meter and key lights so you can see
the loop close. Replace the handler bodies with `sounddevice`, `pyo`, or a MIDI port.

```
python examples/python/example_control_surface.py
```

It needs no `/ms/app/output`: it simply binds 7401, where MusicScene already sends.

The setup and the dispatch, in full:

```python
def setup() -> None:
    """Teach MusicScene which control signal becomes which musical message.

    Payload tokens: self = the control's osc_id, value = the first signal argument,
    argN = the Nth. Without a payload spec you get <osc_id> <signal_name> <args...>.
    """
    to_ms("/ms/scene/cutoff/signal", "value_changed", "/synth/param", "payload", "self", "value")
    to_ms("/ms/scene/reso/signal", "value_changed", "/synth/param", "payload", "self", "value")
    to_ms("/ms/scene/wave/signal", "value_changed", "/synth/wave", "payload", "value")
    to_ms("/ms/scene/filter/signal", "enable_toggled", "/synth/filter", "payload", "value")
    to_ms("/ms/scene/keys/signal", "note_pressed", "/synth/note/on", "payload", "arg0", "arg1")
    to_ms("/ms/scene/keys/signal", "note_released", "/synth/note/off", "payload", "arg0")
```

```python
def handle(addr: str, args: list) -> None:
    global wave, filter_on, amp
    if addr == "/synth/param" and len(args) >= 2:
        params[str(args[0])] = float(args[1])
        print(f"param {args[0]} = {args[1]:.4g}")
    elif addr == "/synth/wave" and args:
        wave = int(args[0])
        print(f"wave = {wave}")
    elif addr == "/synth/filter" and args:
        # ModulePanel.enable_toggled carries a real OSC boolean (T/F type tag).
        filter_on = bool(args[0])
        print(f"filter {'on' if filter_on else 'bypassed'}")
    elif addr == "/synth/note/on" and len(args) >= 2:
        held[int(args[0])] = float(args[1])
        print(f"note on  {args[0]} vel {args[1]:.2f}  cutoff={params['cutoff']:.0f}")
        to_ms("/ms/scene/keys", "call", "highlight_note", int(args[0]), 1)
    elif addr == "/synth/note/off" and args:
        held.pop(int(args[0]), None)
        print(f"note off {args[0]}")
        to_ms("/ms/scene/keys", "call", "highlight_note", int(args[0]), 0)
    elif addr == "/ms/error":
        print(f"!! MusicScene error: {args}")
    elif addr != "/ms/reply":
        print(f"?? {addr} {args}")
```

Writing a preset straight into the UI:

```python
def preset(cutoff: float, reso: float) -> None:
    """Write straight into the UI. Each knob moves and echoes one /synth/param back."""
    to_ms("/ms/scene/cutoff", "prop", "value", float(cutoff))
    to_ms("/ms/scene/reso", "prop", "value", float(reso))
```

If you prefer `python-osc` (`pip install python-osc`), a `Dispatcher` maps addresses to handlers and
unpacks the arguments for you; the OSC contract is unchanged.

---

## 10. Details that bite

**Writing a property echoes back.** `/ms/scene/cutoff prop value 3000` moves the knob, the knob emits
`value_changed`, and your forwarding rule sends `/synth/param cutoff 3000` straight back at you. This
is a one-shot echo, not a loop: `SynthParameterBinding` only emits when the value actually changes, so
your engine's answer (setting the same value again) dies immediately. It is still one wasted round
trip — if that matters, skip the echo by writing to your own state instead of the UI.

**Count changes, not events.** Every MusicControls control emits its signal once per *actual* change,
whether the change came from a click or from `prop` — writing a value it already holds emits nothing.
Rely on that for idempotence, not for counting: a dropped or duplicated datagram is still possible over
UDP, so a receiver that increments a counter per event will drift where one that stores a value will not.

**Booleans arrive as booleans.** `enable_toggled(bool)` forwards a real OSC `T`/`F` type tag. Both
SuperCollider and `python-osc` decode it correctly, and then it bites: `true > 0` and `true.clip(0, 1)`
both raise *"Message not understood"* in sclang, and `Select.ar` needs a number. Convert on arrival:

```supercollider
var on = if (msg[1] == true or: { msg[1] == 1 }) { 1 } { 0 };
```

**OSC floats are 32-bit.** `0.8` arrives as `0.80000001192093`. Compare with a tolerance; never test an
incoming float for equality.

**`prop` coerces multi-value arguments, `call` does not.** Two numbers passed to `prop` become a
`Vector2`, three a `Vector3`, four a `Color` — which is what you want for `position` and wrong for
anything else. `call` passes its arguments through untouched, so `call set_stereo_level 0.5 0.42`
really does arrive as two floats. The flip side: a method that *wants* a `Vector2` cannot be reached
by `call` (`call set_position 5 7` fails with *"Cannot convert argument 1 from int to Vector2"*). Set
the property instead — `prop position 5 7`.

**A payload token that collides with a keyword is a keyword.** `payload self value` is fine; a control
whose `osc_id` is literally `value` would confuse the token parser. Do not name one that.

**UDP drops packets.** Rare on `127.0.0.1`, real across a network. Keep note-off idempotent (the
SuperCollider example uses `!?` so a stray note-off for a silent note does nothing), and re-send your
`signal` setup if the engine restarts.

---

## 11. When to use which route

MusicControls can speak OSC on its own — see its
[OSC_TUTORIAL.md](https://github.com/shimpe/MusicControls/blob/main/OSC_TUTORIAL.md), which writes a
small codec and a sender in GDScript.

| | MusicControls alone | This tutorial |
|---|---|---|
| Godot addons | `music_controls` | `music_controls` + `musicscene` |
| GDScript you write | ~250 lines | none |
| Who decides the OSC mapping | the Godot code | the engine, at runtime |
| Change the mapping | edit + restart Godot | send a different `signal` message |
| Ports | you choose | `7400` in, `7401` out (redirectable) |
| Also get | — | notation, physics, scene graph, script runner |

Use the standalone route when the panel **is** the app and you want no extra dependency. Use this one
when the panel is part of a bigger score world, or when you want to re-map controls live — a
performance-time luxury the compiled route cannot offer.

---

## 12. Beyond a control surface

The panel is now just one more set of OSC objects in a MusicScene world, which means the rest of the
API is already available to it.

**Put a score next to the knobs.** Anything MusicScene can create, it can create alongside your
`Control` tree — though a `Control` main scene is 2D, so keep `musicscene/space = "2d"`:

```
/ms/scene/score new notation
/ms/scene/score notation abc "X:1\nK:C\nCDEF|"
/ms/scene/score/cursor show 1
```

Your engine now moves a playback cursor with the same `NetAddr` it uses to light the keys. If you
write your music in Panola, the **MSScore** quark drives that half for you — see
[TUTORIAL.md](TUTORIAL.md) and [README.md](README.md#music-notation).

**Bake the setup into the project.** Section 5's six `signal` messages have to be sent by *someone*. If
you would rather the panel work the moment Godot starts, put them in a `.ms` script (one OSC command
per line, `#` for comments) and have MusicScene run it:

```
# res://wiring.ms
/ms/scene/cutoff/signal value_changed /synth/param payload self value
/ms/scene/keys/signal note_pressed /synth/note/on payload arg0 arg1
```

```
/ms/script/load "res://wiring.ms"
```

**Let the panel react to the world.** Because the controls are ordinary MusicScene objects, a physics
collision or a sensor zone elsewhere in the scene can drive them — a falling ball landing in a zone can
emit an event that your engine turns into `/ms/scene/cutoff prop value …`. See
[README.md](README.md#physics--collision-events).

---

## 13. Troubleshooting

**`auto-bound 0 exposed node(s)`.** The `OscExposable` nodes are not in the **main scene**, or
`osc_auto_bind` is off. Auto-binding scans the running scene two frames after start-up; nodes added
later need an explicit `/ms/bind`.

**`permission_denied … Property not exposed: X`.** Add `X` to that control's `osc_properties`. Same for
`call` and `osc_methods`.

**`unknown_object`.** The `osc_id` does not match. Send `/ms/discover` and read the list; remember an
empty `osc_id` becomes the snake_cased node name.

**The knobs move but the engine hears nothing.** MusicScene is sending to 7401 and your engine is
listening somewhere else. Either bind 7401, or send `/ms/app/output 127.0.0.1 <your port>`.

**Nothing at all, and no error.** Check the Godot Output panel for the `listening on udp:7400` line. If
a previous run is still alive it owns the port — leftover Godot processes do not always release UDP
binds when the window closes.

**A signal you did not list still fires.** Expected: `osc_signals` is advisory. See section 3.

---

## Where to go next

- **[TUTORIAL.md](TUTORIAL.md)** — MusicScene from scratch, in 2D and 3D.
- **[ADVANCED.md](ADVANCED.md)** — the mechanics behind MusicScene's trickier features.
- **[README.md](README.md#api-reference)** — the full OSC API.
- **[MusicControls](https://github.com/shimpe/MusicControls)** — the control library, its reference
  docs, and the standalone OSC tutorial.
