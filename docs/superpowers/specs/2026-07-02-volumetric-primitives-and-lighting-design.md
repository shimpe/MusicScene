# Design — Volumetric primitives & lighting ("true 3D", phase 1)

**Date:** 2026-07-02 · **Target version:** 0.10.0 · **Status:** approved, ready for planning

Implements workstreams **(a) volumetric primitives** and **(b) lighting + lit materials** from
`2026-07-02-true-3d-future-phase.md`. Workstream **(c) runtime glTF/model loading is out of scope**
(still deferred).

## Motivation

gscore_osc's 3D mode already has real x/y/z coordinates, a freely-positionable camera, 3D physics
with depth colliders, and real-axis joints. What keeps scenes looking flat is the *visual vocabulary*:
only `circle` (a `SphereMesh`) has volume, every material is `_unshaded()`, and there are **no lights**,
so even a sphere renders as a flat silhouette. This phase adds volumetric mesh primitives and a default
lighting rig with lit materials, so 3D scenes can actually look 3D — while remaining **fully
non-breaking**: nothing that exists today changes appearance.

## Goals

- Volumetric mesh primitives: `sphere`, `box`/`cube`, `cylinder`, `capsule`, `cone`.
- A lit `StandardMaterial3D` mode; volumetric primitives lit by default, flat/billboard ones unshaded.
- A default two-light rig (key + fill) added lazily to 3D scenes, mirroring `ensure_camera()`.
- A small control surface: per-object `shaded`/`metallic`/`roughness`, a global `scene shading`
  toggle, and a `/gscore/light` namespace to tweak the default lights.
- Full backward compatibility and a headless test suite wired into CI.

## Non-goals (still deferred)

Runtime glTF/`.obj` loading; multiple named/point/spot lights; shadows-on-by-default; sky/environment
backgrounds; per-material textures. All remain future-phase.

---

## 1. Volumetric primitives

Added to `GScoreSpatial3D.create_primitive(type, args)`. Dimensions are in the active app coord mode
(`length_to_world`), matching the existing sizable `circle`/`rect`. Each gets a lit material by default
(§2) and works with the existing auto-collider (mesh AABB → box) plus new explicit collider kinds.

| Command | Mesh (3D) | Dims → params | Defaults (world) |
|---|---|---|---|
| `new sphere [r]` | `SphereMesh` | `r` = radius | r 0.3 |
| `new box [w] [h] [d]` *(alias `cube`)* | `BoxMesh` | `size` = (w, h, d); h,d default to w | 0.6 × 0.6 × 0.6 (matches the sphere's 0.6 diameter) |
| `new cylinder [r] [h]` | `CylinderMesh` (top=bottom=r) | radius r, height h | r 0.3, h 0.8 |
| `new capsule [r] [h]` | `CapsuleMesh` | radius r, height h (total; clamped ≥ 2r) | r 0.3, h 0.9 |
| `new cone [r] [h]` | `CylinderMesh` (top_radius = 0) | radius r, height h | r 0.3, h 0.8 |

`sphere` and the existing `circle` share a `_sphere_mesh(args)` builder — **same geometry**, so sizing,
colliders and physics are identical; they differ only in the default material (§2). `circle` is
unchanged (still `SphereMesh`, still unshaded).

**Colliders.** `make_collider` gains `cylinder` (`CylinderShape3D`) and `capsule` (`CapsuleShape3D`)
kinds so `collider cylinder r h` / `collider capsule r h` match their meshes. `box`/`sphere` kinds
already exist. `cone` has no exact Godot collision shape; its auto-collider is the AABB box, or use
`collider cylinder`. The `"auto"` path (mesh AABB → `BoxShape3D`) is unchanged and works for every new
mesh.

**2D fallback (`GScoreSpatial2D`).** So the dimension-agnostic API never errors in 2D, the new types
alias to the nearest existing 2D primitive: `box`/`cube` → rect, `cylinder`/`capsule`/`cone` → rect,
`sphere` → circle. (Faithful 2D silhouettes are a possible later refinement, not part of this phase.)

## 2. Materials

New helper `_lit(color)` alongside the existing `_unshaded(color)`:

- `StandardMaterial3D`, per-pixel shading (Godot default), `albedo_color = color`,
  `roughness = 0.7`, `metallic = 0.0`, `cull_mode = CULL_BACK`, opaque (transparency switches to
  `ALPHA` only when opacity < 1, via the existing `set_opacity`).

**Default material by primitive name** (the rule is keyed on the creation name, not the geometry):

| Lit by default | Unshaded by default |
|---|---|
| `sphere`, `box`/`cube`, `cylinder`, `capsule`, `cone` | `circle`, `rect`, `text`, `image`/`sprite`, `line`, `notation`, `group` |

Because unshaded materials ignore lights entirely, adding the default rig (§3) does **not** change how
any unshaded object looks. Combined with `circle` staying unshaded, **no existing scene changes
appearance.**

**Per-object verbs** (added to `GScoreObject.apply_command`, delegating to the spatial backend):

- `shaded [1|0]` — flip `material_override.shading_mode` between per-pixel (lit) and unshaded.
  `shaded` with no arg = `shaded 1`. Creates a default material if the node has none.
- `metallic <0..1>` — set metallic on the `StandardMaterial3D` (clamped).
- `roughness <0..1>` — set roughness (clamped).

`metallic`/`roughness` only affect appearance under a lit material; they set the value regardless (so
toggling `shaded 1` later shows them). In 2D these three verbs are **no-ops** (CanvasItems have no PBR),
returning without error.

**Global toggle** — `/gscore/scene shading auto|shaded|flat` (new verb in `_handle_scene`'s empty-rest
branch, beside `reset`/`clear`):

- `auto` *(default)* — every object uses its per-type default from the table above.
- `shaded` — force the volumetric solids (classified by `type_hint` ∈ {sphere, box, cube, cylinder,
  capsule, cone}) lit; flat/billboard objects left as-is. **`circle` is deliberately excluded** — it
  always stays flat; light an individual circle only with a per-object `shaded 1`.
- `flat` — force **all** objects unshaded (the classic INScore look).

The chosen mode is stored on the context and consulted by `create_primitive` for newly created
objects, and the command re-applies the mode to all existing registered objects.

## 3. Lighting

`GScoreSpatial3D.ensure_lighting()` — lazy, invoked from the same 3D scene-setup path as
`ensure_camera()`, and **bails if a `DirectionalLight3D` already exists** in the viewport (so a
user-provided rig is never doubled). It adds two lights as children of the gscore root:

- **`GScoreKeyLight`** — `DirectionalLight3D`, angled from upper-front (≈ `rotation_degrees
  (-50, -35, 0)`), `light_energy 1.0`, shadows **off**.
- **`GScoreFillLight`** — `DirectionalLight3D`, dim, from the opposite side (≈ `(-20, 145, 0)`),
  `light_energy 0.35`, shadows off.

Two directional lights (rather than a `WorldEnvironment`) keep the existing background/clear color
untouched and give volumes a lit side and a softly-lit side with no pure-black faces.

**Commands** — `/gscore/light <sub> …` routes (new `"light":` case in `OscDispatcher`) to
`ctx.spatial.handle_light(rest, args)`; 3D implements, 2D no-ops:

| Command | Effect |
|---|---|
| `dir x y z` | Aim the key light so it shines toward world vector (x, y, z). |
| `color r g b` | Key light color. |
| `energy e` | Key light energy. |
| `ambient e` | Fill light energy (the soft "ambient" fill). |
| `shadows 0\|1` | Enable/disable shadows on the key light (opt-in, default off). |
| `reset` | Restore all light defaults. |

`dir` is a raw direction vector (not coord-mode scaled).

---

## Architecture & files

| File | Change |
|---|---|
| `core/GScoreSpatial3D.gd` | New primitive cases + `_sphere_mesh`; `_lit`; `set_shaded`/`set_metallic`/`set_roughness`; `ensure_lighting` + `handle_light`; `make_collider` `cylinder`/`capsule`; classify-by-type helper for the global toggle. |
| `core/GScoreSpatial2D.gd` | New-primitive aliases; `set_shaded`/`set_metallic`/`set_roughness` and `handle_light` no-ops. |
| `core/GScoreObject.gd` | `apply_command` verbs `shaded`/`metallic`/`roughness`. |
| `core/OscDispatcher.gd` | `"light":` route; `scene shading` verb; version `0.9.0` → `0.10.0` (3 occurrences). |
| 3D scene-setup call site | Call `ensure_lighting()` where `ensure_camera()` is already called. |
| `tools/test_volumetric.gd`, `tools/test_lighting.gd`, `tools/test_material_mode.gd` | New headless tests. |
| `.github/workflows/ci.yml` | Wire the new tests in. |
| `README.md`, `TUTORIAL.md`, `CHANGELOG.md` | Command reference, a "volumetric shapes & lighting" section, `[0.10.0]` entry. |
| `docs/.../2026-07-02-true-3d-future-phase.md`, memory `true-3d-future-phase.md` | Mark (a)+(b) done; (c) still deferred. |
| `core/GScoreSpatial3D.gd` `body_set_planar` docstring | Soften the now-stale "3D is really 2D in a plane" wording. |

If lighting + materials push `GScoreSpatial3D` (already ~860 lines) past comfortable readability,
extract a `GScoreMaterial3D` static helper for `_lit`/`_unshaded`/mode-application — decided during
implementation, not pre-split.

## Backward compatibility

- `circle`, `rect`, `text`, `image`, `line`, `notation` are visually unchanged.
- The default lights only affect **lit** materials, which only the new primitives use by default;
  existing scenes contain no lit objects, so they render identically.
- `ensure_lighting()` skips when the user already has a light, mirroring `ensure_camera()`.
- New verbs/namespaces are additive; unknown-command behavior is unchanged for older clients.

## Testing (headless, `--script`)

- **test_volumetric** — each new type creates a `MeshInstance3D` with the expected mesh class
  (`cone` = `CylinderMesh` with `top_radius == 0`; `capsule.height ≥ 2·radius`); `sphere` is lit,
  `circle` is unshaded; enabling physics yields an auto-collider; `collider cylinder`/`capsule`
  produce the matching shapes.
- **test_lighting** — after setup, key + fill `DirectionalLight3D` exist; `energy`/`ambient`/`color`/
  `dir`/`shadows` mutate the right light; `reset` restores; `ensure_lighting` is idempotent and skips
  a pre-existing light.
- **test_material_mode** — `sphere` lit by default; `shaded 0` → unshaded; `metallic`/`roughness` set
  values; `scene shading flat` → all unshaded; `shaded` → volumetric lit; `auto` → per-type.
- **2D fallback** — in 2D, the new `new <type>` create without error; `shaded`/`metallic`/`roughness`
  and `/gscore/light …` are no-ops without error.

## Rollout

Version → **0.10.0**. Docs updated (README/TUTORIAL/CHANGELOG). Future-phase spec + memory updated to
show (a)+(b) landed and (c) deferred. Optional follow-up examples (a lit-solids demo) are out of scope
for this plan.
