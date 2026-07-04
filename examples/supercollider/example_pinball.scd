// =============================================================================
// Generative pinball arcade — a SuperCollider showcase for gscore_osc's collision
// reactors (bouncers & portals), built in 3D with planar physics (bodies pinned to
// z=0, exactly like tools/example_pachinko.scd / example_pachinko.py).
//
// Autonomous & generative — there are NO player flippers. A handful of balls launch
// from the top, ricochet off bumpers, get warped across the table by portals, ring
// pentatonic targets, rattle a scatter of pins, and are recycled the instant they
// reach the drain — forever. gscore emits several OSC streams back to us, and — just
// like the pachinko port — sclang both DRIVES the board over OSC *and* synthesises
// every sound locally. No external synth required.
//
//     /pin/bump    <bumper> <ball-speed>                  -> bright metallic "ding"   (\bumperDing)
//     /pin/warp    <portal> <ball-speed>                  -> swept noise "whoosh"     (\portalWhoosh)
//     /music/note  <zone>   <note> <ball> <ball-speed>     -> pentatonic bell          (\targetBell)
//     /pin/click   <ball>   <pin>  <ball-speed>            -> tiny percussive click    (\pinClick)
//     /pin/drain   <drain>  <ball> <ball-speed>            -> low percussive "thunk"   (\drainThunk)
//
// A slow, independent arpeggio (\padArp) runs underneath the whole time as a musical
// bed, its amplitude loosely tied to how many balls are in play.
//
// REQUIRES gscore_osc 0.12.x+ (3D space) — leans on:
//   * collision reactors: `new bouncer` / `new portal` (README "Collision reactors",
//     ADVANCED.md §10). Both are first-class Area types whose Area is auto-enabled
//     at creation, and they still emit `areaEnter`, so `on areaEnter …` drives sound.
//   * `physics planar 1`: pins balls to z=0 so a 3D scene reads as a flat table
//     (same trick the pachinko port uses).
//
// A NOTE ON VISUALS: `new bouncer` / `new portal` create a bare Area3D with no mesh
// (they are pass-through *sensors*, not visible primitives) — so `color` on them is
// harmless but invisible. Each bumper/portal below gets a small non-physical
// decorative twin ("<id>Vis": a lit sphere or disc) positioned on top of it, which is
// what you actually see glowing on the table.
//
// PORTS:  gscore listens on 7400 and sends its replies to 7401. We send commands to
//         7400 and open UDP 7401 to receive — mind that no other instance holds 7401.
//
// USAGE:
//   1. Boot the audio server if it isn't up:   evaluating the block below does it.
//   2. Run the Godot project with gscore_osc set to 3D (exactly ONE instance).
//   3. Put the cursor inside the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. Balls launch, bumpers ding, portals whoosh, targets ring, the drain thunks and
//      recycles — the table should never sit still or fall silent.
//   5. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

    // ---- SynthDefs: six small synthesised voices -----------------------------

    // Bumper "ding": a bright FM bell. Ball speed drives both pitch and the FM
    // index (brightness), so a hard hit rings harder AND brighter than a soft one.
    SynthDef(\bumperDing, { |freq = 500, amp = 0.25, pan = 0, bright = 0.4|
        var env = EnvGen.kr(Env.perc(0.001, 0.16, 1, -6), doneAction: 2);
        var modIndex = 1 + (bright * 7);
        var modFreq = freq * 2.756;                       // inharmonic ratio -> metallic
        var mod = SinOsc.ar(modFreq) * modIndex * freq;
        var car = SinOsc.ar(freq + mod);
        var click = HPF.ar(WhiteNoise.ar, 5000) * EnvGen.kr(Env.perc(0.0003, 0.01)) * 0.25;
        var sig = ((car * 0.8) + click) * env * amp;
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    // Portal "whoosh": band-passed noise swept upward through an exponential ramp.
    SynthDef(\portalWhoosh, { |amp = 0.3, pan = 0, dur = 0.35, cf = 1200|
        var env = EnvGen.kr(Env.perc(0.02, dur, 1, -2), doneAction: 2);
        var sweep = XLine.kr(cf * 0.2, cf * 2.4, dur);
        var noise = BPF.ar(WhiteNoise.ar, sweep, 0.3) * 5;
        var sig = noise * env * amp;
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    // Target bell: soft additive pentatonic tone with a little reverb tail
    // (same shape as the pachinko port's \pinNote), panned by the zone's own x.
    SynthDef(\targetBell, { |freq = 440, amp = 0.25, pan = 0|
        var env = EnvGen.kr(Env.perc(0.002, 1.2, 1, -4), doneAction: 2);
        var partials = SinOsc.ar(freq * [1, 2, 3.01, 4.17], 0, [0.5, 0.3, 0.16, 0.08]);
        var sig = partials.sum * env * amp;
        sig = sig + (FreeVerb.ar(sig, 0.35, 0.7, 0.4) * 0.3);
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    // Pin "click": a quick high tick for the ball rattling through the pin scatter.
    SynthDef(\pinClick, { |freq = 2000, amp = 0.1, pan = 0|
        var env = EnvGen.kr(Env.perc(0.0005, 0.045, 1, -8), doneAction: 2);
        var tone = SinOsc.ar(freq) * env;
        var click = HPF.ar(WhiteNoise.ar, 4500) * EnvGen.kr(Env.perc(0.0002, 0.012)) * 0.6;
        Out.ar(0, Pan2.ar((tone + click) * amp, pan));
    }).add;

    // Drain "thunk": a low sine body + sub + a short click, so it reads as a
    // physical "the ball just dropped out" thud.
    SynthDef(\drainThunk, { |amp = 0.3, pan = 0|
        var envA = EnvGen.kr(Env.perc(0.001, 0.5, 1, -4));
        var envB = EnvGen.kr(Env.perc(0.001, 0.75, 1, -4), doneAction: 2);
        var body = SinOsc.ar(58) * envA * 0.8;
        var sub  = SinOsc.ar(36) * envB * 0.6;
        var click = HPF.ar(WhiteNoise.ar, 700) * EnvGen.kr(Env.perc(0.0005, 0.02)) * 0.35;
        var sig = (body + sub + click) * amp;
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    // Sustained bed: a slow, independent pentatonic arpeggio underneath everything.
    SynthDef(\padArp, { |freq = 220, amp = 0.12, pan = 0, atk = 0.6, rel = 2.0|
        var env = EnvGen.kr(Env.new([0, 1, 0], [atk, rel], \sin), doneAction: 2);
        var sig = Mix.ar([SinOsc.ar(freq), SinOsc.ar(freq * 2.005) * 0.3, SinOsc.ar(freq * 0.501) * 0.4]);
        sig = LPF.ar(sig, 1400) * env * amp;
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    s.sync;   // make sure every def exists on the server before any Synth() call

    // ---- configuration --------------------------------------------------------
    ~engine  = NetAddr("127.0.0.1", 7400);        // where gscore listens
    ~nb      = 4;                                  // balls in play at once
    ~ballR   = 0.026;                              // ball radius (normalized)
    ~launchY = 0.92;                               // where balls spawn/relaunch from

    // pin scatter columns (shared by both zig-zag rows)
    ~pinX = [-0.45, -0.27, -0.09, 0.09, 0.27, 0.45];

    // top bumper row (3 of the 6 bumpers)
    ~bumpTopId       = ["bumpA", "bumpB", "bumpC"];
    ~bumpTopX        = [-0.34, 0.0, 0.34];
    ~bumpTopStrength = [3.0, 3.6, 3.0];
    ~bumpTopColor    = [[0.95, 0.20, 0.25], [0.95, 0.75, 0.15], [0.90, 0.30, 0.50]];

    // scoring zones: 5 pentatonic tones (C D E G A) x 2 octaves = 10 zones
    ~zoneX      = [-0.44, -0.22, 0.0, 0.22, 0.44];
    ~zoneNoteHi = ["C4", "D4", "E4", "G4", "A4"];
    ~zoneNoteLo = ["C3", "D3", "E3", "G3", "A3"];
    ~zoneColor  = [[0.90, 0.25, 0.25], [0.95, 0.55, 0.15], [0.90, 0.85, 0.20],
                   [0.25, 0.85, 0.35], [0.30, 0.55, 0.95]];

    ~noteFreq = IdentityDictionary[
        \C3 -> 48.midicps, \D3 -> 50.midicps, \E3 -> 52.midicps, \G3 -> 55.midicps, \A3 -> 57.midicps,
        \C4 -> 60.midicps, \D4 -> 62.midicps, \E4 -> 64.midicps, \G4 -> 67.midicps, \A4 -> 69.midicps
    ];

    // filled in by ~mkBumper / ~mkPortal / ~mkZone below, keyed by object id symbol
    ~bumperPan = IdentityDictionary.new;
    ~portalPan = IdentityDictionary.new;
    ~zonePan   = IdentityDictionary.new;

    // ---- paced OSC send (like the pachinko port's `~snd`) ----------------------
    // Only call from inside a Routine — `.wait` yields the enclosing thread.
    ~snd = { |... m| ~engine.sendMsg(*m); 0.0001.wait; };

    // ---- scene-building helpers -------------------------------------------------
    // Order matters: `color`/`opacity` only work while the node is still the plain
    // mesh, so they must be sent BEFORE `physics enable` wraps it in a body (the
    // wrapped body has no mesh/modulate of its own to color) — same rule the
    // pachinko port follows for its pegs/bins/balls.

    // Static bouncy wall/floor/ceiling — containment for the whole table.
    ~mkWall = { |id, w, h, d, x, y, bounce, cr, cg, cb|
        ~snd.("/gscore/scene/" ++ id, "new", "box", w, h, d);
        ~snd.("/gscore/scene/" ++ id, "color", cr, cg, cb);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "enable", "static");
        ~snd.("/gscore/scene/" ++ id ++ "/collider", "box", w, h, d);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "friction", 0.05);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "bounce", bounce);
        ~snd.("/gscore/scene/" ++ id, "pos", x, y, 0.0);
    };

    // Small static pin the balls rattle against (round, silvery, bouncy).
    ~mkPin = { |id, x, y, r, cr, cg, cb|
        ~snd.("/gscore/scene/" ++ id, "new", "sphere", r);
        ~snd.("/gscore/scene/" ++ id, "color", cr, cg, cb);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "enable", "static");
        ~snd.("/gscore/scene/" ++ id ++ "/collider", "sphere", r);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "bounce", 0.78);
        ~snd.("/gscore/scene/" ++ id, "pos", x, y, 0.0);
    };

    // Bumper: a `bouncer` reactor (invisible Area) + a lit decorative sphere twin.
    ~mkBumper = { |id, x, y, strength, r, cr, cg, cb|
        ~snd.("/gscore/scene/" ++ id, "new", "bouncer");
        ~snd.("/gscore/scene/" ++ id ++ "/collider", "circle", r);
        ~snd.("/gscore/scene/" ++ id, "pos", x, y, 0.0);
        ~snd.("/gscore/scene/" ++ id ++ "/bouncer", "strength", strength, "gain", 1.0, "minSpeed", 0.35);
        ~snd.("/gscore/scene/" ++ id, "color", cr, cg, cb);   // no visible effect (bare Area) — see Vis twin
        ~snd.("/gscore/scene/" ++ id ++ "/on", "areaEnter", "/pin/bump", "cooldown", 0.05);
        ~snd.("/gscore/scene/" ++ id ++ "/payload", "areaEnter", "self", "otherspeed");
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "new", "sphere", r * 0.85);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "color", cr, cg, cb);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "metallic", 0.5);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "roughness", 0.35);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "pos", x, y, 0.0);
        ~bumperPan[id.asSymbol] = (x / 0.6).clip(-1, 1);
    };

    // Portal: a `portal` reactor (invisible Area) + a lit decorative disc twin.
    // Linking is done by the caller (directional — see the build routine below).
    ~mkPortal = { |id, x, y, r, cr, cg, cb|
        ~snd.("/gscore/scene/" ++ id, "new", "portal");
        ~snd.("/gscore/scene/" ++ id ++ "/collider", "circle", r);
        ~snd.("/gscore/scene/" ++ id, "pos", x, y, 0.0);
        ~snd.("/gscore/scene/" ++ id, "color", cr, cg, cb);   // no visible effect (bare Area) — see Vis twin
        ~snd.("/gscore/scene/" ++ id ++ "/on", "areaEnter", "/pin/warp", "cooldown", 0.12);
        ~snd.("/gscore/scene/" ++ id ++ "/payload", "areaEnter", "self", "otherspeed");
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "new", "cylinder", r * 0.9, 0.015);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "color", cr, cg, cb);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "metallic", 0.3);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "roughness", 0.2);
        ~snd.("/gscore/scene/" ++ id ++ "Vis", "pos", x, y, 0.0);
        ~portalPan[id.asSymbol] = (x / 0.6).clip(-1, 1);
    };

    // Scoring target: a pentatonic sensor area (visible glowing orb).
    ~mkZone = { |id, x, y, note, r, cr, cg, cb|
        ~snd.("/gscore/scene/" ++ id, "new", "sphere", r);
        ~snd.("/gscore/scene/" ++ id, "color", cr, cg, cb);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "enable", "area");
        ~snd.("/gscore/scene/" ++ id ++ "/collider", "sphere", r);
        ~snd.("/gscore/scene/" ++ id, "pos", x, y, 0.0);
        ~snd.("/gscore/scene/" ++ id ++ "/on", "areaEnter", "/music/note", "cooldown", 0.08);
        // payload:  <zone (self)>  <note (literal)>  <ball (other)>  <ball speed>
        ~snd.("/gscore/scene/" ++ id ++ "/payload", "areaEnter", "self", "=" ++ note, "other", "otherspeed");
        ~zonePan[id.asSymbol] = (x / 0.6).clip(-1, 1);
    };

    // A ball: small sphere, pinned to the z=0 plane, rings on any pin hit.
    ~mkBall = { |i, cr, cg, cb|
        var id = "ball" ++ i;
        ~snd.("/gscore/scene/" ++ id, "new", "sphere", ~ballR);
        ~snd.("/gscore/scene/" ++ id, "color", cr, cg, cb);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "enable", "rigid");
        ~snd.("/gscore/scene/" ++ id ++ "/collider", "sphere", ~ballR);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "planar", 1);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "friction", 0.05);
        ~snd.("/gscore/scene/" ++ id ++ "/physics", "bounce", 0.58);
        // click whenever THIS ball hits a pin (collisionEnter only fires on rigid
        // bodies — static pins can't emit it themselves, so the binding lives here).
        ~snd.("/gscore/scene/" ++ id ++ "/on", "collisionEnter", "/pin/click", "other", "pin*", "cooldown", 0.03);
        // "speed" (not "otherspeed"!) — the pin is static, so its own speed is
        // always 0; the ball's OWN speed is what should drive the click.
        ~snd.("/gscore/scene/" ++ id ++ "/payload", "collisionEnter", "self", "other", "speed");
    };

    // Recycle a ball to the top. Called from OSC callbacks / the watchdog, so it
    // forks its own Routine to get a small pause between velocity and teleport.
    ~lastDrop = Array.fill(~nb, 0);
    ~drop = { |i|
        ~lastDrop[i] = Main.elapsedTime;
        Routine({
            ~engine.sendMsg("/gscore/scene/ball" ++ i ++ "/physics",
                "velocity", rrand(-0.3, 0.3), -0.15, 0.0);
            0.03.wait;
            ~engine.sendMsg("/gscore/scene/ball" ++ i,
                "pos", rrand(-0.22, 0.22), ~launchY, 0.0);
        }).play;
    };

    // ---- open the reply port and register listeners ---------------------------
    if(thisProcess.openUDPPort(7401),
        { "gscore-pinball: listening for replies on UDP 7401".postln; },
        { "gscore-pinball: UDP 7401 already open (or busy) — continuing".postln; }
    );

    // A ball hit a bumper: bright FM ding, pitch/brightness track its speed.
    OSCdef(\pin_bump, { |msg|
        var bid = msg[1].asSymbol;
        var speed = (msg[2] ? 1.0).abs;
        var pan = ~bumperPan[bid] ? 0.0;
        var bright = (speed / 1.4).clip(0.0, 1.0);
        var freq = 260 + (speed * 260) + 200.0.rand;
        var amp = (0.14 + (speed * 0.12)).clip(0.1, 0.45);
        Synth(\bumperDing, [\freq, freq, \amp, amp, \pan, pan, \bright, bright]);
    }, '/pin/bump', recvPort: 7401);

    // A ball entered a portal: swept whoosh, cutoff/level track its speed.
    OSCdef(\pin_warp, { |msg|
        var pid = msg[1].asSymbol;
        var speed = (msg[2] ? 1.0).abs;
        var pan = ~portalPan[pid] ? 0.0;
        var cf = (900 + (speed * 1000)).clip(500, 3200);
        var amp = (0.16 + (speed * 0.08)).clip(0.12, 0.4);
        Synth(\portalWhoosh, [\amp, amp, \pan, pan, \cf, cf, \dur, rrand(0.28, 0.48)]);
    }, '/pin/warp', recvPort: 7401);

    // A ball rang a scoring zone: pentatonic bell, panned by the zone's own x.
    OSCdef(\music_note, { |msg|
        var zid = msg[1].asSymbol, note = msg[2].asSymbol, ball = msg[3];
        var speed = (msg[4] ? 1.0).abs;
        var freq = ~noteFreq[note] ? 440;
        var pan = ~zonePan[zid] ? 0.0;
        var amp = (0.16 + (speed * 0.06)).clip(0.1, 0.36);
        Synth(\targetBell, [\freq, freq, \amp, amp, \pan, pan]);
    }, '/music/note', recvPort: 7401);

    // A ball rattled a pin: tiny click, driven by the ball's own speed.
    OSCdef(\pin_click, { |msg|
        var speed = (msg[3] ? 1.0).abs;
        var freq = rrand(1600, 3000);
        var amp = (0.04 + (speed * 0.05)).clip(0.03, 0.18);
        Synth(\pinClick, [\freq, freq, \amp, amp, \pan, rrand(-0.5, 0.5)]);
    }, '/pin/click', recvPort: 7401);

    // A ball reached the drain: low thunk, then relaunch that exact ball.
    OSCdef(\pin_drain, { |msg|
        var ball = msg[2];   // "other" field — which ball actually drained
        var speed = (msg[3] ? 1.0).abs;
        var amp = (0.22 + (speed * 0.1)).clip(0.18, 0.45);
        Synth(\drainThunk, [\amp, amp, \pan, rrand(-0.3, 0.3)]);
        if(ball.asString.copyRange(0, 3) == "ball") {
            ~drop.(ball.asString.drop(4).asInteger);
        };
    }, '/pin/drain', recvPort: 7401);

    // ---- watchdog: re-launch any ball that somehow stalls out -------------------
    if(~watchdog.notNil) { ~watchdog.stop };
    ~watchdog = Routine({
        loop {
            3.0.wait;
            ~nb.do({ |i|
                if(Main.elapsedTime - ~lastDrop[i] > 7.0) { ~drop.(i) };
            });
        };
    }).play;

    // ---- musical bed: a slow, independent pentatonic arpeggio -------------------
    // Runs the whole time under the game sounds; amplitude loosely tracks ~nb.
    ~padNotes = [36, 43, 48, 50, 55, 57, 60, 62].collect(_.midicps);
    ~padIdx = 0;
    if(~padRoutine.notNil) { ~padRoutine.stop };
    ~padRoutine = Routine({
        loop {
            var octMul = [1, 2].wchoose([0.85, 0.15]);
            var freq = ~padNotes.wrapAt(~padIdx) * octMul;
            var amp = (0.05 + (~nb * 0.018)).clip(0.05, 0.22);
            Synth(\padArp, [\freq, freq, \amp, amp, \pan, rrand(-0.25, 0.25),
                \atk, rrand(0.5, 0.9), \rel, rrand(1.6, 2.6)]);
            ~padIdx = ~padIdx + 1;
            rrand(0.7, 1.15).wait;
        };
    }).play;

    // ---- build the table (paced OSC traffic) ------------------------------------
    ~build = Routine({
        ~snd.("/gscore/scene", "reset");

        // containment: bouncy static walls all the way around the table
        ~mkWall.("wallL", 0.06, 2.3, 0.15, -0.66, 0.0, 0.85, 0.10, 0.10, 0.14);
        ~mkWall.("wallR", 0.06, 2.3, 0.15,  0.66, 0.0, 0.85, 0.10, 0.10, 0.14);
        ~mkWall.("wallTop", 1.38, 0.06, 0.15, 0.0, 1.06, 0.80, 0.10, 0.10, 0.14);
        ~mkWall.("floorSafety", 1.38, 0.06, 0.15, 0.0, -1.08, 0.50, 0.10, 0.10, 0.14);

        // pin scatter: two zig-zag rows the balls rattle through
        ~pinX.do({ |x, i|
            var y = if(i % 2 == 0, 0.32, 0.26);
            ~mkPin.("pinU" ++ i, x, y, 0.018, 0.72, 0.74, 0.80);
        });
        ~pinX.do({ |x, i|
            var y = if(i % 2 == 0, -0.34, -0.40);
            ~mkPin.("pinL" ++ i, x, y, 0.018, 0.72, 0.74, 0.80);
        });

        // bumpers: 3 up top, 2 mid-table, 1 big "jackpot" bumper near the bottom
        ~bumpTopX.do({ |x, i|
            var col = ~bumpTopColor[i];
            ~mkBumper.(~bumpTopId[i], x, 0.72, ~bumpTopStrength[i], 0.055, col[0], col[1], col[2]);
        });
        ~mkBumper.("bumpD", -0.20, 0.08, 2.6, 0.05, 0.25, 0.55, 0.95);
        ~mkBumper.("bumpE",  0.20, 0.08, 2.6, 0.05, 0.35, 0.65, 0.90);
        ~mkBumper.("bumpF",  0.0, -0.56, 4.4, 0.075, 0.95, 0.85, 0.20);   // jackpot

        // portals: 2 directional pairs (each linked both ways -> a true two-way warp)
        ~mkPortal.("portA", -0.50,  0.08, 0.05, 0.25, 0.85, 0.90);
        ~mkPortal.("portB",  0.50,  0.08, 0.05, 0.25, 0.85, 0.90);
        ~snd.("/gscore/scene/portA/portal", "link", "portB");
        ~snd.("/gscore/scene/portB/portal", "link", "portA");

        ~mkPortal.("portC", -0.30, -0.56, 0.05, 0.75, 0.40, 0.95);
        ~mkPortal.("portD",  0.30, -0.56, 0.05, 0.75, 0.40, 0.95);
        ~snd.("/gscore/scene/portC/portal", "link", "portD");
        ~snd.("/gscore/scene/portD/portal", "link", "portC");

        // scoring targets: 10 pentatonic zones in two banks (upper = octave 4, lower = octave 3)
        ~zoneX.do({ |x, i|
            var col = ~zoneColor[i];
            ~mkZone.("zU" ++ i, x,  0.50, ~zoneNoteHi[i], 0.045, col[0], col[1], col[2]);
        });
        ~zoneX.do({ |x, i|
            var col = ~zoneColor[i];
            ~mkZone.("zL" ++ i, x, -0.14, ~zoneNoteLo[i], 0.045, col[0], col[1], col[2]);
        });

        // drain: a wide sensor near the bottom recycles any ball that reaches it
        ~snd.("/gscore/scene/drain", "new", "box", 1.16, 0.22, 0.15);
        ~snd.("/gscore/scene/drain", "color", 0.55, 0.12, 0.12);
        ~snd.("/gscore/scene/drain", "opacity", 0.55);
        ~snd.("/gscore/scene/drain/physics", "enable", "area");
        ~snd.("/gscore/scene/drain/collider", "box", 1.16, 0.22, 0.15);
        ~snd.("/gscore/scene/drain", "pos", 0.0, -0.85, 0.0);
        ~snd.("/gscore/scene/drain/on", "areaEnter", "/pin/drain", "cooldown", 0.05);
        ~snd.("/gscore/scene/drain/payload", "areaEnter", "self", "other", "otherspeed");

        // multiball: nb balls, colored, pinned to the z=0 plane
        ~nb.do({ |i|
            var col = [rrand(0.3, 0.9), rrand(0.3, 0.9), rrand(0.3, 0.9)];
            ~mkBall.(i, col[0], col[1], col[2]);
        });

        ~snd.("/gscore/physics", "gravity", 0.0, -0.6, 0.0);
        ~snd.("/gscore/physics", "enable", 1);

        // launch, staggered, so the table doesn't start with every ball clumped
        ~nb.do({ |i|
            ~drop.(i);
            0.18.wait;
        });

        // frame the whole board
        ~snd.("/gscore/camera", "pos", 0.0, 0.0, 2.6);
        ~snd.("/gscore/camera", "lookAt", 0.0, 0.0, 0.0);

        "".postln;
        "Pinball built -- 4 balls, 6 bumpers, 2 portal pairs, 10 pentatonic targets,".postln;
        "12 pins rattling, one drain recycling. The table never sits still.".postln;
        "".postln;
    });
    ~build.play;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
if(~watchdog.notNil) { ~watchdog.stop };
if(~padRoutine.notNil) { ~padRoutine.stop };
OSCdef(\pin_bump).free;
OSCdef(\pin_warp).free;
OSCdef(\music_note).free;
OSCdef(\pin_click).free;
OSCdef(\pin_drain).free;
~engine.sendMsg("/gscore/physics", "enable", 0);   // freeze the board
"Pinball stopped.".postln;
)

OSCFunc.trace(false);   // prints every incoming OSC message
