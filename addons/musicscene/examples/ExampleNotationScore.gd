extends Node2D
## Minimal notation-only demo: loads a score page, shows a cursor and a highlighted region.

func _ready() -> void:
	await get_tree().create_timer(0.6).timeout
	var osc := get_node_or_null("/root/MusicSceneOSC")
	if osc == null:
		return
	osc.script_runner.run_text("""
/ms/scene clear
/ms/scene/score new notation
/ms/scene/score notation png "res://scores/page1.png"
/ms/scene/score pos 0 0
/ms/scene/score scale 0.9
/ms/scene/score/cursor show 1
/ms/scene/score/cursor pos 0.2 0.5
/ms/scene/score/cursor color 1 0 0 0.8
/ms/scene/score/region m1 rect 0.1 0.25 0.2 0.1
/ms/scene/score/region m1 highlight 1
/ms/scene/score/region m1 on click /score/measure
""")
