extends Node3D
## 3D example scene controller. Provides pre-exposed existing 3D nodes (binding / signal
## acceptance) and, on start, runs the 3D example .gscore so a score quad + falling note appear
## without an external OSC client. Requires ms/space = "3d".

@export var auto_run_demo: bool = true
@export var demo_script: String = "res://addons/musicscene/examples/example_score_3d.gscore"


func _ready() -> void:
	if not auto_run_demo:
		return
	await get_tree().create_timer(0.6).timeout
	var osc := get_node_or_null("/root/MusicSceneOSC")
	if osc == null:
		push_warning("[ExampleMain3D] MusicSceneOSC autoload not found; is the plugin enabled?")
		return
	if not osc.spatial.is_3d():
		push_warning("[ExampleMain3D] ms/space is not '3d'; set it in Project Settings.")
	osc.script_runner.run_file(demo_script)
