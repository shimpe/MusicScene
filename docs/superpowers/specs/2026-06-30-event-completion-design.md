# gscore_osc — Event-System Completion (spec §19 remainder)

**Date:** 2026-06-30
**Status:** Approved design, ready for implementation planning
**Scope:** Close the remaining §19 gaps: `collisionStay` continuous-contact events, the `mode`
option (`queued` / `bundle` / `quantized`), and a functional `layer` event filter. **Out of scope
(by decision):** `positionEnter` / `positionExit` (redundant with area zones + `yAbove`/`yBelow`),
and `guido`/`pdf`/native-glyph notation backends.

---

## 1. What already works

- Events `collisionEnter/Exit`, `areaEnter/Exit`, `sleep`, `wake` (discrete, via `emit`);
  `velocityAbove/Below`, `yAbove/yBelow`, `areaStay` (continuous, via `check_continuous`).
- Event options `minIntensity`, `cooldown`, `maxRate` (single + per-body), `other` filter.
- Per-body throttle on `GScoreEventBinding` (`should_emit_other`/`mark_other`/`prune_others`).
- Other-centric data fields (`otherx/othery/...`). Canonical `/gscore/event/physics` mirror for
  discrete events.
- `OscServer.send_bundle(elements, timetag)` already exists (accepts `{address, args}` dicts).

The three additions below all build on this.

---

## 2. Feature A — `collisionStay`

The physical-contact analogue of `areaStay`: report each body currently **in contact** with this
object, every physics frame, throttled per body.

### 2.1 Registration
Already routes through the generic event-binding path:
`/gscore/scene/ball/on collisionStay /synth/sustain maxRate 30`. No dispatcher change.

### 2.2 Emission — `GScoreCollisionEvents.check_continuous`
Mirror the existing `areaStay` block, after it:

```
cb = obj.event_bindings.get("collisionStay")
if cb != null:
    active := {}
    for other in ctx.spatial.colliding_others(node):
        if not is_instance_valid(other): continue
        data = _build_data(ctx, obj, "collisionStay", other)
        oid = data["other"]
        active[oid] = true
        if cb.should_emit_other(data["intensity"], data["time"], oid, data["layer"]):
            cb.mark_other(oid, data["time"])
            ctx.emitter.emit(cb.target, cb.build_args(data), cb.mode, cb.quantize_grid)   # §3
    cb.prune_others(active)
```

(Uses `ctx.emitter` from Feature B, not `ctx.send_event` directly. The existing continuous and
areaStay sites switch to `ctx.emitter.emit(...)` too — see §3.4.)

### 2.3 Backend — `colliding_others(node)`
On both backends, mirroring `overlapping_others`:

```
# 2D
func colliding_others(node) -> Array:
    if node is RigidBody2D: return (node as RigidBody2D).get_colliding_bodies()
    return []
# 3D: RigidBody3D
```

Rigid bodies already enable `contact_monitor` + `max_contacts_reported = 8` in `make_body`, so
`get_colliding_bodies()` is populated. Non-rigid nodes yield `[]` (logged no-op effectively).

---

## 3. Feature B — `mode queued | bundle | quantized`

A new per-frame emission scheduler routes every physics/collision/area event by its binding's `mode`.

### 3.1 Binding additions — `GScoreEventBinding`
- `mode` already exists (default `"immediate"`, set via `set_option("mode", …)`).
- Add `var quantize_grid: float = 1.0` and `set_option("quantizegrid", v)` → `quantize_grid = max(v, 0.0)`.

### 3.2 New file — `events/GScoreEmissionScheduler.gd` (RefCounted)
```
var ctx
var _queued: Array = []     # {address, args}
var _bundle: Array = []     # {address, args}
var _quantized: Array = []  # {address, args, fire_beat}

func emit(address, args, mode, grid):
    match mode:
        "queued":    _queued.append({"address": address, "args": args})
        "bundle":    _bundle.append({"address": address, "args": args})
        "quantized": _quantized.append({"address": address, "args": args,
                                        "fire_beat": _next_grid(ctx.transport.beat, grid)})
        _:           ctx.send_event(address, args)   # "immediate" (and unknown) -> now

func flush(now_beat):
    for m in _queued: ctx.send_event(m.address, m.args)
    _queued.clear()
    if not _bundle.is_empty():
        ctx.server.send_bundle(_bundle); _bundle.clear()
    if not _quantized.is_empty():
        var keep := []
        for m in _quantized:
            if now_beat >= m.fire_beat: ctx.send_event(m.address, m.args)
            else: keep.append(m)
        _quantized = keep

func _next_grid(beat, grid) -> float:
    if grid <= 0.0: return beat            # no grid -> fire next flush
    return (floor(beat / grid) + 1.0) * grid   # strictly the next grid line
```

Notes:
- `immediate` bypasses all buffers (unchanged latency). Unknown mode falls back to immediate.
- `bundle` emits the frame's bundle-mode events as **one** OSC bundle via the existing
  `send_bundle`. `queued` sends them individually at frame end (order preserved).
- `quantized` holds until the transport beat crosses the next grid line; requires the transport to
  be advancing (documented). `quantizeGrid 0` degenerates to "fire on next flush".

### 3.3 Wiring — `GScoreRoot`
- `var emitter = null`; construct `emitter = GScoreEmissionScheduler.new(self)` after `transport`.
- In `_process(delta)`, after transport/timemapper updates: `emitter.flush(transport.beat)`.

### 3.4 Emission call sites switch to the scheduler
Replace the three `ctx.send_event(binding.target, …)` emission points with
`ctx.emitter.emit(binding.target, args, binding.mode, binding.quantize_grid)`:
1. `GScoreCollisionEvents.emit` (discrete enter/exit/sleep/wake) — line ~26.
2. `check_continuous` velocity/position loop — line ~50.
3. `check_continuous` `areaStay` (and new `collisionStay`) blocks.

The canonical `/gscore/event/physics` mirror in `emit` stays an **immediate** `ctx.send_event`
(diagnostic stream, not subject to the binding's mode). Signal→OSC and input bindings are unchanged
(immediate). `ctx.send_event` itself is untouched.

---

## 4. Feature C — functional `layer` filter

Make `other`-body layer filtering work (currently `data["layer"]` is always `""`).

### 4.1 Backend — `layer_names_for(node)`
On both backends:
```
# 2D (3D: CollisionObject3D)
func layer_names_for(node) -> PackedStringArray:
    var out := PackedStringArray()
    if node is CollisionObject2D:
        var bits: int = (node as CollisionObject2D).collision_layer
        for i in range(1, 33):
            if bits & (1 << (i - 1)):
                out.append(str(ctx.physics_world.layer_names.get(i, i)))   # name, else bit number
    return out
```
`physics_world.layer_names` maps layer number → name (set via `/gscore/physics/layer <n> <name>`).
Unnamed set bits resolve to their number as a string, so `layer 3` still matches.

### 4.2 Data — `_build_data`
Set `data["layer"]` to the **other** body's layers, comma-joined (empty when `other == null`):
```
"layer": ",".join(sp.layer_names_for(other)) if other != null else "",
```
(Usable verbatim as a payload field; `data["layer"]` replaces the current constant `""`.)

### 4.3 Filter — `GScoreEventBinding._passes_filters`
Change the layer check from equality to membership:
```
if layer_filter != "" and not (layer_filter in str(layer).split(",")):
    return false
```
So `layer percussion` matches a body whose layers include `percussion`, and `layer 3` matches bit 3.
The `other` filter is unchanged.

---

## 5. Behavior notes / edge cases

- `collisionStay` only fires while physics is simulating (continuous path), like every other
  continuous event; requires the object to be a rigid body (contact source).
- `mode` applies to physics/collision/area event bindings only. The `/gscore/event/physics` mirror,
  signal→OSC, and input events remain immediate.
- `quantized` with a stopped transport never fires (beat frozen) — documented.
- Layer membership: a body on multiple layers matches a filter naming any of them.

---

## 6. Verification

`tools/test_events.gd` (space-aware; run both spaces via `override.cfg`), mixing unit and integration
checks (replies go over UDP, so assert via scheduler/binding state):
- **Scheduler (unit):** `emit(...,"queued")`/`"bundle"` buffer then clear on `flush`; `emit(...,"quantized")`
  with a future `fire_beat` is withheld by `flush(beforeBeat)` and released by `flush(afterBeat)`;
  `_next_grid(2.3, 1)==3.0`, `_next_grid(2.0, 1)==3.0`.
- **collisionStay (integration):** static floor + rigid ball settling onto it under gravity; after N
  frames the `collisionStay` binding's `_last_emit_other` contains the floor's id; ball removed → pruned.
- **layer filter (unit/integration):** `layer_names_for` returns the configured name for a named bit and
  the number for an unnamed bit; `_passes_filters` matches by name and by number and rejects a
  non-member.

CI runs `test_events.gd`. Tutorial gains a short "Event modes & filters" note (mode/quantizeGrid,
collisionStay, layer). CHANGELOG `[0.5.0]`, version bump.

---

## 7. File-change summary

**New:** `addons/gscore_osc/events/GScoreEmissionScheduler.gd`, `tools/test_events.gd`.
**Modified:**
- `addons/gscore_osc/physics/GScoreCollisionEvents.gd` — `collisionStay` block; `layer` in `_build_data`;
  emission sites → `ctx.emitter.emit`.
- `addons/gscore_osc/events/GScoreEventBinding.gd` — `quantize_grid` + `quantizegrid` option; layer
  membership in `_passes_filters`.
- `addons/gscore_osc/core/GScoreSpatial2D.gd` + `GScoreSpatial3D.gd` — `colliding_others`,
  `layer_names_for`.
- `addons/gscore_osc/nodes/GScoreRoot.gd` — `ctx.emitter` + per-frame `flush`.
- `TUTORIAL.md`, `CHANGELOG.md`, `addons/gscore_osc/plugin.cfg`, `addons/gscore_osc/core/OscDispatcher.gd`
  (version strings), `.github/workflows/ci.yml`.

No `GScoreEvents`/`OscDispatcher` routing changes (`collisionStay`/options already route through the
generic binding path).
