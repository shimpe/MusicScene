#!/usr/bin/env python3
"""
Engine stand-in for a MusicControls panel exposed through MusicScene (INSTRUMENT_UI_TUTORIAL.md).

The Godot project contains no glue code: the panel is a plain scene of MusicControls nodes, each
carrying an OscExposable child. This script tells MusicScene, over OSC, which Godot signal should
become which musical address -- then reacts to them. It makes no audio; it prints the patch state
and drives the panel's meter and key lights so the loop is visible.

    python --> 127.0.0.1:7400   /ms/... setup, and /ms/scene/<id> call|prop to drive the UI
    Godot  --> 127.0.0.1:7401   /synth/... forwarded control signals, and /ms/reply, /ms/error

Unlike the SuperCollider example this needs no /ms/app/output: it simply listens on 7401, where
MusicScene sends by default.

USAGE
    1. Run the Godot project (panel.tscn as main scene, both addons enabled).
    2. python examples/python/example_control_surface.py
    3. Play the on-screen keyboard and turn the knobs.

Only the standard library is used. Requires the MusicControls addon alongside MusicScene:
https://github.com/shimpe/MusicControls
"""
import socket
import struct
import time

MS = ("127.0.0.1", 7400)          # MusicScene listens here
LISTEN = 7401                     # MusicScene sends replies and events here
LEVEL_HZ = 30.0

# --- OSC ---------------------------------------------------------------------


def _pad(b: bytes) -> bytes:
    return b + b"\x00" * ((4 - len(b) % 4) % 4)


def _ostr(s: str) -> bytes:
    return _pad(s.encode() + b"\x00")


def encode(addr, *args) -> bytes:
    tags, payload = ",", b""
    for a in args:
        if isinstance(a, bool):
            tags += "T" if a else "F"
        elif isinstance(a, int):
            tags += "i"
            payload += struct.pack(">i", a)
        elif isinstance(a, float):
            tags += "f"
            payload += struct.pack(">f", a)
        else:
            tags += "s"
            payload += _ostr(str(a))
    return _ostr(addr) + _ostr(tags) + payload


def _read_str(d: bytes, i: int):
    end = d.index(b"\x00", i)
    s = d[i:end].decode("utf-8", "replace")
    i = end + 1
    return s, i + ((4 - i % 4) % 4)


def decode(d: bytes):
    if d[:8] == b"#bundle\x00":
        out, i = [], 16
        while i + 4 <= len(d):
            n = struct.unpack_from(">i", d, i)[0]
            i += 4
            out += decode(d[i:i + n])
            i += n
        return out
    addr, i = _read_str(d, 0)
    if i >= len(d):
        return [(addr, [])]
    tags, i = _read_str(d, i)
    args = []
    for c in tags[1:]:
        if c == "i":
            args.append(struct.unpack_from(">i", d, i)[0]); i += 4
        elif c == "f":
            args.append(struct.unpack_from(">f", d, i)[0]); i += 4
        elif c in "sS":
            v, i = _read_str(d, i); args.append(v)
        elif c == "T":
            args.append(True)
        elif c == "F":
            args.append(False)
        elif c in "hd":
            i += 8
        else:
            break
    return [(addr, args)]


rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
rx.bind(("127.0.0.1", LISTEN))
rx.settimeout(1.0 / LEVEL_HZ)
tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)


def to_ms(addr, *args) -> None:
    tx.sendto(encode(addr, *args), MS)


# --- engine state ------------------------------------------------------------

params = {"cutoff": 1200.0, "reso": 15.0}
wave = 1
filter_on = True
held: dict[int, float] = {}
amp = 0.0


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


def preset(cutoff: float, reso: float) -> None:
    """Write straight into the UI. Each knob moves and echoes one /synth/param back."""
    to_ms("/ms/scene/cutoff", "prop", "value", float(cutoff))
    to_ms("/ms/scene/reso", "prop", "value", float(reso))


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


def main() -> None:
    global amp
    print(f"control surface engine: -> {MS[0]}:{MS[1]}, listening on {LISTEN}")
    setup()
    last = next_level = time.monotonic()
    while True:
        try:
            data, _ = rx.recvfrom(65535)
            for addr, args in decode(data):
                handle(addr, args)
        except socket.timeout:
            pass

        now = time.monotonic()
        dt, last = now - last, now
        target = 0.85 if held else 0.0     # crude amp envelope, purely so the meter moves
        amp += (target - amp) * min(1.0, dt * (12.0 if target else 3.0))
        if now >= next_level:
            next_level = now + 1.0 / LEVEL_HZ
            wobble = 0.9 + 0.1 * (now * 7.0 % 1.0)
            to_ms("/ms/scene/meter", "call", "set_stereo_level", amp, amp * wobble)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nbye")
