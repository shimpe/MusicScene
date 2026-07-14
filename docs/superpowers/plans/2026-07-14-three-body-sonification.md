# Three-Body Chaos Sonification Example — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one runnable SuperCollider example that simulates a seeded, bounded chaotic three-body gravitational system, streams the three bodies to a MusicScene scene over OSC, and sonifies their positions and speeds.

**Architecture:** A single `.scd` file, in the style of `examples/supercollider/example_chaos_globe.scd`: sclang integrates the physics itself (Godot only does uniform-field gravity, not mutual N-body), drives three coloured circles over OSC, and synthesises all sound locally (no external synth). No addon code changes, no version bump.

**Tech Stack:** SuperCollider (sclang + scsynth), the MusicScene OSC scene surface (`/ms/scene/...`). Verification is a headless sclang *compile* check (parses without executing, so it can't hang on `waitForBoot`).

---

## Spec

Design/spec: `docs/superpowers/specs/2026-07-14-three-body-sonification-design.md`. Read it for the rationale; this plan is self-contained for implementation.

## File Structure

- **Create** `examples/supercollider/example_three_body.scd` — the whole example (build block + cleanup block). One artifact, one responsibility.
- **Create** `C:\Scripts\Temp\claude\D--Projects-MusicScene\a1fb2dce-fd6e-4517-ab85-d0c51d4eed41\scratchpad\three_body_compile_check.scd` — an ephemeral headless syntax gate (NOT committed; scratchpad only). Reused as the verify step.
- **Modify** `TUTORIAL.md` — add one bullet to the physics-driven SuperCollider examples list (~lines 1336–1369).

## Key SuperCollider constraints (the implementer MUST respect these)

- **Var-order rule:** every `var` declaration must be at the TOP of its enclosing function `{ ... }`, before any statement. This bit us before (a mid-function `var` is a parse error → the compile check fails). Each `Array.fill`/`.do`/`if`/`Routine` closure that needs locals declares them first.
- **Arrays are vectors:** `[a,b] + [c,d]`, `[a,b] * s`, `[a,b] / s` are element-wise in SC — no helper functions needed. `hypot(x, y)` == `x.hypot(y)`.
- **`~snd` (paced send) waits** and may only be called inside a Routine. The tight simulation loop uses `~engine.sendMsg(...)` directly (no wait).
- **Node order for the effect bus:** the `\master` synth must sit at the tail; the voices and whooshes at the head, so sources render before the master reads the bus.

---

## Task 1: Headless compile-check harness (the verify gate, built first)

Build the verification tool before the example, and prove it actually catches errors.

**Files:**
- Create: `C:\Scripts\Temp\claude\D--Projects-MusicScene\a1fb2dce-fd6e-4517-ab85-d0c51d4eed41\scratchpad\three_body_compile_check.scd`

- [ ] **Step 1: Write the harness**

`thisProcess.interpreter.compile(codeString)` compiles the code to a `FunctionDef` and returns it, or returns `nil` on a syntax/var-order error. It does NOT execute the code, so the example's `s.waitForBoot` never runs — no server, no Godot, no hang.

Write this file:

```supercollider
// Headless syntax gate for example_three_body.scd — compiles WITHOUT executing,
// so it never boots the server or hangs. Prints OK/FAIL and exits.
(
var path = "D:/Projects/MusicScene/examples/supercollider/example_three_body.scd";
var code, fn;
code = File.readAllString(path);
if(code.isNil, {
    "THREE-BODY-COMPILE-FAIL (file not found)".postln;
    0.exit;
});
fn = thisProcess.interpreter.compile(code);
fn.isNil.if(
    { "THREE-BODY-COMPILE-FAIL".postln; },
    { "THREE-BODY-COMPILE-OK".postln; }
);
0.exit;
)
```

- [ ] **Step 2: Prove the gate REJECTS broken code (test the tester)**

The example file does not exist yet, so the harness should currently report the not-found FAIL. Run it and confirm it fails cleanly (does not hang):

PowerShell:
```powershell
& "C:\Program Files\SuperCollider-3.14.1\sclang.exe" "C:\Scripts\Temp\claude\D--Projects-MusicScene\a1fb2dce-fd6e-4517-ab85-d0c51d4eed41\scratchpad\three_body_compile_check.scd"
```
Expected: stdout contains `THREE-BODY-COMPILE-FAIL (file not found)`, and sclang exits on its own (the `0.exit`). If it does not exit within ~30 s, something is wrong — stop and investigate (do NOT leave a hung sclang; kill it with `Get-Process sclang | Stop-Process -Force`).

- [ ] **Step 3: Prove the gate ACCEPTS good code and CATCHES a var-order error**

Temporarily create two probe files in the scratchpad to confirm both verdicts, then delete them:

Good probe `probe_ok.scd`:
```supercollider
( var a = 1; a + 1; )
```
Bad probe `probe_bad.scd` (a `var` after a statement — the exact class of error we fear):
```supercollider
( 1 + 1; var a = 2; a; )
```
Point a copy of the harness at each (or edit `path`) and confirm `...OK` for the good probe and `...FAIL` for the bad one. Delete the probes afterward. No commit (scratchpad only).

---

## Task 2: The example file

Write the complete example, then gate it with the harness.

**Files:**
- Create: `examples/supercollider/example_three_body.scd`

- [ ] **Step 1: Write the file**

Write EXACTLY this content:

```supercollider
// =============================================================================
// Three-body chaos — a seeded gravitational three-body system, sonified.
//
// Three bodies attract each other under (softened) Newtonian gravity. sclang
// integrates the motion itself — Godot's physics only does a uniform gravity
// FIELD, not mutual N-body attraction — and streams each body's position to a
// circle in the MusicScene scene over OSC. The same positions and speeds drive
// a self-contained sonification (no external synth): sclang is the whole show.
//
// CHAOS, BUT BOUNDED.  A pure three-body system usually slingshots one body out
// to infinity and then it's boring. A weak central "well" (a gentle pull toward
// the middle) keeps all three on-screen and chaotic FOREVER, while their mutual
// gravity still dominates up close, so the motion never repeats and never settles.
//
// A DIFFERENT START EVERY RUN, REPRODUCIBLE ON DEMAND.  The initial masses,
// positions and velocities are drawn from a SEEDED random generator. The seed is
// printed at the top of every run. To replay a run exactly, set ~fixedSeed to the
// printed value before evaluating the block:
//
//     ~fixedSeed = 123456;   // then run the block below
//
// Leave ~fixedSeed = nil (the default) for a fresh, different system each time.
//
// THE SOUND.  Each body sings one sustained voice: its distance from the centre
// picks a pitch (quantised to C lydian so it stays musical), its x-position pans
// it across the stereo field (you HEAR it swing as you SEE it move), and its
// speed sets loudness and brightness (orbits breathe, slingshots surge). When two
// bodies nearly collide — a chaotic slingshot — a "whoosh" fires, louder and
// brighter the faster they pass. A master reverb breathes with the system's total
// energy. Because the dynamics are chaotic, these encounters never repeat.
//
// REQUIRES one running MusicScene instance (2D or 3D — positions are planar, z=0).
// MusicScene listens on 7400 and replies on 7401.
//
// USAGE:
//   1. Optionally set ~fixedSeed (see above); leave nil for a fresh run.
//   2. Run the Godot project with MusicScene (exactly ONE instance).
//   3. Put the cursor in the big ( ... ) block below and press Ctrl+Enter.
//   4. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

    // ---- local synths (no external synth needed) ---------------------------

    // one sustained voice per body: a lagged saw+octave through a lowpass, so
    // pitch / brightness / pan glide smoothly as the body moves.
    SynthDef(\bodyVoice, { |out = 0, freq = 220, amp = 0.0, cutoff = 1500, pan = 0, gate = 1|
        var f, sig, env;
        f   = Lag.kr(freq, 0.25);
        sig = Saw.ar(f) + SinOsc.ar(f * 2, 0, 0.3);
        env = EnvGen.kr(Env.asr(0.6, 1, 1.5), gate, doneAction: 2);
        sig = RLPF.ar(sig, Lag.kr(cutoff, 0.15).clip(100, 18000), 0.4);
        sig = sig * Lag.kr(amp, 0.2) * env;
        Out.ar(out, Pan2.ar(sig, Lag.kr(pan, 0.2)));
    }).add;

    // a one-shot "whoosh" for a near-collision slingshot: a filtered-noise sweep
    // plus a sine glide; intensity is set by the pass speed at trigger time.
    SynthDef(\whoosh, { |out = 0, amp = 0.3, pan = 0, dur = 0.6, f0 = 300, f1 = 2000|
        var env, sweep, sig;
        env   = EnvGen.kr(Env.perc(0.02, dur, 1, -2), doneAction: 2);
        sweep = XLine.kr(f0, f1, dur * 0.6);
        sig   = (BPF.ar(WhiteNoise.ar, sweep, 0.3) * 6) + SinOsc.ar(sweep, 0, 0.3);
        sig   = sig * env * amp;
        Out.ar(out, Pan2.ar(sig, pan));
    }).add;

    // master: sum the voices + whooshes off a private bus, add a reverb whose
    // mix "breathes" with the system's kinetic energy, play to the speakers.
    SynthDef(\master, { |in = 0, mix = 0.3|
        var wet, sig;
        wet = In.ar(in, 2);
        sig = wet + (FreeVerb.ar(wet, mix.clip(0, 1), 0.9, 0.5) * 0.6);
        Out.ar(0, sig);
    }).add;

    s.sync;

    // ---- seeded initial configuration --------------------------------------

    // pick the seed: ~fixedSeed if set, else a fresh one drawn from the ambient
    // (time-seeded) RNG — so it differs every run, even repeated runs in one
    // session. Reseeding with it makes the whole configuration a deterministic
    // function of the printed seed.
    ~seed = ~fixedSeed ?? { 1000000.rand };
    thisThread.randSeed = ~seed;
    ("three-body seed: " ++ ~seed ++ "   (set ~fixedSeed = " ++ ~seed ++ " and re-run to replay)").postln;

    // three bodies: random masses, positions in a disc, tangential + jittered speeds.
    ~mass = Array.fill(3, { rrand(0.7, 1.4) });
    ~pos  = Array.fill(3, {
        var ang, rad;
        ang = rrand(0, 2pi);
        rad = rrand(0.12, 0.32);
        [rad * cos(ang), rad * sin(ang)];
    });
    ~vel = Array.fill(3, { |i|
        var p, tmag, tang, speed;
        p     = ~pos[i];
        tmag  = hypot(p[0], p[1]);
        tang  = [p[1].neg / tmag, p[0] / tmag];      // unit tangential direction
        speed = rrand(0.15, 0.40);
        (tang * speed) + [rrand(-0.08, 0.08), rrand(-0.08, 0.08)];
    });

    // shift into the centre-of-mass frame: no net drift, centred in view.
    {
        var mtot, compos, comvel;
        mtot   = ~mass.sum;
        compos = [0.0, 0.0];
        comvel = [0.0, 0.0];
        3.do { |i|
            compos = compos + (~pos[i] * ~mass[i]);
            comvel = comvel + (~vel[i] * ~mass[i]);
        };
        compos = compos / mtot;
        comvel = comvel / mtot;
        3.do { |i| ~pos[i] = ~pos[i] - compos; ~vel[i] = ~vel[i] - comvel; };
    }.value;

    ("  masses: " ++ ~mass.round(0.001)).postln;
    ("  start:  " ++ ~pos.collect(_.round(0.001))).postln;

    // ---- physics constants + integrator (velocity-Verlet) ------------------

    ~G       = 0.06;     // gravitational strength (mutual attraction)
    ~eps2    = 0.02;     // softening^2: keeps close passes finite (no singularity)
    ~k       = 0.6;      // central-well strength: bounds the system on-screen
    ~tickHz  = 60;       // scene / sound update rate
    ~sub     = 8;        // physics substeps per tick (stable through close passes)
    ~rmax    = 0.6;      // radius that maps to the lowest pitch
    ~scale   = [60, 62, 64, 66, 67, 69, 71, 72, 74, 76, 78, 79, 81];   // C lydian, ~2 octaves
    ~pairs   = [[0, 1], [0, 2], [1, 2]];
    ~encDist = 0.14;     // "near-collision" distance that fires a whoosh
    ~encCool = 0.5;      // per-pair whoosh cooldown (s)
    ~cool    = [0.0, 0.0, 0.0];

    // accelerations for a set of positions P: softened mutual gravity + central well.
    ~accel = { |P|
        var acc;
        acc = Array.fill(3, { [0.0, 0.0] });
        3.do { |i|
            3.do { |j|
                if(i != j) {
                    var d, r2, inv;
                    d   = P[j] - P[i];
                    r2  = (d[0] * d[0]) + (d[1] * d[1]);
                    inv = (~G * ~mass[j]) / ((r2 + ~eps2) ** 1.5);
                    acc[i] = acc[i] + (d * inv);
                };
            };
            acc[i] = acc[i] + (P[i] * ~k.neg);        // central well
        };
        acc;
    };

    // one velocity-Verlet substep of length dt.
    ~step = { |dt|
        var a0, a1;
        a0 = ~accel.(~pos);
        3.do { |i| ~pos[i] = ~pos[i] + (~vel[i] * dt) + (a0[i] * (0.5 * dt * dt)) };
        a1 = ~accel.(~pos);
        3.do { |i| ~vel[i] = ~vel[i] + ((a0[i] + a1[i]) * (0.5 * dt)) };
    };

    // total kinetic energy (drives the master reverb "breath").
    ~ke = {
        var e = 0.0;
        3.do { |i| e = e + (0.5 * ~mass[i] * ((~vel[i][0].squared) + (~vel[i][1].squared))) };
        e;
    };

    // ---- OSC out + error listener ------------------------------------------

    ~engine = NetAddr("127.0.0.1", 7400);
    ~snd = { |... m| ~engine.sendMsg(*m); 0.03.wait; };      // paced setup send (Routine-only)

    if(thisProcess.openUDPPort(7401),
        { "three-body: listening for MusicScene replies on 7401".postln; },
        { "three-body: UDP 7401 already open — continuing".postln; }
    );
    OSCdef(\msError, { |msg| ("MusicScene error: " ++ msg[1..]).warn }, '/ms/error', recvPort: 7401);

    // ---- audio routing -----------------------------------------------------

    ~fxbus  = Bus.audio(s, 2);
    ~master = Synth(\master, [\in, ~fxbus, \mix, 0.3], addAction: \addToTail);
    ~voices = Array.fill(3, { Synth(\bodyVoice, [\out, ~fxbus, \amp, 0.0]) });

    // ---- the simulation + sonification loop --------------------------------

    ~running = true;
    ~loop = Routine({
        var dt = 1 / ~tickHz;
        while({ ~running }, {
            ~sub.do { ~step.(dt / ~sub) };            // advance the physics

            // per-body: drive the scene circle and its voice
            3.do { |i|
                var p, v, r, spd, deg, freq, amp, cut, pan;
                p    = ~pos[i];
                v    = ~vel[i];
                r    = hypot(p[0], p[1]);
                spd  = hypot(v[0], v[1]);
                deg  = ((1 - (r / ~rmax)).clip(0, 1) * (~scale.size - 1)).round.asInteger;
                freq = ~scale[deg].midicps;
                amp  = (0.04 + (spd * 0.18)).clip(0.03, 0.28);
                cut  = (400 + (spd * 3500)).clip(300, 7000);
                pan  = p[0].clip(-1, 1);
                ~voices[i].set(\freq, freq, \amp, amp, \cutoff, cut, \pan, pan);
                ~engine.sendMsg("/ms/scene/body" ++ i, "pos", p[0], p[1], 0.0);
                ~engine.sendMsg("/ms/scene/body" ++ i, "opacity", (0.5 + spd).clip(0.4, 1.0));
            };

            // per-pair: fire a whoosh on a close, approaching pass
            ~pairs.do { |pr, pi|
                var i, j, sep, r, relv, closing, intensity, mx;
                i   = pr[0];
                j   = pr[1];
                sep = ~pos[i] - ~pos[j];
                r   = hypot(sep[0], sep[1]);
                relv = ~vel[i] - ~vel[j];
                closing = ((relv[0] * sep[0]) + (relv[1] * sep[1])) / max(r, 1e-6);
                ~cool[pi] = (~cool[pi] - dt).max(0);
                if((r < ~encDist) and: { closing < 0 } and: { ~cool[pi] <= 0 }, {
                    intensity = closing.abs;
                    mx = (~pos[i][0] + ~pos[j][0]) * 0.5;
                    Synth(\whoosh, [
                        \out, ~fxbus,
                        \amp, (0.1 + (intensity * 0.5)).clip(0.1, 0.6),
                        \pan, mx.clip(-1, 1),
                        \dur, 0.6, \f0, 300,
                        \f1, (800 + (intensity * 2500)).clip(800, 5000)
                    ]);
                    ~cool[pi] = ~encCool;
                });
            };

            // master reverb breathes with the system's kinetic energy
            ~master.set(\mix, ~ke.value.linlin(0.02, 0.5, 0.12, 0.5).clip(0.1, 0.6));

            dt.wait;
        });
    });

    // ---- build the scene, then start the loop ------------------------------

    ~cols = [[0.95, 0.40, 0.35], [0.45, 0.90, 0.50], [0.55, 0.60, 1.00]];
    ~build = Routine({
        ~snd.("/ms/scene", "reset");
        3.do { |i|
            ~snd.("/ms/scene/body" ++ i, "new", "circle");
            ~snd.("/ms/scene/body" ++ i, "color", ~cols[i][0], ~cols[i][1], ~cols[i][2]);
            ~snd.("/ms/scene/body" ++ i, "size", 0.08, 0.08);
            ~snd.("/ms/scene/body" ++ i, "pos", ~pos[i][0], ~pos[i][1], 0.0);
        };
        "".postln;
        "Three-body system built — bounded, chaotic, never repeating.".postln;
        "notes stream below; evaluate the CLEANUP block to stop.".postln;
        "".postln;
        ~loop.play;
    });

    CmdPeriod.doOnce({ ~running = false; s.freeAll; OSCdef(\msError).free; });
    ~build.play;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
~running = false;
~loop !? { ~loop.stop };
~build !? { ~build.stop };
OSCdef(\msError).free;
s.freeAll;
~fxbus !? { ~fxbus.free };
"three-body stopped.".postln;
)
```

- [ ] **Step 2: Compile-check the file (the gate)**

Point the harness at the real file (it already targets that path). Run:

PowerShell:
```powershell
& "C:\Program Files\SuperCollider-3.14.1\sclang.exe" "C:\Scripts\Temp\claude\D--Projects-MusicScene\a1fb2dce-fd6e-4517-ab85-d0c51d4eed41\scratchpad\three_body_compile_check.scd"
```
Expected: stdout contains `THREE-BODY-COMPILE-OK` and no `ERROR:` lines; sclang exits on its own. If it prints `THREE-BODY-COMPILE-FAIL` or an `ERROR:`, read the parse error (usually a mis-placed `var`), fix the file, and re-run until OK. Never leave a hung sclang — if one lingers, `Get-Process sclang | Stop-Process -Force`.

- [ ] **Step 3: Commit**

```powershell
git add examples/supercollider/example_three_body.scd
git commit -m "feat(examples): seeded three-body chaos sonification (SuperCollider)"
```

Commit message body to include:
```
Seeded, bounded three-body gravity integrated in sclang (velocity-Verlet,
softened mutual gravity + gentle central well), streamed to three circles in
a MusicScene scene over OSC. Sonified self-contained: one voice per body
(distance->pitch in C lydian, x->pan, speed->amp/brightness) with slingshot
"whoosh" gestures at chaotic near-collisions and a KE-breathing master reverb.
Seed is printed and settable via ~fixedSeed for exact replay.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## Task 3: List the example in TUTORIAL.md

**Files:**
- Modify: `TUTORIAL.md` (the physics-driven SuperCollider examples list, ~lines 1336–1369)

- [ ] **Step 1: Find the anchor**

Run:
```powershell
Select-String -Path TUTORIAL.md -Pattern "Generative pinball \(SuperCollider\)"
```
Expected: one match near line 1356 (the `example_pinball.scd` bullet). This is the physics-examples list.

- [ ] **Step 2: Add the bullet**

Immediately AFTER the "Generative pinball (SuperCollider)" bullet (the whole bullet, which spans two lines through its trailing sentence), insert a new bullet. Match the surrounding bullet style exactly (a `- **Name (SuperCollider):**` lead-in and backticked path). Insert:

```markdown
- **Three-body chaos (SuperCollider):** `examples/supercollider/example_three_body.scd` — a seeded,
  bounded three-body gravitational system. sclang integrates the mutual gravity itself (a velocity-Verlet
  step, softened so close passes stay finite, plus a gentle central well that keeps all three on-screen and
  chaotic forever), streams the bodies to three coloured circles over OSC, and sonifies them self-contained:
  one voice per body (distance → pitch in C lydian, x-position → stereo pan, speed → loudness/brightness),
  a slingshot "whoosh" at each chaotic near-collision, and a reverb that breathes with the system's energy.
  Every run starts differently; the printed seed replays it exactly (`~fixedSeed = <n>`).
```

- [ ] **Step 3: Verify the edit**

```powershell
Select-String -Path TUTORIAL.md -Pattern "example_three_body.scd"
```
Expected: one match, inside the physics-examples list, directly after the pinball bullet.

- [ ] **Step 4: Re-run the compile gate (confirms the example file is untouched and still valid)**

```powershell
& "C:\Program Files\SuperCollider-3.14.1\sclang.exe" "C:\Scripts\Temp\claude\D--Projects-MusicScene\a1fb2dce-fd6e-4517-ab85-d0c51d4eed41\scratchpad\three_body_compile_check.scd"
```
Expected: `THREE-BODY-COMPILE-OK`.

- [ ] **Step 5: Commit**

```powershell
git add TUTORIAL.md
git commit -m "docs(tutorial): list the three-body chaos SuperCollider example"
```

Commit body:
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```

---

## Manual verification (after all tasks — needs a live server + Godot, so it is NOT automated)

The compile gate proves the file parses; these confirm it behaves. The implementer runs the compile gate; the human runs the perceptual checks.

1. **Reproducibility (the key requirement).** In SuperCollider, evaluate `~fixedSeed = 42;` then run the build block. Note the printed `three-body seed: 42`, the `masses:` and `start:` lines. Evaluate the CLEANUP block, then run it again with `~fixedSeed = 42` — the `masses:` and `start:` lines must be identical. Then evaluate `~fixedSeed = nil;` and run twice — the seed (and config) must differ each time.
2. **Visuals.** With one MusicScene instance running (2D or 3D), the build block spawns three coloured circles that orbit and swing chaotically without drifting off-screen or freezing.
3. **Sound.** Three sustained voices pan with the bodies; near-collisions fire audible whooshes; the texture never exactly repeats. CLEANUP silences everything.

## Notes / out of scope

- No CI: like every other physics example here, this needs a live audio server + Godot and cannot run headless (`waitForBoot` blocks). The compile gate is the only automated check, and it is local (the scratchpad harness is not committed; CI has no SuperCollider).
- No trails, no >3 bodies, no addon/Godot code change, no version bump, no CHANGELOG entry.
- README.md needs no entry (its example mentions are feature-specific: MSScore / lyrics / LilyPond).

---

## Implementation notes (what actually shipped)

The code blocks above are the plan; these are the refinements made during inline execution. The shipped file `examples/supercollider/example_three_body.scd` is the source of truth.

**SuperCollider identifier fixes (caught by the compile gate).** SC reserves uppercase-initial identifiers for class names and `pi` for the constant π, so three names in the plan draft were illegal:
- `~G` → `~grav` (env/var names must start lowercase).
- the `~accel` argument `P` → `positions` (same rule for locals).
- the pair-loop index `pi` → `pidx` (`pi` is the π constant).

**Verification (both server-free, so neither can hang on `waitForBoot`).**
- *Compile gate* `three_body_compile_check.scd`: reads the file, splits it into top-level `( … )` blocks, and `String:compile`s each (compiles WITHOUT executing). Result: `THREE-BODY-COMPILE-OK (2 blocks)`. Note `String:compile` takes one expression, so multi-block example files must be compiled block-by-block.
- *Math smoke test* `three_body_math_smoke.scd`: mirrors the config draw + velocity-Verlet + softened gravity + central well with no server, runs several seeds for ~60 s of sim, and asserts determinism, finiteness and boundedness. (Both harnesses live in the scratchpad; not committed — CI has no SuperCollider.)

**Tuned physics + whoosh constants** (chosen from the multi-seed smoke sweep; all runs stayed bounded and finite, radii used the screen, whoosh events landed at 0–1.5/s):
- `~grav = 0.05`, `~eps2 = 0.022`, `~k = 0.20` (was 0.06 / 0.02 / 0.6 — the original well was too strong, collapsing the bodies into a tight central knot with max radius ~0.19).
- `~rmax = 0.40` (matched to the observed radius range for a good pitch spread).
- Whoosh trigger changed from "fire while near (cooldown-gated)" to a **falling-edge, fast-approach** trigger: fire once when a pair first enters `~encDist = 0.09` with closing speed above `~encFloor = 0.40`, backed by a short `~encCool = 0.25` s cooldown and a per-pair `~near` edge-state array. A bounded three-body system passes close often, so the continuous trigger would have machine-gunned; the edge+speed gate reserves whooshes for genuine slingshots.
```
