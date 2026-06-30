# gscore_osc — Physics Constraints & Joints (spec §11)

**Date:** 2026-06-30
**Status:** Approved design, ready for implementation planning
**Scope:** Add OSC-controlled physics joints to gscore_osc, in **both 2D and 3D**, exposing each
engine's **native** joint types (not a 2D vocabulary approximated onto 3D).

---

## 1. Goal

Let OSC clients build "physical notation" — notes hanging from strings, bouncing rhythms,
gravity-driven forms — by constraining physics bodies with joints. Joints get their own OSC
namespace and id space, parallel to `/gscore/scene/<id>`:

```
/gscore/joint/<id> new <type> <a> <b>
/gscore/joint/<id> <property> <args...>
/gscore/joint/<id> del
```

`<a>` and `<b>` are existing **scene-object ids** that must already have physics enabled.

---

## 2. Design principles

- **Native per space.** Each spatial backend exposes Godot's *real* joint types. 2D maps the spec's
  list directly (those *are* Godot's 2D joints); 3D exposes the full 3D joint family rather than
  imitating 2D semantics.
- **Uniform grammar, per-space vocabulary.** The verb grammar is identical in both spaces; the set of
  valid `<type>` values and which properties apply is declared by the active backend. A property that
  a given joint type doesn't support is a **logged no-op**, never a hard error.
- **Mirror the physics architecture.** Joints reuse the exact structural pattern already established
  for physics bodies (world router + per-object adapter + dimension-specific backend methods), so the
  code reads like the surrounding code.
- **Dimension-agnostic core.** `GScoreJointWorld` and `GScoreJoint` contain no `Node2D`/`Node3D`
  specifics; everything dimension-specific goes through `ctx.spatial`.
- **Normalized values.** `stiffness`/`damping` are `0..1`, mapped per backend to a musically useful
  range. Lengths (`restLength`, slider `limit`) are normalized app/length units converted through the
  coordinate mapper, consistent with every other gscore length.

---

## 3. Architecture

Three new pieces mirroring the physics trio (`GScorePhysicsWorld` / `GScorePhysicsAdapter` /
spatial backend methods):

| New file | Mirrors | Responsibility |
|---|---|---|
| `physics/GScoreJointWorld.gd` | `GScorePhysicsWorld` | Owns `id → GScoreJoint` map (its own id space). Routes `/gscore/joint/...` commands. Steps each physics frame to monitor `breakForce` and prune joints whose endpoints died. |
| `physics/GScoreJoint.gd` | `GScorePhysicsAdapter` | Wraps one Godot joint node + the two endpoint `GScoreObject`s + cached params + the generic6dof active-DOF cursor. Per-frame strain check. |
| new methods on `core/GScoreSpatial2D.gd` / `GScoreSpatial3D.gd` | `make_body`, `make_collider`, … | All native joint creation and parameter application. Each backend declares `joint_types()` and applies `joint_set_param`. |

**Context wiring.** `ctx.joints` is created alongside `ctx.physics_world` at startup. The physics
step driver (whatever currently calls `physics_world.physics_step(delta)`) also calls
`ctx.joints.physics_step(delta)`.

**Dispatcher.** Add one case to `OscDispatcher.dispatch`:

```gdscript
"joint", "joints":
    # head=="joint"  => /gscore/joint/<id> <verb> ...
    # head=="joints" => /gscore/joints <query>   (sibling namespace for `list`)
    if head == "joints":
        ctx.joints.handle_global(parts.slice(2), args)
    else:
        var jid := str(parts[2]) if parts.size() > 2 else ""
        ctx.joints.handle(jid, args)
```

**Node placement.** Joint nodes are parented directly under `ctx.objects_root` (which is the correctly
typed `Node2D`/`Node3D`, so the joint's `global_position`/`global_transform` resolve against the same
space as the bodies). `node_a`/`node_b` are set as NodePaths from the joint to each endpoint body.

---

## 4. Endpoints

`<a>` and `<b>` resolve through the registry to scene objects. For each:

1. `obj = ctx.registry.get_object(id)`; if missing → `unknown_object` error.
2. The body is `obj.physics_adapter.body` if an adapter exists, else `obj.node` if
   `ctx.spatial.is_physics_body(obj.node)`, else → `bad_arguments` error:
   *"joint endpoint '<id>' has no physics body; enable physics first"*.

In practice at least one endpoint should be a movable (rigid) body — joining two static bodies just
produces an inert constraint, which is harmless and not treated as an error (no extra dimension-specific
static check is introduced).

On creation the joint node is positioned/oriented from the two bodies' current world transforms
(e.g. spring/slider placed at body A, axis pointing toward body B; pin at body A's origin). The
backend owns this geometry.

**Endpoint death.** Each physics step, if either endpoint body becomes invalid, the joint frees
itself silently (same pruning policy as physics adapters). No event is emitted for this case (it is a
consequence of an explicit `scene/<id> free`, which the client already knows about).

---

## 5. Type vocabulary

### 5.1 2D (`GScoreSpatial2D`)
| logical type | Godot node | notes |
|---|---|---|
| `pin` | `PinJoint2D` | ball/pivot; supports `motor` (target velocity), angular `limit` |
| `spring`, `dampedSpring` | `DampedSpringJoint2D` | aliases; `spring` defaults to low damping |
| `groove` | `GrooveJoint2D` | body B slides in body A's groove; `limit` sets groove length |
| `distance` | `DampedSpringJoint2D` | preset: high stiffness + near-critical damping ⇒ near-rigid rod at `restLength` |

### 5.2 3D (`GScoreSpatial3D`)
| logical type | Godot node | notes |
|---|---|---|
| `pin` | `PinJoint3D` | ball joint (3 rotational DOF free); params via bias/damping/impulse_clamp |
| `hinge` | `HingeJoint3D` | 1 rotational DOF; `motor` (speed + torque→max impulse, **real**), `limit` (degrees), `axis` |
| `slider` | `SliderJoint3D` | 1 linear DOF with limits; `stiffness`/`damping` tune the limit compliance; for a true linear spring-to-equilibrium use `generic6dof`. `restLength` is a no-op. `axis` |
| `coneTwist` | `ConeTwistJoint3D` | ball with swing/twist limits; `limit` → swing_span/twist_span (degrees), `stiffness`/`damping` → softness/relaxation |
| `generic6dof` | `Generic6DOFJoint3D` | full per-axis control via the `dof` selector (see §6.6) |

If `new` is given a type the active backend does not support (e.g. `hinge` in 2D mode), reply
`bad_arguments`: *"joint type 'hinge' is not available in 2d space"*.

---

## 6. Verb / property surface

All numeric args accepted as float or numeric string (existing `_f` helper convention).

### 6.1 `new <type> <a> <b>`
Creates the joint (§4, §5). Re-issuing `new` on an existing joint id frees the old joint first
(consistent with registry re-creation semantics).

### 6.2 `stiffness <0..1>` / `damping <0..1>`
Normalized; mapped per backend to native ranges via documented constants, e.g.

- 2D `DampedSpringJoint2D`: `stiffness_native = lerp(MIN, MAX, v)` chosen so `0.8` is firm-but-springy
  and `1.0` is near-rigid; `damping_native` similar.
- 3D `SliderJoint3D`: `stiffness` → `PARAM_LINEAR_LIMIT_SOFTNESS` (limit compliance analog); `damping` → `PARAM_LINEAR_LIMIT_DAMPING`. No spring params exist on this joint.
- 3D `Generic6DOFJoint3D` spring: `*_spring_stiffness` / `*_spring_damping`.
- 3D `ConeTwistJoint3D`: maps to `softness` / `relaxation`.

Mapping constants live in one documented block in each backend. No-op (logged) on joint types
without a spring (e.g. 2D `pin`, 3D `pin`).

### 6.3 `restLength <norm>`
Converted through `ctx.spatial` length mapping (2D px, 3D world units). Sets the spring's
`rest_length`/equilibrium; the joint's `length`/limit max is set to `max(current_separation,
rest_length)` so the spring is well-formed. No-op on non-spring joints.

### 6.4 `limit <lower> <upper>`
- Angular joints (2D pin angular, 3D hinge, coneTwist, 6dof angular DOF): **degrees**.
- Linear joints (2D groove length, 3D slider, 6dof linear DOF): **normalized length** (mapper-converted).

Enables the corresponding limit on the native joint and sets lower/upper. No-op where unsupported.

### 6.5 `motor <speed> <torque>` and `axis <x> <y> <z>`
- `motor`: 2D `pin` → `motor_enabled=true`, `motor_target_velocity=speed` (rad/s); `torque` is a
  **documented no-op in 2D** (Godot 2D pin exposes no max impulse). 3D `hinge` → motor enabled,
  target velocity = `speed`, **`motor/max_impulse` = mapped(`torque`)** (real). 3D `generic6dof` → the
  active DOF's motor (see §6.6). No-op elsewhere.
- `axis`: geometric working axis (a direction vector, normalized) for `hinge`/`slider`/`coneTwist`.
  Default at creation is the A→B direction (or world-up if degenerate). Re-orients the joint basis.
  Ignored in 2D and on `pin`.

### 6.6 `dof <token>` (generic6dof only)
Sets the joint's **active DOF cursor**; subsequent `limit`/`stiffness`/`damping`/`restLength`/`motor`
verbs target that DOF. Tokens: `linX linY linZ angX angY angZ`, plus convenience `lin` (all three
linear), `ang` (all three angular), `all`. Default cursor before any `dof` is `all`. On a non-6dof
joint, `dof` is a logged no-op.

Example:
```
/gscore/joint/j new generic6dof noteA noteB
/gscore/joint/j dof linY
/gscore/joint/j limit -0.2 0.2
/gscore/joint/j stiffness 0.7
/gscore/joint/j dof angY
/gscore/joint/j motor 1.0 0.5
```

### 6.7 `breakForce <0..1>`
Implemented as an **overstretch / strain proxy** — Godot does not expose joint solver reaction force.
The world step computes the joint's current endpoint separation (or twist beyond limit for angular
joints); when it exceeds a threshold derived from `breakForce` (lower value ⇒ snaps sooner), the
joint is freed and the world emits:

```
/gscore/event/jointBreak <id> <a> <b>
```

Most meaningful for spring/distance/slider joints; on a near-rigid `pin` it effectively never
triggers (documented). `breakForce` of `0` disables breaking.

### 6.8 `del`
Frees the joint node and removes it from the map. Idempotent; unknown id → `unknown_object` error.

### 6.9 Queries (debug niceties, beyond spec)
- `/gscore/joint/<id> info` → `ctx.reply("joint/info", [id, type, a, b, ...params])`.
- `/gscore/joints list` → `ctx.reply("joints/list", [id1, type1, id2, type2, ...])`.

---

## 7. Events

| address | when |
|---|---|
| `/gscore/event/jointBreak <id> <a> <b>` | `breakForce` threshold exceeded; joint auto-freed |

Errors use the existing `ctx.error(code, address, message)` channel with codes
`unknown_object` / `bad_arguments` / `unsupported_type`.

---

## 8. Coordinate & axis conventions

- Lengths normalized, mapper-converted (2D `length_x_to_pixels`, 3D `length_to_world`), matching all
  other gscore lengths.
- Angular `limit`/`motor` speeds in degrees / rad-per-second respectively, matching existing rotation
  (`rotate` uses degrees) and angular-velocity conventions.
- 3D `axis` is a world-space direction; the backend builds the joint basis from it.

---

## 9. Verification

- **Headless self-test** `tools/test_joints.gd` (SceneTree script, both spaces via two runs or a
  space override): create two rigid bodies, `joint new`, step physics N frames, assert the joint node
  exists and constrains (bodies stay within expected separation); then drive overstretch and assert a
  `/gscore/event/jointBreak` is emitted. Mirrors `tools/test_recreate.gd` style.
- **CI** extends the existing boot/self-test job to run `test_joints.gd` and grep for PASS.
- **Tutorial** new section "Physical notation: joints" with a 2D hanging-note spring example and a 3D
  hinge/slider example; documents the `breakForce` strain-proxy and 2D-`motor`-torque caveats.
- **Example** wire `ExamplePhysicalNote.tscn` (already a `RigidBody2D` note) into a runnable
  hanging-from-a-string demo driven over OSC.

---

## 10. Out of scope (v1)

- Real Newton-based break force (Godot exposes no joint reaction force).
- Per-joint collision-disable toggle between the two bodies (Godot default kept; can be added later).
- Soft-body / rope chains as a first-class type (achievable by chaining springs; no dedicated type).
- 2D angular motor max-impulse (engine limitation).

---

## 11. File-change summary

**New:** `physics/GScoreJointWorld.gd`, `physics/GScoreJoint.gd`, `tools/test_joints.gd`.
**Modified:** `core/OscDispatcher.gd` (route `joint`/`joints`), `core/GScoreSpatial2D.gd` +
`core/GScoreSpatial3D.gd` (native joint methods + `joint_types()`), context bootstrap (`ctx.joints`,
physics-step call), `TUTORIAL.md`, `CHANGELOG.md`, `addons/gscore_osc/plugin.cfg` (version bump),
`.github/workflows/ci.yml` (run `test_joints.gd`).
