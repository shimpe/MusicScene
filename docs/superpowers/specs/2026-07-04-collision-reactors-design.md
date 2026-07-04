# Design — Collision reactors: bouncers & portals

**Date:** 2026-07-04 · **Target version:** 0.12.0 · **Status:** approved, ready for planning

## Motivation

MusicScene can create physics bodies and emit OSC on collision, but bodies only interact through Godot's
default physics response. Two new **collision reactors** add active, scriptable behavior when a body
touches them:

- **Bouncer** — a mirror that reflects a colliding body's velocity (specular reflection) and adds an
  outward impulse "kick" (a pinball bumper).
- **Portal** — teleports a colliding body to one of its linked partner portals, chosen at random.

Both are dimension-agnostic (2D and 3D) and reuse the physics actuation that already exists
(`ctx.spatial.body_get_velocity` / `body_set_velocity` / `set_position`, all teleport-safe for a
live-simulating `RigidBody`).

## Key architectural facts (from research)

- Discrete collision events are Godot-signal driven per body via `MSPhysicsAdapter`. **`Area` bodies
  get `area_entered`/`body_entered` wired; `StaticBody` gets no signals.** So a reactor that must detect
  "who touched me" is an **Area** (pass-through sensor), exactly like existing zones.
- The signal handler `MSPhysicsAdapter._on_area_enter(other)` (and `_on_enter`) is the single hook
  where a reactor acts on the touching body.
- `MSObject.type_hint` already carries the creation type and is used elsewhere to special-case
  behavior — the natural key for "is this a bouncer / portal".
- Velocity set, impulse, and **teleport of a simulating RigidBody** (`ctx.spatial.set_position` →
  `PhysicsServer*.body_set_state`) already exist and are symmetric across 2D/3D. No new actuation
  machinery is required.
- Only a center-to-center normal is available from the signal pipeline, but because reactors are MusicScene
  objects whose collider **shape and orientation we control**, the true surface normal is computed
  **analytically** — exact for circle/sphere and box/rect (the supported collider shapes) — with no
  `PhysicsServer` force-integration plumbing.

## Architecture

A new manager **`MSReactors`** (`addons/musicscene/physics/MSReactors.gd`) owns all reactor config
and behavior, keyed by object id:

- `configure_bouncer(obj, args)` / `configure_portal(obj, args)` — apply the OSC config commands.
- `on_contact(obj, other)` — called from the adapter when a body enters a reactor's Area; dispatches on
  `obj.type_hint` to `_bounce(obj, other)` or `_teleport(obj, other)`.
- Holds portal cooldown state (`_recent: { body_instance_id -> expiry_time }`).

Wiring:

| File | Change |
|---|---|
| `physics/MSReactors.gd` (new) | The manager: config + reflect/teleport logic. |
| `nodes/MSRoot.gd` | Instantiate `ctx.reactors = MSReactors.new(ctx)` alongside the other managers; give it a per-frame tick for cooldown expiry if needed. |
| `physics/MSPhysicsAdapter.gd` | In `_on_area_enter(other)` — the handler wired to an Area's `body_entered`/`area_entered`, so a rigid body entering a reactor routes here — after the existing `CollisionEvents.emit(...)`, call `ctx.reactors.on_contact(obj, other)`. (Reactors act **in addition to** normal event emission, so `on areaEnter …` bindings on a bouncer/portal still fire — that's how the example attaches sound.) |
| `core/MSFactory.gd` | Add `"bouncer"`, `"portal"` to `BUILTIN_TYPES`. |
| `core/MSSpatial2D.gd` / `MSSpatial3D.gd` | Add `"bouncer"`/`"portal"` cases to `create_primitive`, cloning the `"area"` case (Area2D/3D + default collider). |
| `core/MSRegistry.gd` | In `create_builtin`, after creating a `bouncer`/`portal`, auto-enable its area adapter (so signals are wired without a separate `physics enable area`). |
| `core/OscDispatcher.gd` | Add `"bouncer"` / `"portal"` cases to `_handle_scene_subsystem`, dispatching to `ctx.reactors`. |

### Object creation

```
/ms/scene/<id> new bouncer          # Area2D/3D + default collider, type_hint="bouncer", area adapter auto-enabled
/ms/scene/<id> new portal           # same, type_hint="portal"
/ms/scene/<id>/collider box 0.1 0.4 # override the shape as usual (rect/box/circle/sphere)
```

Auto-enabling the area on creation (a small, justified special-case for these intrinsically-Area types)
means `new bouncer` + `collider …` + config is enough; no separate `physics enable area`. The collider is
overridable via the standard `collider` command. Only real rigid bodies are acted on; an entering
area/zone is ignored.

## Bouncer

Config command:
```
/ms/scene/<id>/bouncer strength <s> gain <g> minSpeed <m>
```
Defaults `gain = 1.0` (energy-preserving mirror), `strength = 0.0` (opt-in outward kick), `minSpeed = 0.0`.
Options are parsed as case-insensitive key/value pairs (like event options); unknown keys are ignored.

On a body entering the bouncer's Area, `_bounce(obj, other)`:

1. Read `v = ctx.spatial.body_get_velocity(other)`.
2. Compute the outward **surface normal** `n` from the bouncer's shape + contact geometry:
   - **circle/sphere:** `n = (other_pos − bouncer_pos).normalized()` — exact.
   - **box/rect:** in the bouncer's local frame (via the node's inverse transform, so rotation is
     honored), the face the body is moving into — i.e. the box face whose outward world normal is most
     anti-parallel to the incoming velocity. Exact for a box.
   - Degenerate (`n` ~ 0, e.g. a dead-stop body at the center): fall back to `−v̂`, or straight up.
3. Reflect: `v_ref = v − 2 (v·n) n`.
4. Combine: `v_out = v_ref * gain + n * strength`. Guarantee an outward component: if `v_out·n <= 0`,
   add `n * (minSpeed + epsilon)`. Enforce `|v_out| >= minSpeed` along `n`.
5. `ctx.spatial.body_set_velocity(other, v_out.x, v_out.y, v_out.z, mode)`.

The normal derivation, reflection, and combination are pure vector math on the world-space `Vector2`/
`Vector3` returned by `ctx.spatial`, so the same code path serves 2D and 3D (the z terms are 0 in 2D).

## Portal

Config commands:
```
/ms/scene/<id>/portal link <id1> [<id2> …]    # directional targets (A→B does NOT imply B→A)
/ms/scene/<id>/portal unlink                    # clear this portal's targets
```
Targets are stored as an ordered `Array[String]` of object ids on the reactor config. Directional per the
chosen model: entering portal A teleports to a random one of **A's** listed targets.

On a body entering the portal's Area, `_teleport(obj, other)`:

1. If the body's instance id is in `_recent` (still within cooldown), **skip** (this is a just-arrived
   body; prevents ping-pong).
2. Resolve valid targets: for each linked id, look up the `MSObject` and its node; drop ids that no
   longer resolve. If none remain, skip (optionally emit a `bad_arguments`-style warning once).
3. Pick a uniform-random target `dst` (`randi() % n`).
4. Read the destination position `p = ctx.spatial.body_global_position(dst.node)` and the body velocity
   `v`. Teleport with a small exit **nudge** along travel direction:
   `ctx.spatial.set_position(other, p_norm + v̂ * nudge, mode)` (position expressed in the active
   coordinate space; `nudge` a small default in normalized units, e.g. `0.02`).
5. **Preserve velocity** — do not modify `other`'s velocity (momentum carries through).
6. Register the body in `_recent` with an expiry (short timeout, e.g. `0.25 s`), so the destination portal
   ignores it until it either leaves that portal's area or the timeout elapses.

Randomness uses runtime `randi()`; tests assert the body arrived at **one of** the linked targets
(deterministic on outcome set, not on which one).

## Data flow

```
rigid body enters reactor's Area
  → Godot area_entered/body_entered signal
  → MSPhysicsAdapter._on_area_enter(other)
      → CollisionEvents.emit(ctx, obj, "areaEnter", other)   # unchanged: `on areaEnter …` still fires
      → ctx.reactors.on_contact(obj, other)
          type_hint == "bouncer" → _bounce  → body_set_velocity(other, v_out)
          type_hint == "portal"  → _teleport → set_position(other, dst) (+ nudge, cooldown)
```

## Error handling / edge cases

- Non-rigid `other` (an area/zone/static body with no readable velocity) → reactor no-ops.
- Bouncer with a dead-stop body at its center → degenerate-normal fallback (kick straight out along
  `minSpeed`/up), never NaN.
- Portal with no (or all-unresolvable) targets → no-op.
- Portal ping-pong → the `_recent` cooldown set.
- A body simultaneously inside two reactors → each fires on its own `areaEnter`; last write wins that
  frame (acceptable).

## 2D + 3D

Everything goes through `ctx.spatial` (identical method surface in both backends) and world-space vector
math, so a single implementation serves both. Tests run once per `musicscene/space` value.

## Testing (headless `--script`, `SceneTree` pattern)

- `tools/test_bouncers.gd` (+ committed `.gd.uid`): create a bouncer (`new bouncer`, `collider circle`/
  `box`, `pos`), create a rigid ball with a known velocity heading into it, step a few frames, assert the
  ball's velocity was **reflected** (sign of the normal-component flipped) and **boosted** when
  `strength > 0`. A box-bouncer case asserts the correct face normal (e.g. a body moving `+x` into a
  vertical wall leaves with `−x`). `DONE pass=N fail=0`.
- `tools/test_portals.gd` (+ `.gd.uid`): portal A `link B`, drop a rigid ball into A, step frames, assert
  the ball's position jumped to B (within a tolerance) and its velocity was preserved; assert the cooldown
  prevents an immediate second teleport. A `link B C` case asserts the body ends at B **or** C. `DONE
  pass=N fail=0`.
- Both follow `tools/test_zones.gd`/`test_events.gd` verbatim (frame-gated `dispatch()` calls, `check()`,
  final `DONE pass=N fail=M`), and are wired into `.github/workflows/ci.yml` next to the other self-tests.

## Documentation

- **README.md** — add `bouncer` and `portal` to the object-types / command reference, with the
  `/ms/scene/<id>/bouncer …` and `/portal …` command grammar and a one-line behavior note each.
- **TUTORIAL.md** — a short worked section introducing bouncers and portals with `s()`-helper examples
  (create a bumper that kicks a ball; link two portals and watch a ball warp), and a pointer to the
  pinball example.
- **ADVANCED.md** — a "Collision reactors" section covering the mechanics + gotchas (Area-based/
  pass-through; analytical normal exact for circle/box; portal cooldown; reactors still fire `areaEnter`).
- **CHANGELOG.md** — `[0.12.0]` entry.
- **Version bump** to `0.12.0` (OscDispatcher ×3 + plugin.cfg).

## Deliverable — pinball SuperCollider example

`examples/supercollider/example_pinball.scd`: a self-contained, attractive **generative pinball table**
that needs no external synth (like the pachinko/chaos-globe examples — SuperCollider both drives the board
over OSC *and* synthesises every sound locally).

Uses **existing** elements — rigid ball(s) (spheres), static outer walls with `bounce` (restitution),
pins, gravity, planar physics (pinned to a plane for a table feel), colors/materials, a camera, and
pentatonic **sensor-zone targets** — plus the **new** elements: several **bouncer bumpers** (mirror + a
`strength` kick) scattered on the playfield, and a pair of **portals** that warp the ball across the
table. Each element carries an `on areaEnter`/`on collisionEnter` binding that emits a musical/sfx OSC
address; SuperCollider synthesises them:

- bumper hit → a bright metallic/percussive "ding" whose pitch/brightness tracks the ball speed;
- portal warp → a swept-noise "whoosh";
- scoring target → a pentatonic bell note (zone → pitch);
- ball drains at the bottom → a soft thunk, and the client re-launches the ball (endless generator).

Dimension: 3D with planar physics (reusing the pachinko approach) so the 0.10.0 lighting/materials make
it look good; the ball is launched with an initial impulse and the piece runs forever, an ever-evolving
soundscape. Its header documents the run steps and the "mind that no other instance holds 7401" caveat,
consistent with the other examples. Referenced from `TUTORIAL.md`'s example list. No player flippers (the
piece is autonomous/generative, not interactive).

## Scope / non-goals

- No player-controlled flippers/input (the example is autonomous).
- No true concave/mesh bouncer normals — analytical normals cover circle/sphere/box/rect, which are the
  supported collider shapes; arbitrary concave shapes are out of scope.
- No per-portal orientation remapping of velocity (velocity is preserved in world space, not rotated into
  the destination portal's frame).
- Bouncers/portals are pass-through Areas by design (they do not physically block); table containment uses
  ordinary static walls with `bounce`.

## Rollout

New branch `feat/collision-reactors` (off `main`). Version → 0.12.0. Docs updated. Merge/PR decided when
finishing the branch.
