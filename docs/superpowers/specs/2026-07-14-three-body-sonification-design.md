# Three-Body Chaos Sonification Example — Design

**Date:** 2026-07-14
**Status:** Approved (design)
**Deliverable:** one new SuperCollider example, `examples/supercollider/example_three_body.scd`

## Goal

A runnable SuperCollider example that simulates a chaotic gravitational three-body
system, visualises the three bodies live in a MusicScene (Godot) scene over OSC, and
turns their positions and speeds into a surprising, self-contained sonification. Every
run starts from a different initial configuration via **seeded** randomness; the seed is
printed and can be pinned to replay a run exactly.

No addon code changes, no version bump — this is a pure showcase of the existing OSC
surface, in the spirit of `example_chaos_globe.scd` (sclang drives the scene *and*
synthesises the audio; no external synth required).

## Architecture

Single file, two evaluable blocks, matching the sibling examples' conventions:

1. A build block `( s.waitForBoot({ ... }) )` — boots the server, defines the local
   SynthDefs, seeds and draws the initial configuration, builds the scene, and starts
   the integrator + sonification loop.
2. A `CLEANUP` block — stops the integrator Routine, frees synths and OSCdefs.

sclang is the single brain: it owns the physics integration, streams body positions to
Godot over OSC, and produces all sound locally. Godot is a live display only.

### Components

- **Seed & configuration builder** — picks/prints the seed, seeds the RNG, draws masses,
  positions and velocities, and normalises to the centre-of-mass frame.
- **Integrator** — velocity-Verlet stepping of softened mutual gravity plus a weak
  central well; runs as a Routine at a fixed tick rate with several substeps per tick.
- **Scene driver** — one-time scene build (reset + three coloured circles), then a
  per-tick `pos` (and subtle `opacity`/`scale`) update per body.
- **Sonifier** — three sustained per-body voices updated each tick, a one-shot
  "whoosh" gesture fired on near-collisions, and a master reverb whose mix breathes with
  the system's kinetic energy. All SynthDefs are defined in-file.

## 1. Seeded start (different every run, reproducible on demand)

- Environment variable `~fixedSeed`:
  - `nil` (default) → derive a fresh seed from the wall clock:
    `Date.getDate.rawSeconds.asInteger`. This differs on every run, even repeated
    evaluations within one sclang session.
  - non-nil → use that integer verbatim (replay).
- Print exactly one clear line, e.g.:
  `three-body seed: <N>   (set ~fixedSeed = <N> and re-run to replay)`.
- `thisThread.randSeed = seed;` **before** drawing any random config, so the whole
  configuration is a deterministic function of the seed.
- Draw the configuration (all in the seeded setup thread):
  - 3 masses `rrand(0.7, 1.4)`.
  - 3 positions in a disc of radius ~0.35 around the origin.
  - 3 velocities: a tangential component (to encourage orbiting rather than a straight
    infall) plus a small random jitter.
  - Subtract the centre-of-mass **position** (so the system is centred in-frame) and the
    centre-of-mass **velocity** (so there is no net drift off-screen).
  - 3 distinct colours (warm, e.g. red / green / blue-violet) so the bodies are
    tellable apart.

## 2. Physics — integrated in sclang

Godot's physics only applies a uniform gravity *field*, not mutual N-body attraction, so
the dynamics are integrated in sclang and the bodies are driven kinematically in Godot
(no Godot physics enabled on them).

- **Integrator:** velocity-Verlet, ~60 Hz tick, ~8 substeps per tick with a small `dt`.
  Verlet is symplectic-ish and energy-conserving, so the system neither heats up nor
  winds down — no damping needed, motion is genuinely perpetual, and it stays stable
  through close passes.
- **Softened mutual gravity:** for each pair, force magnitude `G * mi * mj / (r^2 + eps^2)`
  along the separation. The softening `eps` keeps hard slingshots finite (no singularity,
  no NaN).
- **Gentle central well:** an additional `-k * pos` restoring force on each body with a
  small `k`. This is the "bounded (perpetual)" choice: mutual gravity still dominates
  locally so the motion stays chaotic, but nothing ever escapes the frame.

Constants (`G`, `eps`, `k`, `dt`, substeps, tick rate) are named at the top of the block
and tuned so the motion is lively, on-screen, and never settles.

## 3. Visuals (MusicScene over OSC)

- Paced OSC send helper (`~snd`, ~0.03 s between setup messages) exactly like
  `example_chaos_globe.scd`.
- Build phase: `/ms/scene reset`, then for each body `i`:
  - `/ms/scene/body<i> new circle`
  - `/ms/scene/body<i> color r g b` (its distinct colour)
  - `/ms/scene/body<i> size w h` (a small disc)
  - **no** `/physics enable` — sclang owns the motion.
- Per tick: `/ms/scene/body<i> pos x y 0` (z = 0, so the example works in a 2D **or** 3D
  MusicScene project). Speed subtly modulates each body's `opacity` (and/or `scale`) so
  fast bodies flare.
- `OSCdef(\msError, ...)` on `/ms/error` to surface any MusicScene-side mistakes, as in
  `example_control_surface.scd`.

Trails are intentionally out of scope (YAGNI) — the `line` primitive is a static segment
and real trails would need per-frame segment spawning. A note may mention it as a
possible extension.

## 4. Sonification — the "surprise" (self-contained)

A perpetual, never-repeating ambient drone that makes the chaos audible.

- **One sustained voice per body** (persistent Synth, `.set` each tick):
  - **Pitch** = the body's distance from centre, quantised to a warm consonant scale
    (C lydian) so the result is musical rather than noise. (Mapping is a single
    function so the scale/mood is trivially swappable.)
  - **Pan** = the body's x-position → the listener hears each body swing across the
    stereo field in lockstep with the picture.
  - **Amplitude + lowpass brightness** = the body's speed → orbits breathe and
    slingshots surge.
- **Gravitational "whoosh" on near-collisions** — the payoff. Each tick, watch the three
  pairwise distances; when a pair drops below a threshold (a slingshot / near-collision),
  fire a one-shot pitch-swoop gesture whose **intensity is proportional to the closing
  speed**, panned to the encounter's location, with a short **per-pair cooldown** so a
  single slow pass does not machine-gun. Because the dynamics are chaotic, these
  encounters land at unpredictable times and never repeat.
- **Master glue:** a light reverb whose mix (or a gentle drive) breathes with the
  system's total kinetic energy, so the whole texture swells with the system's activity.
- All SynthDefs (`\bodyVoice`, `\whoosh`, and any master effect) are defined in-file;
  no external synth is used.

## 5. Cleanup & conventions

- `CmdPeriod.doOnce({ ... })` to auto-clean on Ctrl-. (stop Routine, free synths + OSCdefs).
- Explicit `CLEANUP` block at the bottom (cursor-in, evaluate) that stops the integrator
  Routine, `s.freeAll`, frees OSCdefs, and optionally freezes/clears the scene.
- Header doc comment in the style of the other examples: the three-body model and the
  bounded-well trick, the seed/replay instructions, the sonification mapping, the
  requirements, and numbered usage steps.

## 6. Requirements

- A running MusicScene instance (exactly one), 2D or 3D — positions are planar (z = 0),
  so either project space works.
- SuperCollider with a booted audio server (the build block boots it).
- No external synth, no Verovio/LilyPond, no MSScore — this example uses only the raw
  scene OSC surface.

## 7. Verification

- Matches repo convention: none of the physics examples (`example_chaos_globe.scd`,
  `example_pinball.scd`, `example_pendulum_joints.scd`, …) are in CI — they need a live
  audio server and a running Godot, and `s.waitForBoot` blocks headless runs.
- Verification for this example: careful logic review, plus a headless sclang
  **parse-only** sanity check of the file if one is available on this box. The
  perceptual check (does it look and sound right) is manual.
- **Default: no automated test.** If an automated test of the integrator is wanted, the
  Verlet step + force computation would be factored into a pure function and covered by a
  small pytest that boots sclang (reusing the msscore `_run` pattern) and asserts the
  energy stays bounded and finite over N steps. This is out of scope unless requested.

## 8. Out of scope

- Trails / motion history.
- Reproducibility of the *audio server* RNG (only the *configuration* is seeded; the
  synths are deterministic given the configuration).
- Any addon/Godot code change, version bump, or CHANGELOG entry.
- More than three bodies, collisions/merging, or a UI to edit the configuration.

## Files

- **Create:** `examples/supercollider/example_three_body.scd`
- **Modify:** `TUTORIAL.md` — add a one-line bullet to the "creative examples" list
  (the physics-driven SuperCollider examples around lines 1336–1369, alongside
  `example_chaos_globe.scd`, `example_pinball.scd`, etc.).
- README.md needs no entry — its example mentions are feature-specific (MSScore / lyrics /
  LilyPond), not a physics-examples index.
