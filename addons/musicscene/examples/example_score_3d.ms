# MusicScene 3D example — notation quad in world space + 3D physics
# Requires ms/space = "3d". Runs automatically from ExampleMain3D.tscn.

/ms/scene clear

# --- Notation page on a quad in 3D space ---
/ms/scene/score new notation
/ms/scene/score notation png "res://scores/page1.png"
/ms/scene/score pos -0.45 0.15 0
/ms/scene/score rotate 0 -18 0
/ms/scene/score/cursor show 1
/ms/scene/score/cursor pos 0.1 0.5
/ms/scene/score/cursor color 1 0 0 0.85
/ms/scene/score/region m1 rect 0.1 0.25 0.2 0.1
/ms/scene/score/region m1 highlight 1
/ms/scene/score/region m1 on click /score/measure

# --- Physics floor (a flat box) ---
/ms/scene/floor new rect
/ms/scene/floor pos 0.3 -0.7 0
/ms/scene/floor scale 3 0.15 3
/ms/scene/floor color 0.3 0.3 0.35 1
/ms/scene/floor/physics enable static
/ms/scene/floor/collider box 0.9 0.05 0.9

# --- A bouncing note (sphere) that emits OSC on impact ---
/ms/scene/note1 new circle
/ms/scene/note1 pos 0.3 0.8 0
/ms/scene/note1/physics enable rigid
/ms/scene/note1/collider sphere 0.1
/ms/scene/note1/physics bounce 0.7
/ms/scene/note1/on collisionEnter /synth/hit minIntensity 0.05 cooldown 0.05
/ms/scene/note1/payload collisionEnter self other intensity x y z time

# --- Gravity (downward along -Y) ---
/ms/physics enable 1
/ms/physics gravity 0 -0.6 0

# --- Sweep the cursor across the page ---
/ms/transport tempo 120
/ms/transport play
/ms/scene/score/cursor map 0 8 x 0.05 0.95
