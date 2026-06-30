extends SceneTree
## Does re-`new` under the same id orphan the first node? Run:
##   godot --headless --path . --script res://tools/test_recreate.gd
var _f := 0
func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("AUTOLOAD_MISSING"); return true
	if _f == 5:
		osc.dispatcher.dispatch("/gscore/scene/title", ["new", "text", "A"])
		osc.dispatcher.dispatch("/gscore/scene/title", ["new", "text", "B"])
	if _f == 12:
		print("registered ids = ", osc.registry.list_ids())
		print("objects_root children = ", osc.objects_root.get_child_count())
		return true
	return false
