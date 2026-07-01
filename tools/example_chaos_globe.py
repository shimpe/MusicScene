#!/usr/bin/env python3
"""
Chaotic "snow-globe" — a physics-driven generative sequencer for gscore_osc (3D space).

Several balls are sealed inside a box. This script slowly ROTATES the direction of
gravity, so the balls tumble and cascade endlessly, never settling into a pattern.
Five sensor zones arranged in a ring are pentatonic "pads" (C D E G A): whenever a
ball passes through one, gscore emits

    /music/note  <zone>  <note>  <ball-speed>

...an ever-evolving, never-repeating melody driven by real physics. Point a synth at
/music/note (note name = pitch, ball-speed = velocity/dynamics).

WHY ROTATING GRAVITY?
A game physics engine bleeds energy, so any self-contained mechanism (a pendulum, a
free bounce) winds down to something regular within seconds. Continuously turning the
gravity vector is an inexhaustible energy source, so the motion stays chaotic forever.
A little linear damping keeps the balls slow enough that they never escape the box.

USAGE
    1. Run the Godot project with gscore_osc set to 3D (gscore_osc/space = "3d").
    2. python tools/example_chaos_globe.py        (or: py tools\\example_chaos_globe.py)
    3. Watch the "<- /music/note ..." lines stream by; Ctrl+C to stop.
"""
import math
import time
from gosc import s   # tiny OSC client next to this file (also prints incoming messages)

NOTES = ["C4", "D4", "E4", "G4", "A4"]


def build():
    s("/gscore/scene", "reset")

    # sealed box: four THICK static walls (thick so fast balls can't tunnel through them)
    walls = [("top", 0.0, 0.66, 1.5, 0.3), ("bot", 0.0, -0.66, 1.5, 0.3),
             ("lft", -0.66, 0.0, 0.3, 1.5), ("rgt", 0.66, 0.0, 0.3, 1.5)]
    for name, x, y, w, h in walls:
        s(f"/gscore/scene/{name}", "new", "rect")
        s(f"/gscore/scene/{name}/physics", "enable", "static")
        s(f"/gscore/scene/{name}/physics", "friction", 0.0)
        s(f"/gscore/scene/{name}/collider", "rect", w, h)
        s(f"/gscore/scene/{name}", "pos", x, y, 0.0)

    # five pentatonic sensor zones arranged in a ring
    for k, note in enumerate(NOTES):
        a = math.radians(90 + k * 72)
        zx, zy = 0.42 * math.cos(a), 0.42 * math.sin(a)
        zid = f"zone{k}"
        s(f"/gscore/scene/{zid}", "new", "rect")
        s(f"/gscore/scene/{zid}/physics", "enable", "area")
        s(f"/gscore/scene/{zid}/collider", "rect", 0.26, 0.26)
        s(f"/gscore/scene/{zid}", "pos", zx, zy, 0.0)
        # any ball entering emits a note; small cooldown so a slow pass doesn't retrigger
        s(f"/gscore/scene/{zid}/on", "areaEnter", "/music/note", "cooldown", 0.08)
        s(f"/gscore/scene/{zid}/payload", "areaEnter", "self", f"={note}", "otherspeed")

    # a handful of balls. Light LINEAR DAMPING caps their speed so they can never tunnel
    # out of the box, while gravity still tosses them around.
    for i in range(6):
        b = f"ball{i}"
        s(f"/gscore/scene/{b}", "new", "circle")
        s(f"/gscore/scene/{b}/physics", "enable", "rigid")
        s(f"/gscore/scene/{b}/physics", "friction", 0.0)
        s(f"/gscore/scene/{b}/physics", "bounce", 0.35)
        s(f"/gscore/scene/{b}/physics", "damping", 1.4, 0.0)   # linear, angular
        s(f"/gscore/scene/{b}", "pos", -0.35 + 0.14 * i, 0.0, 0.0)

    s("/gscore/physics", "debug", 1)          # show the box + zones (send "debug 0" to hide)
    s("/gscore/physics", "gravity", 0.0, -1.0, 0.0)
    s("/gscore/physics", "enable", 1)


if __name__ == "__main__":
    build()
    print("\nSnow-globe running — rotating gravity keeps the balls tumbling forever.")
    print("/music/note <zone> <note> <speed> streams below. Ctrl+C to stop.\n")
    theta = 0.0
    try:
        while True:
            theta += 0.8                       # advance the gravity direction (the "shake")
            s("/gscore/physics", "gravity", math.cos(theta), math.sin(theta), 0.0)
            time.sleep(0.8)
    except KeyboardInterrupt:
        print("\nbye")
