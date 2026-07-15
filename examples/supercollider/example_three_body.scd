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
        f   = Lag.kr(freq, 1.5);
		f = f * (f/freq);
		sig = LFCub.ar(f * (f/freq)) + SinOsc.ar(f * (freq/f) * 2, 0, 0.3);
        env = EnvGen.kr(Env.asr(5.0, 1, 1.5), gate, doneAction: 2);
		sig = RLPF.ar(sig, Lag.kr(cutoff, 0.15).clip(100, 3000), 0.4 * (freq/f));
        sig = sig * Lag.kr(amp, 0.2) * env;
        Out.ar(out, Pan2.ar(sig, Lag.kr(pan, 0.2)));
    }).add;

    // a one-shot "whoosh" for a near-collision slingshot: a filtered-noise sweep
    // plus a sine glide; intensity is set by the pass speed at trigger time.
    SynthDef(\whoosh, { |out = 0, amp = 0.3, pan = 0, dur = 0.6, f0 = 300, f1 = 2000|
        var env, sweep, sig;
        env   = EnvGen.kr(Env.perc(0.1, dur, 1, -2), doneAction: 2);
		sweep = XLine.kr(f0, f1, LFNoise1.kr(0.01, dur) * 0.6);
        sig   = (BPF.ar(WhiteNoise.ar, sweep, 0.1) * 6) + LFSaw.ar(sweep, 0, 0.3);
		sig   = Lag.ar(0.5 * sig * env * amp, 0.001);
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
    ~mass = Array.fill(3, { rrand(0.7, 2.4) });
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

    ~grav    = 0.05;     // gravitational strength (mutual attraction)
    ~eps2    = 0.022;    // softening^2: keeps close passes finite (no singularity)
    ~k       = 0.20;     // central-well strength: bounds the system on-screen
    ~tickHz  = 60;       // scene / sound update rate
    ~sub     = 8;        // physics substeps per tick (stable through close passes)
    ~rmax    = 0.40;     // radius that maps to the lowest pitch
    ~scale   = [60, 62, 64, 66, 67, 69, 71, 72, 74, 76, 78, 79, 81];   // C lydian, ~2 octaves
    ~pairs   = [[0, 1], [0, 2], [1, 2]];
    ~encDist  = 0.09;    // pairwise distance below which a fast pass fires a whoosh
    ~encFloor = 0.40;    // minimum closing speed for a whoosh (only dramatic slingshots)
    ~encCool  = 0.25;    // per-pair whoosh cooldown backstop (s)
    ~cool    = [0.0, 0.0, 0.0];
    ~near    = [false, false, false];   // per-pair "was within encDist last tick" (edge trigger)

    // accelerations for a set of positions: softened mutual gravity + central well.
    ~accel = { |positions|
        var acc;
        acc = Array.fill(3, { [0.0, 0.0] });
        3.do { |i|
            3.do { |j|
                if(i != j) {
                    var d, r2, inv;
                    d   = positions[j] - positions[i];
                    r2  = (d[0] * d[0]) + (d[1] * d[1]);
                    inv = (~grav * ~mass[j]) / ((r2 + ~eps2) ** 1.5);
                    acc[i] = acc[i] + (d * inv);
                };
            };
            acc[i] = acc[i] + (positions[i] * ~k.neg);        // central well
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

            // per-pair: fire a whoosh once, on the FALLING EDGE of a FAST approach —
            // a real slingshot (bodies pass close AND fast), not every routine near-miss.
            ~pairs.do { |pr, pidx|
                var i, j, sep, r, relv, closing, isNear, intensity, mx;
                i    = pr[0];
                j    = pr[1];
                sep  = ~pos[i] - ~pos[j];
                r    = hypot(sep[0], sep[1]);
                relv = ~vel[i] - ~vel[j];
                closing = ((relv[0] * sep[0]) + (relv[1] * sep[1])) / max(r, 1e-6);
                isNear  = r < ~encDist;
                ~cool[pidx] = (~cool[pidx] - dt).max(0);
                if(isNear and: { ~near[pidx].not } and: { closing < ~encFloor.neg } and: { ~cool[pidx] <= 0 }, {
                    intensity = closing.abs;
                    mx = (~pos[i][0] + ~pos[j][0]) * 0.5;
                    Synth(\whoosh, [
                        \out, ~fxbus,
                        \amp, (0.06 + (intensity * 0.4)).clip(0.12, 0.6),
                        \pan, mx.clip(-1, 1),
                        \dur, 0.1,
						\f0, 320,
                        \f1, (900 + (intensity * 2200)).clip(900, 5000)
                    ]);
                    ~cool[pidx] = ~encCool;
                });
                ~near[pidx] = isNear;
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
