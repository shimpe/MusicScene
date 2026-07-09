@tool
class_name OscExposable
extends Node
## Component that marks a Godot node as OSC-controllable and declares exactly what is exposed.
##
## Usage: add OscExposable as a CHILD of the node you want to expose (it controls its parent
## by default). To expose the node the script is attached to directly, set `target_path` to "."
## (self). The registry auto-binds every OscExposable whose `osc_auto_bind` is true on startup.
##
## Being exposed at all is the primary safety mechanism for existing project nodes: without an
## OscExposable (or an `osc_expose` meta) a node cannot be bound, so nothing can reach it.
##
## Once a node IS bound, the allow-lists gate WRITES and CALLS only:
##   osc_methods    -> allow-list for `call`   (enforced)
##   osc_properties -> allow-list for `prop`   (enforced; property SET)
##   osc_allow_free -> permits `free`          (enforced)
##   osc_signals    -> NOT enforced. Informational only: it feeds the `signals` and
##                     `capabilities` queries. Any signal the node has can be forwarded with
##                     `/ms/scene/<id>/signal`, listed here or not.
## Reads are likewise ungated: `getProp` / `get` / `dump` return any property of a bound node.
## Treat every readable property and every existing signal of a bound node as reachable.
## Developer mode additionally relaxes the `call` / `prop` / `free` gates. See ADVANCED.md §5.

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
