@tool
extends EditorPlugin
## gscore_osc editor plugin.
##
## Installs the GScoreOSC autoload singleton (the central GScoreRoot controller) so the
## OSC server boots automatically when the project runs. Removing the plugin removes it.

const AUTOLOAD_NAME := "GScoreOSC"
const AUTOLOAD_PATH := "res://addons/gscore_osc/nodes/GScoreRoot.gd"


func _enter_tree() -> void:
	# add_autoload_singleton is idempotent; safe even if project.godot already lists it.
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
