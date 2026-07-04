# MusicScene example score — full vertical slice (notation + cursor + region + physics)
# Run via:  /ms/script/load "res://addons/musicscene/examples/example_score.gscore"
# or it runs automatically from ExampleMain.tscn.

/ms/scene clear

# --- Notation ---
/ms/scene/score new notation
/ms/scene/score notation png "res://scores/page1.png"
/ms/scene/score pos 0 0.1
/ms/scene/score scale 0.85
/ms/scene/score/cursor show 1
/ms/scene/score/cursor pos 0.1 0.5
/ms/scene/score/cursor color 1 0 0 0.8
/ms/scene/score/region m1 rect 0.1 0.25 0.2 0.1
/ms/scene/score/region m1 highlight 1
/ms/scene/score/region m1 on click /score/measure

# --- Physics floor ---
/ms/scene/floor new rect
/ms/scene/floor pos 0 -0.85
/ms/scene/floor size 1.8 0.05
/ms/scene/floor color 0.3 0.3 0.35 1
/ms/scene/floor/physics enable static
/ms/scene/floor/collider rect 1.8 0.05

# --- A bouncing note that emits OSC on impact ---
/ms/scene/note1 new circle
/ms/scene/note1 pos -0.3 0.8
/ms/scene/note1/physics enable rigid
/ms/scene/note1/collider circle 0.05
/ms/scene/note1/physics bounce 0.8
/ms/scene/note1/on collisionEnter /synth/hit minIntensity 0.2 cooldown 0.05
/ms/scene/note1/payload collisionEnter self other intensity x y time

# --- Turn on gravity ---
/ms/physics enable 1
/ms/physics gravity 0 -0.5

# --- Sweep the cursor across the page over 8 seconds ---
/ms/transport tempo 120
/ms/transport play
/ms/scene/score/cursor map 0 8 x 0.05 0.95
