extends Node2D
## Minimal notation-only demo: loads a score page, shows a cursor and a highlighted region.

func _ready() -> void:
	await get_tree().create_timer(0.6).timeout
	var osc := get_node_or_null("/root/GScoreOSC")
	if osc == null:
		return
	osc.script_runner.run_text("""
/gscore/scene clear
/gscore/scene/score new notation
/gscore/scene/score notation png "res://scores/page1.png"
/gscore/scene/score pos 0 0
/gscore/scene/score scale 0.9
/gscore/scene/score/cursor show 1
/gscore/scene/score/cursor pos 0.2 0.5
/gscore/scene/score/cursor color 1 0 0 0.8
/gscore/scene/score/region m1 rect 0.1 0.25 0.2 0.1
/gscore/scene/score/region m1 highlight 1
/gscore/scene/score/region m1 on click /score/measure
""")
