#!/usr/bin/env python3
"""
Double-pendulum JOINTS demo for gscore_osc (3D space).

Shows how to build a linkage with hinge joints and drive events off it: a static
pivot and two rigid arms are connected by two hinges, so a double pendulum swings
under gravity. Five pentatonic sensor zones ("pads", C D E G A) sit across the
bottom of the swing; when the pendulum tip crosses one, gscore emits

    /music/note  <pad-id>  <note>  <tip-speed>

Point a synth at /music/note (note = pitch, tip-speed = velocity).

NOTE ON MOTION
This is a demo of *joints + zones*, not a perpetual generative engine. A game
physics solver bleeds energy, so the pendulum swings energetically for a while and
then settles — re-run this file to wind it up again. For motion that stays chaotic
forever (an inexhaustible energy source), see example_chaos_globe.py.

USAGE
    1. Run the Godot project with gscore_osc set to 3D (gscore_osc/space = "3d").
    2. python examples/python/example_pendulum_joints.py   (or: py examples\\python\\example_pendulum_joints.py)
    3. Watch the "<- /music/note ..." lines stream by; Ctrl+C to stop.
"""
import os
import sys
import time

# gosc.py lives in the repo's tools/ dir; make it importable from here.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from gosc import s   # tiny OSC client in tools/ (importing it also prints incoming replies)


def build():
    s("/gscore/scene", "reset")

    # A static pivot + two rigid arms + two hinges (both rotating about Z, so the
    # whole linkage swings in the screen plane). Colliders are created automatically
    # when physics is enabled, so the tip can trigger the zones out of the box.
    s("/gscore/scene/post", "new", "circle")
    s("/gscore/scene/post/physics", "enable", "static")
    s("/gscore/scene/post", "pos", 0.0, 0.7, 0.0)
    s("/gscore/scene/post/collider", "disabled", 1)   # anchor only: don't bounce the tip off it

    s("/gscore/scene/arm1", "new", "circle")
    s("/gscore/scene/arm1/physics", "enable", "rigid")
    s("/gscore/scene/arm1", "pos", 0.22, 0.7, 0.0)

    s("/gscore/scene/arm2", "new", "circle")
    s("/gscore/scene/arm2/physics", "enable", "rigid")
    s("/gscore/scene/arm2", "pos", 0.44, 0.7, 0.0)     # both arms out to one side = lots of energy

    s("/gscore/joint/h1", "new", "hinge", "post", "arm1")
    s("/gscore/joint/h1", "axis", 0, 0, 1)
    s("/gscore/joint/h2", "new", "hinge", "arm1", "arm2")
    s("/gscore/joint/h2", "axis", 0, 0, 1)

    # five pentatonic pads across the swing; left -> right = low -> high. Each pad
    # is a sensor zone that fires only for the pendulum tip (arm2); the tip's speed
    # rides along as note velocity.
    pads = [
        ("padA", -0.34, 0.50, "C4"),
        ("padB", -0.18, 0.36, "D4"),
        ("padC",  0.00, 0.30, "E4"),
        ("padD",  0.18, 0.36, "G4"),
        ("padE",  0.34, 0.50, "A4"),
    ]
    for pid, x, y, note in pads:
        s(f"/gscore/scene/{pid}", "new", "rect")
        s(f"/gscore/scene/{pid}/physics", "enable", "area")
        s(f"/gscore/scene/{pid}/collider", "rect", 0.16, 0.14)
        s(f"/gscore/scene/{pid}", "pos", x, y, 0.0)
        # only the tip triggers; a small cooldown avoids double-hits on a slow pass
        s(f"/gscore/scene/{pid}/on", "areaEnter", "/music/note", "other", "arm2", "cooldown", 0.08)
        # payload:  <pad id>  <note (literal)>  <tip speed>
        s(f"/gscore/scene/{pid}/payload", "areaEnter", "self", f"={note}", "otherspeed")

    s("/gscore/physics", "debug", 1)          # show the hinges + pad zones (send "debug 0" to hide)
    s("/gscore/physics", "gravity", 0.0, -1.0, 0.0)
    s("/gscore/physics", "enable", 1)


if __name__ == "__main__":
    build()
    print("\nDouble pendulum swinging — /music/note <pad> <note> <speed> streams below.")
    print("It settles after a while; re-run to wind it up again. Ctrl+C to stop.\n")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nbye")
