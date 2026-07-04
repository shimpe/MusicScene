extends Node2D
## Main example scene controller. Provides a couple of pre-exposed existing nodes (for the
## binding / signal-forwarding acceptance tests) and, on start, runs the example .ms so the
## project shows a score + physics demo without needing an external OSC client.

@export var auto_run_demo: bool = true
@export var demo_script: String = "res://addons/musicscene/examples/example_score.ms"


func _ready() -> void:
	if not auto_run_demo:
		return
	# Wait for the MusicSceneOSC autoload to finish booting (it auto-binds exposed nodes on frame 2).
	await get_tree().create_timer(0.6).timeout
	var osc := get_node_or_null("/root/MusicSceneOSC")
	if osc == null:
		push_warning("[ExampleMain] MusicSceneOSC autoload not found; is the plugin enabled?")
		return
	osc.script_runner.run_file(demo_script)
