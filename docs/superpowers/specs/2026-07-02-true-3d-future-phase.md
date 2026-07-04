# Future phase — "True 3D" (deferred)

**Status: (a) volumetric primitives + (b) lighting LANDED in 0.10.0** (see `2026-07-02-volumetric-primitives-and-lighting-design.md`). **(c) runtime model loading still deferred / backlog.**

## Context

MusicScene's 3D mode (`ms/space = "3d"`) is already a genuine 3D coordinate + physics +
camera system, not a 2D fake:

- **Coordinates**: `pos x y z`, per-axis `x`/`y`/`z`, and `gravity`/`velocity`/`force` all take a real z
  (`to_world_point` / `to_world_vector` in `core/MSSpatial3D.gd`).
- **Camera**: freely positionable/aimable — `pos`, `lookAt`, `up`, `target`, `follow` (chase/orbit),
  perspective/orthographic (`core/MSCamera.gd`). The front view is only the *default*.
- **Physics**: 3D joints with real axes; box/sphere colliders with genuine depth (`collider box w h d`,
  depth is a first-class argument).
- **Arbitrary content**: `instantiate <scene>` loads any Godot `PackedScene`, incl. a pre-imported 3D
  `.tscn` (`core/MSRegistry.gd`).
- `planar 1` is an **opt-in** constraint (pin a body to z=0); by default bodies are free in 3D.

What keeps it feeling "2.5D" today is the built-in *visual vocabulary and defaults*, not the math:
flat/billboard primitives, unshaded materials, and no lights — an INScore-style "flat elements arranged
in space" aesthetic.

## Gaps → workstreams for true 3D

### (a) Volumetric primitives
Only `circle` (SphereMesh) has volume. `rect` = flat quad, `text`/`image` = billboards, `line` = flat,
`notation` = textured quad. There is a box *collider* but no box *visual*.
- Add `box`/`cube`, `cylinder`, `capsule` (maybe `cone`/`torus`) mesh primitives in `create_primitive`
  (`MSSpatial3D`); give each a matching auto-collider.
- **Effort: low.** Mostly mirrors the existing `circle`/`rect` cases.

### (b) Lighting + lit/PBR materials
All primitives use `_unshaded()` `StandardMaterial3D`; there are no lights, so even volumetric shapes
read as flat silhouettes.
- Add a default `DirectionalLight3D` (+ optional `WorldEnvironment` / ambient) on 3D scene setup.
- Offer a lit/shaded material mode (per-object or global toggle), optional albedo/metallic/roughness.
- **Effort: low–medium.** Keep it from breaking flat-notation legibility — make lighting opt-in/scoped.

### (c) Runtime 3D model loading
`instantiate` needs a pre-imported `.tscn`; there is no raw `.glb`/`.gltf`/`.obj` loading.
- Add a loader (e.g. `new model <path>` or a `mesh`/`model` command) using Godot's `GLTFDocument` /
  `GLTFState` at runtime, respecting the asset whitelist/permissions.
- **Effort: medium.** Runtime glTF import + scale/material normalization + permission gating.

## Notes / ordering
- **(a) + (b) together are the highest leverage** — they make 3D scenes actually *look* 3D with little
  code. Do these first.
- Keep everything **opt-in** so the default flat/INScore aesthetic and notation legibility are preserved.
  True 3D should be additive, not a breaking change.
- Companion idea: a per-scene `planar` default toggle if flat 2.5D remains the common case.
