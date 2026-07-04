# MusicScene — Sensors & Trigger Zones (spec §12)

**Date:** 2026-06-30
**Status:** Approved design, ready for implementation planning
**Scope:** Close the two gaps between the existing area/event system and spec §12: continuous
`areaStay` presence events (per-body throttled) and literal constant values in event payloads.

---

## 1. Goal

Make area "zones" fully first-class for musical use: besides the existing enter/exit triggers, a zone
should report **continuous presence** of each body inside it (rate-limited per body), and any event's
payload should be able to carry a **constant tag** (e.g. a form-section name):

```
/ms/scene/zoneA/on areaStay /zone/presence maxRate 20
/ms/scene/zoneA/payload areaStay self other otherx othery otherspeed
/ms/scene/zoneA/payload areaEnter self other =A
```

---

## 2. What already works (no changes)

The zone path in §12's example is already implemented and needs nothing:

- Area objects: `new rect` + `physics enable area` + `collider rect 0.4 0.3`
  (`MSSpatial*.make_body("area")`, `connect_collision` wires the area signals).
- `areaEnter` / `areaExit` → bound OSC target **and** canonical `/ms/event/physics`
  (`MSCollisionEvents.emit`), fired on body **or** area overlap.
- Event-binding options already cover `minIntensity`, `cooldown`, **`maxRate`**, `other <id|prefix*>`,
  `layer`, `mode` (`MSEventBinding`), and per-event `payload` field lists
  (`MSEvents.handle_on` / `handle_payload`).
- The OSC routing for `on areaStay …` and `payload areaStay …` **already works** through the generic
  event-binding path — no dispatcher/handler changes are needed. The only missing pieces are the
  *emitter* for `areaStay` and *literal* payload values.

---

## 3. Design principles

- **Reuse the continuous-event path.** `areaStay` is a per-frame continuous event, exactly like the
  existing `velocityAbove`/`yBelow` events handled in `MSCollisionEvents.check_continuous`. Extend
  that method rather than adding a new manager.
- **Dimension-agnostic.** Overlap enumeration and area detection go through `ctx.spatial`
  (`is_area` / `overlapping_others`), like every other physics primitive.
- **Per-body semantics.** A zone reports each contained body independently, each on its own `maxRate`
  clock — so two notes in the zone both stream at the full rate.
- **No canonical spam.** Continuous events (incl. `areaStay`) emit **only to their bound target**
  (already the convention for `velocityAbove` et al.), never to `/ms/event/physics`, so the
  per-body `maxRate` actually bounds traffic.

---

## 4. Feature A — `areaStay` continuous presence

### 4.1 Registration (already works)
`/ms/scene/zoneA/on areaStay /zone/presence maxRate 20` registers a `MSEventBinding` with
`event = "areaStay"`, `target = "/zone/presence"`, `max_rate = 20` — through the existing
`MSEvents.handle_on` path (`areaStay` is not an input event, so it lands in `event_bindings`).
`/ms/scene/zoneA/payload areaStay …` sets the binding's `payload` list (existing
`handle_payload`).

### 4.2 Emission (new) — `MSCollisionEvents.check_continuous`
`check_continuous(ctx, obj)` already runs once per physics frame per physics object (called from
`MSPhysicsAdapter.physics_step`, which runs while `ctx.physics_world.is_simulating()`). Add an
`areaStay` block:

```
b = obj.event_bindings.get("areaStay")
if b != null and ctx.spatial.is_area(obj.node):
    others = ctx.spatial.overlapping_others(obj.node)   # Array[Node]
    active := {}                                        # other_id -> true, for pruning
    for other in others:
        data = _build_data(ctx, obj, "areaStay", other) # other-centric fields populated (§6)
        oid  = data["other"]
        active[oid] = true
        if b.should_emit_other(oid, data["intensity"], data["time"], data["layer"]):
            b.mark_other(oid, data["time"])
            ctx.send_event(b.target, b.build_args(data))
    b.prune_others(active)                               # drop timers for bodies that left
```

`areaStay` is *not* added to `PHYSICS_EVENTS` (that list drives the discrete Godot-signal callbacks in
`emit`); it lives only in the continuous path.

### 4.3 Per-body throttle (new) — `MSEventBinding`
Add a per-other timer map and matching methods, factoring the shared filter checks out of the existing
`should_emit`:

```
var _last_emit_other: Dictionary = {}     # other_id -> last emit time (seconds)

func _passes_filters(intensity, other_id, layer) -> bool:
    # min_intensity, other_filter (_match), layer_filter — extracted from should_emit
    ...

func should_emit(intensity, now, other_id, layer) -> bool:
    if not _passes_filters(intensity, other_id, layer): return false
    # existing single-timer gap logic (cooldown / max_rate vs _last_emit)
    ...

func should_emit_other(intensity, now, other_id, layer) -> bool:   # arg order matches should_emit
    if not _passes_filters(intensity, other_id, layer): return false
    var gap := 0.0
    if cooldown > 0.0: gap = cooldown
    if max_rate > 0.0: gap = maxf(gap, 1.0 / max_rate)
    var last: float = _last_emit_other.get(other_id, -1.0)
    if gap > 0.0 and last >= 0.0 and (now - last) < gap: return false
    return true

func mark_other(other_id, now) -> void:
    _last_emit_other[other_id] = now

func prune_others(active: Dictionary) -> void:
    for k in _last_emit_other.keys():
        if not active.has(k): _last_emit_other.erase(k)
```

`should_emit`/`mark` (single-timer) keep serving enter/exit and the velocity/position events;
`should_emit_other`/`mark_other` serve `areaStay`. Re-running the existing checks through
`_passes_filters` is a behavior-preserving refactor.

### 4.4 Backend additions — `MSSpatial2D` / `MSSpatial3D`
```
func is_area(node) -> bool:
    return node is Area2D            # 3D: node is Area3D

func overlapping_others(node) -> Array:
    if node is Area2D:              # 3D: Area3D
        var out: Array = []
        out.append_array(node.get_overlapping_bodies())
        out.append_array(node.get_overlapping_areas())
        return out
    return []
```

(Godot updates the overlap lists each physics tick; reading them inside the physics step is fine for
presence — at worst one frame stale.)

---

## 5. Feature B — literal payload tags

In `MSEventBinding.build_args`, a payload token beginning with `'` or `=` is emitted as the
literal string after the marker; unmarked tokens resolve from the data dict as today (unknown → `0`,
so typos stay visible):

```
func build_args(data) -> Array:
    var fields = payload if not payload.is_empty() else DEFAULT_FIELDS
    var out: Array = []
    for f in fields:
        var s := str(f)
        if s.begins_with("'") or s.begins_with("="):
            out.append(s.substr(1))            # literal string
        else:
            var key := s.to_lower()
            out.append(data[key] if data.has(key) else 0)
    return out
```

So `payload areaEnter self other =A` (or `'A`) → `[zoneA, note17, "A"]`, matching §12's
`/form/section zoneA note17 A`. Constants live in `payload`, not in `on` (whose trailing tokens stay
option-pairs, avoiding the `A`-vs-`maxRate` ambiguity). Literals are always emitted as strings; for a
numeric constant, OSC string routing is normally sufficient.

This applies to every physics/area/continuous event payload (all flow through `build_args`). Input and
signal bindings use separate payload paths and are out of scope.

---

## 6. Data-dict additions — `MSCollisionEvents._build_data`

The current `x/y/speed/vx/vy` describe **self** (the zone). For a static zone these are constant/zero
— useless for presence. Add **other-centric** fields, populated whenever `other != null` (else `0`):

| field | meaning |
|---|---|
| `otherx`, `othery`, `otherz` | the other body's normalized position |
| `othervx`, `othervy`, `othervz` | the other body's normalized velocity |
| `otherspeed` | the other body's speed (velocity length) |

Computed via `ctx.spatial.point_to_norm(other_w, …)` and
`ctx.spatial.vector_to_norm(ctx.spatial.body_get_velocity(other), …)` (velocity is `ZERO` for
non-rigid others). These enrich collision-event payloads too, at no extra cost. The §12 areaStay
payload becomes `payload areaStay self other otherx othery otherspeed`; `x/y/speed` remain available
as the zone's own values.

---

## 7. Behavior notes / edge cases

- **Requires simulation.** `areaStay` runs in the continuous path, which executes while
  `ctx.physics_world.is_simulating()` (i.e. after `/ms/physics enable 1`), consistent with the
  other continuous events. Enter/exit (Godot signal callbacks) still fire independently. Documented.
- **Filters apply per body.** `other <id|prefix*>` / `layer` / `minIntensity` gate each contained body
  via `_passes_filters`; only matching bodies stream.
- **Cleanup.** `prune_others` drops a body's timer the first frame it is no longer overlapping, so the
  map stays bounded and a body that re-enters starts fresh.
- **`other` id resolution** reuses the existing rule (`registry.id_for_node(other)` else `node.name`).

---

## 8. Out of scope (v1)

- `collisionStay` (continuous contact). Symmetric to `areaStay` (enumerate contacts instead of
  overlaps); a trivial follow-up, not built now.
- Literal payloads for input/signal bindings (separate payload paths).
- Numeric-typed literal constants (literals emit as strings).

---

## 9. Verification

- **Headless self-test** `tools/test_zones.gd` (space-aware, run in both spaces via `override.cfg`):
  create an area zone with `areaStay`/`maxRate`; move a rigid body inside; step physics; assert
  `areaStay` fires for that body and that a too-fast second frame is throttled (per-body `maxRate`);
  add a second body and assert it gets its own stream; move a body out and assert its stream stops and
  its timer is pruned; verify a `=A` literal appears verbatim in an emitted payload; verify the
  `other*` data fields carry the moved body's position/velocity. (Replies go over UDP, so where direct
  assertion isn't possible, assert via the binding/overlap state and exercise the path.)
- **CI** runs `test_zones.gd` alongside the existing self-tests.
- **Tutorial** gains a "Sensors & trigger zones" section (enter/exit + `areaStay` + literal tags).
- **CHANGELOG** `[0.4.0]` (or `[0.3.1]`) entry; version bump.

---

## 10. File-change summary

**Modified:**
- `addons/musicscene/physics/MSCollisionEvents.gd` — `areaStay` block in `check_continuous`;
  other-centric fields in `_build_data`.
- `addons/musicscene/events/MSEventBinding.gd` — `_last_emit_other`, `should_emit_other`,
  `mark_other`, `prune_others`, `_passes_filters` refactor, literal handling in `build_args`.
- `addons/musicscene/core/MSSpatial2D.gd` + `MSSpatial3D.gd` — `is_area`, `overlapping_others`.
- `TUTORIAL.md`, `CHANGELOG.md`, `addons/musicscene/plugin.cfg` (version), `.github/workflows/ci.yml`.

**New:** `tools/test_zones.gd`.

No changes needed to `MSEvents` (routing) or `OscDispatcher` — `areaStay`/`payload` already route
through the generic event-binding path.
