extends RefCounted
## Thin manager that connects the dispatcher to per-object MSNotationObject instances and
## owns notation-global concerns (the render cache). Keeps notation routing out of the
## dispatcher and out of MSObject.

const Cache := preload("res://addons/musicscene/notation/MSNotationCache.gd")

var ctx = null


func _init(p_ctx) -> void:
	ctx = p_ctx


## Wire a freshly created/registered notation object (2D or 3D).
func attach(obj) -> void:
	if ctx.spatial.is_notation(obj.node):
		obj.notation = obj.node
		obj.node.setup(ctx, obj.osc_id)


func _notation(obj):
	if obj.notation != null:
		return obj.notation
	if ctx.spatial.is_notation(obj.node):
		attach(obj)
		return obj.notation
	ctx.error("unsupported_type", "/ms/scene/" + obj.osc_id,
		"Not a notation object: " + obj.osc_id)
	return null


func handle_command(obj, verb: String, args: Array) -> void:
	var n = _notation(obj)
	if n != null:
		n.handle(verb, args)


func handle_cursor(obj, args: Array) -> void:
	var n = _notation(obj)
	if n != null:
		n.handle_cursor(args)


func handle_region(obj, args: Array) -> void:
	var n = _notation(obj)
	if n != null:
		n.handle_region(args)


func handle_annotation(obj, args: Array) -> void:
	var n = _notation(obj)
	if n != null:
		n.handle_annotation(args)


func reply_regions(obj) -> void:
	var n = _notation(obj)
	if n != null:
		n.reply_regions()


func reply_annotations(obj) -> void:
	var n = _notation(obj)
	if n != null:
		n.reply_annotations()


func reply_info(obj) -> void:
	var n = _notation(obj)
	if n != null:
		n.reply_info()


func reply_pages(obj) -> void:
	var n = _notation(obj)
	if n != null:
		n.reply_pages()


func reply_current_page(obj) -> void:
	var n = _notation(obj)
	if n != null:
		n.reply_current_page()


func handle_cache(args: Array) -> void:
	var cmd := str(args[0]) if args.size() > 0 else ""
	match cmd:
		"clear":
			var removed := Cache.clear()
			ctx.reply("notation/cache", ["cleared", removed])
		"info":
			var i := Cache.info()
			ctx.reply("notation/cache", ["info", i.count, i.bytes, i.dir])
		_:
			ctx.error("bad_arguments", "/ms/notation/cache", "Expected clear|info")
