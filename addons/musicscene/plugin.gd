@tool
extends EditorPlugin
## MusicScene editor plugin.
##
## Installs the MusicSceneOSC autoload singleton (the central MSRoot controller) so the
## OSC server boots automatically when the project runs. Removing the plugin removes it.

const AUTOLOAD_NAME := "MusicSceneOSC"
const AUTOLOAD_PATH := "res://addons/musicscene/nodes/MSRoot.gd"


func _enter_tree() -> void:
	# add_autoload_singleton is idempotent; safe even if project.godot already lists it.
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
