extends RefCounted
## Creates the built-in visual/notation object types. Returns a bare Node; the registry parents
## it and wraps it in a GScoreObject. Notation nodes are GScoreNotationObject instances that the
## notation manager finishes wiring.

const Primitive := preload("res://addons/gscore_osc/core/GScorePrimitive2D.gd")
const NotationObject := preload("res://addons/gscore_osc/notation/GScoreNotationObject.gd")

const BUILTIN_TYPES := [
	"group", "text", "rect", "circle", "line", "image", "sprite", "area", "notation",
]


static func is_builtin(type: String) -> bool:
	return type in BUILTIN_TYPES


## Returns the created Node, or null on failure (after emitting an error through ctx).
static func create(type: String, args: Array, ctx) -> Node:
	match type:
		"group":
			var g := Node2D.new()
			g.name = "Group"
			return g

		"text":
			var p := Primitive.new()
			p.kind = Primitive.Kind.TEXT
			p.name = "Text"
			if args.size() > 0:
				p.text = String(args[0])
			return p

		"rect":
			var p := Primitive.new()
			p.kind = Primitive.Kind.RECT
			p.name = "Rect"
			p.size = Vector2(120, 80)
			return p

		"circle":
			var p := Primitive.new()
			p.kind = Primitive.Kind.CIRCLE
			p.name = "Circle"
			p.radius = 40.0
			p.fill_color = Color(0.95, 0.55, 0.45, 1.0)
			return p

		"line":
			var p := Primitive.new()
			p.kind = Primitive.Kind.LINE
			p.name = "Line"
			var pts := PackedVector2Array()
			var i := 0
			while i + 1 < args.size():
				pts.append(Vector2(float(args[i]), -float(args[i + 1])))
				i += 2
			if pts.size() < 2:
				pts = PackedVector2Array([Vector2(-60, 0), Vector2(60, 0)])
			p.points = pts
			return p

		"image", "sprite":
			var s := Sprite2D.new()
			s.name = "Sprite"
			s.centered = true
			if args.size() > 0:
				var path := String(args[0])
				var tex := _load_texture(path)
				if tex == null:
					ctx.error("load_failed", "/gscore/scene", "Could not load image: " + path)
				else:
					s.texture = tex
			return s

		"area":
			var a := Area2D.new()
			a.name = "Area"
			var col := CollisionShape2D.new()
			var shape := RectangleShape2D.new()
			shape.size = Vector2(120, 120)
			col.shape = shape
			a.add_child(col)
			return a

		"notation":
			var n := NotationObject.new()
			n.name = "Notation"
			return n

		_:
			ctx.error("bad_arguments", "/gscore/scene", "Unknown built-in type: " + type)
			return null


static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is Texture2D:
			return res
	# Fall back to loading a raw image file (user:// or external png) at runtime.
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null
