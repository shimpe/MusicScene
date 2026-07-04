extends RefCounted
## Built-in object types. Creation is delegated to the active spatial backend
## (ctx.spatial.create_primitive), so the same type names produce 2D or 3D nodes depending on
## ms/space. The registry parents the returned node and wraps it in a MSObject.

const BUILTIN_TYPES := [
	"group", "text", "rect", "circle", "line", "image", "sprite", "area", "notation",
	"sphere", "box", "cube", "cylinder", "capsule", "cone",
	"bouncer", "portal",
]


static func is_builtin(type: String) -> bool:
	return type in BUILTIN_TYPES


## Returns the created Node, or null on failure (after emitting an error through ctx).
static func create(type: String, args: Array, ctx) -> Node:
	return ctx.spatial.create_primitive(type, args)
