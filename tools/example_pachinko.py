#!/usr/bin/env python3
"""
Pachinko music box — a gravity-fed generative sequencer for gscore_osc (3D space).

Small balls rain through an offset grid of pegs and fall into five pentatonic bins
(C D E G A). Each landing emits

    /music/note  <bin>  <note>  <ball>  <ball-speed>

and this client recycles that ball back to the top the instant it lands (it listens
for its own /music/note messages), with a slow watchdog to re-drop any ball that gets
stuck in the pegs. The peg scattering is genuinely unpredictable, so the melody never
repeats. Point a synth at /music/note (note = pitch, ball-speed = velocity).

REQUIRES gscore_osc 0.8.x+ — this example leans on two features that make it possible:
  * sizable primitives: small balls/pegs via `new circle <r>` (a full-size ball can't
    thread a peg grid built from the fixed-size primitives).
  * `physics planar 1`: pins the balls to the z=0 plane so they can't drift out of the
    (thin) bins over time — without it the board goes silent after ~30 s.

USAGE
    1. Run the Godot project with gscore_osc set to 3D.
    2. python tools/example_pachinko.py        (or: py tools\\example_pachinko.py)
    3. Ctrl+C to stop.
"""
import math
import random
import socket
import struct
import threading
import time

HOST, SEND_PORT, RECV_PORT = "127.0.0.1", 7400, 7401
NOTES = ["C4", "D4", "E4", "G4", "A4"]
BINX = [-0.44, -0.22, 0.0, 0.22, 0.44]
NB = 6

# --- minimal OSC (self-contained so we can both send commands and listen) --
def _pad(b):
    return b + b"\x00" * ((4 - len(b) % 4) % 4)

def _ostr(s):
    return _pad(s.encode() + b"\x00")

def _encode(addr, *args):
    tt, payload = ",", b""
    for a in args:
        if isinstance(a, bool):
            tt += "T" if a else "F"
        elif isinstance(a, int):
            tt += "i"; payload += struct.pack(">i", a)
        elif isinstance(a, float):
            tt += "f"; payload += struct.pack(">f", a)
        else:
            tt += "s"; payload += _ostr(str(a))
    return _ostr(addr) + _ostr(tt) + payload

def _rstr(d, i):
    e = d.index(b"\x00", i); s = d[i:e].decode("utf-8", "replace"); i = e + 1
    return s, i + ((4 - i % 4) % 4)

def _decode(d):
    addr, i = _rstr(d, 0)
    if i >= len(d):
        return addr, []
    tt, i = _rstr(d, i); args = []
    for c in tt[1:]:
        if c == "i":
            args.append(struct.unpack_from(">i", d, i)[0]); i += 4
        elif c == "f":
            args.append(round(struct.unpack_from(">f", d, i)[0], 4)); i += 4
        elif c in "sS":
            v, i = _rstr(d, i); args.append(v)
        elif c == "T":
            args.append(True)
        elif c == "F":
            args.append(False)
        elif c in "htd":
            i += 8
    return addr, args

_send = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
_last_drop = {}

def s(addr, *args):
    _send.sendto(_encode(addr, *args), (HOST, SEND_PORT))
    time.sleep(0.03)

def drop(i):
    s(f"/gscore/scene/ball{i}/physics", "velocity", random.uniform(-0.5, 0.5), -0.4, 0.0)
    s(f"/gscore/scene/ball{i}", "pos", random.uniform(-0.14, 0.14), 1.0, 0.0)
    _last_drop[i] = time.time()

# --- build the board -------------------------------------------------------
def build():
    s("/gscore/scene", "reset")

    # offset peg grid — small ROUND pegs (sized visual + matching sphere collider)
    even = [-0.48, -0.32, -0.16, 0.0, 0.16, 0.32, 0.48]
    odd = [-0.4, -0.24, -0.08, 0.08, 0.24, 0.4]
    ys = [0.85, 0.71, 0.57, 0.43, 0.29]
    n = 0
    for r, y in enumerate(ys):
        for x in (even if r % 2 == 0 else odd):
            pid = f"peg{n}"; n += 1
            s(f"/gscore/scene/{pid}", "new", "circle", 0.022)
            s(f"/gscore/scene/{pid}/physics", "enable", "static")
            s(f"/gscore/scene/{pid}/collider", "sphere", 0.022)
            s(f"/gscore/scene/{pid}/physics", "friction", 0.0)
            s(f"/gscore/scene/{pid}/physics", "bounce", 0.7)
            s(f"/gscore/scene/{pid}", "pos", x, y, 0.0)

    # side walls + thick floor (thick so fast balls can't tunnel through)
    for wx, nm in ((-0.58, "wallL"), (0.58, "wallR")):
        s(f"/gscore/scene/{nm}", "new", "rect")
        s(f"/gscore/scene/{nm}/physics", "enable", "static")
        s(f"/gscore/scene/{nm}/physics", "friction", 0.0)
        s(f"/gscore/scene/{nm}/collider", "rect", 0.08, 1.5)
        s(f"/gscore/scene/{nm}", "pos", wx, 0.5, 0.0)
    s("/gscore/scene/floor", "new", "rect")
    s("/gscore/scene/floor/physics", "enable", "static")
    s("/gscore/scene/floor/physics", "friction", 0.0)
    s("/gscore/scene/floor/collider", "rect", 1.2, 0.6)
    s("/gscore/scene/floor", "pos", 0.0, -0.22, 0.0)

    # five pentatonic bins (sensor areas) — each plays a note as a ball enters
    for b, (x, note) in enumerate(zip(BINX, NOTES)):
        bid = f"bin{b}"
        s(f"/gscore/scene/{bid}", "new", "rect")
        s(f"/gscore/scene/{bid}/physics", "enable", "area")
        s(f"/gscore/scene/{bid}/collider", "rect", 0.2, 0.24)
        s(f"/gscore/scene/{bid}", "pos", x, 0.12, 0.0)
        s(f"/gscore/scene/{bid}/on", "areaEnter", "/music/note", "cooldown", 0.05)
        # payload:  <bin>  <note (literal)>  <ball id>  <ball speed>
        s(f"/gscore/scene/{bid}/payload", "areaEnter", "self", f"={note}", "other", "otherspeed")

    # small balls, pinned to the z=0 plane, dropped from the top
    for i in range(NB):
        bid = f"ball{i}"
        s(f"/gscore/scene/{bid}", "new", "circle", 0.02)
        s(f"/gscore/scene/{bid}/physics", "enable", "rigid")
        s(f"/gscore/scene/{bid}/collider", "sphere", 0.02)
        s(f"/gscore/scene/{bid}/physics", "planar", 1)
        s(f"/gscore/scene/{bid}/physics", "friction", 0.0)
        s(f"/gscore/scene/{bid}/physics", "bounce", 0.5)
        drop(i)

    s("/gscore/physics", "gravity", 0.0, -1.0, 0.0)
    s("/gscore/physics", "enable", 1)

# --- listen: recycle a ball the instant it lands, and print the note -------
def listen():
    r = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    r.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    r.bind((HOST, RECV_PORT)); r.settimeout(0.3)
    while True:
        try:
            data, _ = r.recvfrom(65535)
        except socket.timeout:
            continue
        addr, args = _decode(data)
        if addr == "/music/note" and len(args) >= 3:
            binid, note, ball = args[0], args[1], args[2]
            print(f"  ♪ {note}   (bin {binid})")
            if isinstance(ball, str) and ball.startswith("ball"):
                try:
                    drop(int(ball[4:]))
                except ValueError:
                    pass


if __name__ == "__main__":
    threading.Thread(target=listen, daemon=True).start()
    build()
    print("\nPachinko running — balls rain through the pegs into pentatonic bins.")
    print("/music/note streams below; Ctrl+C to stop.\n")
    try:
        while True:
            time.sleep(2.0)
            now = time.time()
            for i in range(NB):        # watchdog: re-drop any ball stuck in the pegs
                if now - _last_drop.get(i, 0) > 4.0:
                    drop(i)
    except KeyboardInterrupt:
        print("\nbye")
