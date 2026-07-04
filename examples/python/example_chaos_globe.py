#!/usr/bin/env python3
"""
Chaotic "snow-globe" — a physics-driven generative sequencer for MusicScene (3D space).

Several balls are sealed inside a box. This script slowly ROTATES the direction of
gravity, so the balls tumble and cascade endlessly, never settling into a pattern.
Five sensor zones arranged in a ring are pentatonic "pads" (C D E G A): whenever a
ball passes through one, MusicScene emits

    /music/note  <zone>  <note>  <ball-speed>

...an ever-evolving, never-repeating melody driven by real physics. Point a synth at
/music/note (note name = pitch, ball-speed = velocity/dynamics).

WHY ROTATING GRAVITY?
A game physics engine bleeds energy, so any self-contained mechanism (a pendulum, a
free bounce) winds down to something regular within seconds. Continuously turning the
gravity vector is an inexhaustible energy source, so the motion stays chaotic forever.
A little linear damping keeps the balls slow enough that they never escape the box.

USAGE
    1. Run the Godot project with MusicScene set to 3D (ms/space = "3d").
    2. python examples/python/example_chaos_globe.py   (or: py examples\\python\\example_chaos_globe.py)
    3. Watch the "<- /music/note ..." lines stream by; Ctrl+C to stop.
"""
import math
import os
import sys
import time

# gosc.py lives in the repo's tools/ dir; make it importable from here.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from gosc import s   # tiny OSC client in tools/ (importing it also prints incoming replies)

NOTES = ["C4", "D4", "E4", "G4", "A4"]


def build():
    s("/ms/scene", "reset")

    # sealed box: four THICK static walls (thick so fast balls can't tunnel through them)
    walls = [("top", 0.0, 0.66, 1.5, 0.3), ("bot", 0.0, -0.66, 1.5, 0.3),
             ("lft", -0.66, 0.0, 0.3, 1.5), ("rgt", 0.66, 0.0, 0.3, 1.5)]
    for name, x, y, w, h in walls:
        s(f"/ms/scene/{name}", "new", "rect")
        s(f"/ms/scene/{name}/physics", "enable", "static")
        s(f"/ms/scene/{name}/physics", "friction", 0.0)
        s(f"/ms/scene/{name}/collider", "rect", w, h)
        s(f"/ms/scene/{name}", "pos", x, y, 0.0)

    # five pentatonic sensor zones arranged in a ring
    for k, note in enumerate(NOTES):
        a = math.radians(90 + k * 72)
        zx, zy = 0.42 * math.cos(a), 0.42 * math.sin(a)
        zid = f"zone{k}"
        s(f"/ms/scene/{zid}", "new", "rect")
        s(f"/ms/scene/{zid}/physics", "enable", "area")
        s(f"/ms/scene/{zid}/collider", "rect", 0.26, 0.26)
        s(f"/ms/scene/{zid}", "pos", zx, zy, 0.0)
        # any ball entering emits a note; small cooldown so a slow pass doesn't retrigger
        s(f"/ms/scene/{zid}/on", "areaEnter", "/music/note", "cooldown", 0.08)
        s(f"/ms/scene/{zid}/payload", "areaEnter", "self", f"={note}", "otherspeed")

    # a handful of balls. Light LINEAR DAMPING caps their speed so they can never tunnel
    # out of the box, while gravity still tosses them around.
    for i in range(6):
        b = f"ball{i}"
        s(f"/ms/scene/{b}", "new", "circle")
        s(f"/ms/scene/{b}/physics", "enable", "rigid")
        s(f"/ms/scene/{b}/physics", "planar", 1)           # pin to the z=0 plane (no out-of-plane drift)
        s(f"/ms/scene/{b}/physics", "friction", 0.0)
        s(f"/ms/scene/{b}/physics", "bounce", 0.35)
        s(f"/ms/scene/{b}/physics", "damping", 1.4, 0.0)   # linear, angular
        s(f"/ms/scene/{b}", "pos", -0.35 + 0.14 * i, 0.0, 0.0)

    s("/ms/physics", "debug", 1)          # show the box + zones (send "debug 0" to hide)
    s("/ms/physics", "gravity", 0.0, -1.0, 0.0)
    s("/ms/physics", "enable", 1)


if __name__ == "__main__":
    build()
    print("\nSnow-globe running — rotating gravity keeps the balls tumbling forever.")
    print("/music/note <zone> <note> <speed> streams below. Ctrl+C to stop.\n")
    theta = 0.0
    try:
        while True:
            theta += 0.8                       # advance the gravity direction (the "shake")
            s("/ms/physics", "gravity", math.cos(theta), math.sin(theta), 0.0)
            time.sleep(0.8)
    except KeyboardInterrupt:
        print("\nbye")
