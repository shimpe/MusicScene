#!/usr/bin/env python3
"""
Chaotic double pendulum as a generative sequencer for gscore_osc (3D space).

A two-arm pendulum (two hinges under gravity) swings chaotically. Five sensor
zones laid out across the bottom of its swing are pentatonic "pads" (C D E G A):
whenever the chaotic tip passes through one, gscore emits

    /music/note  <pad-id>  <note>  <tip-speed>

...a never-repeating melody driven by real physics. Point a synth at /music/note
(use <note> for pitch and <tip-speed> as velocity/dynamics).

USAGE
    1. Run the Godot project with gscore_osc set to 3D (gscore_osc/space = "3d").
    2. python tools/example_double_pendulum.py        (or: py tools\\example_double_pendulum.py)
    3. Watch the "<- /music/note ..." lines stream by; Ctrl+C to stop.

The pendulum swings energetically for a while, then slowly settles (physics has a
little numerical damping) — just re-run this file to restart the chaos.
"""
import time
from gosc import s   # tiny OSC client sitting next to this file (also prints incoming messages)


def build():
    # --- fresh scene -------------------------------------------------------
    s("/gscore/scene", "reset")

    # --- the double pendulum ----------------------------------------------
    # A static pivot + two rigid arms + two hinges (both rotating about Z, so the
    # whole thing swings in the screen plane). Colliders are created automatically
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

    # --- five pentatonic pads across the swing -----------------------------
    # left -> right = low -> high. Each pad is a sensor zone that fires only for
    # the chaotic tip (arm2); the tip's speed rides along as note velocity.
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

    # --- go ----------------------------------------------------------------
    s("/gscore/physics", "debug", 1)          # show the hinges + pad zones (send "debug 0" to hide)
    s("/gscore/physics", "gravity", 0.0, -1.0, 0.0)
    s("/gscore/physics", "enable", 1)


if __name__ == "__main__":
    build()
    print("\nDouble pendulum running — /music/note <pad> <note> <speed> will stream below.")
    print("Ctrl+C to stop (re-run to restart the chaos).\n")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nbye")
