@tool
class_name OscExposable
extends Node
## Component that marks a Godot node as OSC-controllable and declares exactly what is exposed.
##
## Usage: add OscExposable as a CHILD of the node you want to expose (it controls its parent
## by default). To expose the node the script is attached to directly, set `target_path` to "."
## (self). The registry auto-binds every OscExposable whose `osc_auto_bind` is true on startup.
##
## Only members listed here are reachable over OSC unless developer mode is enabled. This is
## the primary safety mechanism for existing project nodes.

@export var osc_id: String = ""
@export var osc_auto_bind: bool = true
@export var osc_allow_bind: bool = true
@export var osc_allow_free: bool = false
@export var osc_methods: Array[String] = []
@export var osc_properties: Dictionary = {}   ## name -> optional type hint (informational)
@export var osc_signals: Array[String] = []

## Node this component exposes. Empty = parent; "." = the node this script is attached to.
@export var target_path: NodePath = NodePath("")


func get_target() -> Node:
	if String(target_path) != "":
		return get_node_or_null(target_path)
	return get_parent()


func suggested_id() -> String:
	if osc_id != "":
		return osc_id
	var t := get_target()
	return t.name.to_snake_case() if t != null else name
