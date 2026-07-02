// =============================================================================
// Pachinko music box — a SuperCollider port of tools/example_pachinko.py
//
// A gravity-fed generative sequencer for gscore_osc (3D space). Small balls rain
// through an offset grid of pegs and fall into five pentatonic bins (C D E G A).
// gscore emits two OSC streams back to us, and — unlike the Python version, which
// only prints them — THIS program synthesises them into sound locally:
//
//     /music/pin   <ball> <pin>  <ball-speed>          -> a percussive "plink"  (\pinPlink)
//     /music/note  <bin>  <note> <ball> <ball-speed>   -> a bell tone           (\pinNote)
//
// So there is no separate synth to wire up: sclang drives the physics board over
// OSC *and* plays the resulting music. Ball speed rides along as velocity/amp, the
// bin index pans the note across the stereo field, and each ball is recycled to the
// top the instant it lands (we listen for our own /music/note), with a slow watchdog
// re-dropping any ball that jams in the pegs.
//
// REQUIRES gscore_osc 0.8.x+ (3D space) — leans on two features, same as the .py:
//   * sizable primitives:  small balls/pegs via `new circle <r>`.
//   * `physics planar 1`:  pins balls to z=0 so they can't drift out of the thin
//                          bins over time (without it the board goes silent ~30 s in).
//
// PORTS:  gscore listens on 7400 and sends its replies to 7401. We send commands to
//         7400 and open UDP 7401 to receive — mind that no other instance holds 7401.
//
// USAGE:
//   1. Boot the audio server if it isn't up:   evaluating the block below does it.
//   2. Run the Godot project with gscore_osc set to 3D (exactly ONE instance).
//   3. Put the cursor inside the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. Balls start raining; you should hear plinks + pentatonic notes.
//   5. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

    // ---- SynthDefs: two simple synthesised voices ---------------------------

    // A soft bell / marimba for the bin notes: a percussive additive tone
    // (fundamental + a few inharmonic-ish partials) with a little reverb tail.
    SynthDef(\pinNote, { |freq = 440, amp = 0.3, pan = 0|
        var env = EnvGen.kr(Env.perc(0.002, 1.1, 1, -4), doneAction: 2);
        var partials = SinOsc.ar(freq * [1, 2, 3.01, 4.17], 0, [0.5, 0.3, 0.16, 0.08]);
        var sig = partials.sum * env * amp;
        sig = sig + (FreeVerb.ar(sig, 0.3, 0.7, 0.4) * 0.3);
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    // A short high "plink" for pin hits: a quick sine ping plus a filtered
    // noise click, so a dense burst of hits reads as percussion.
    SynthDef(\pinPlink, { |freq = 1800, amp = 0.15, pan = 0|
        var env = EnvGen.kr(Env.perc(0.001, 0.06, 1, -6), doneAction: 2);
        var tone = SinOsc.ar(freq) * env;
        var click = HPF.ar(WhiteNoise.ar, 4000) * EnvGen.kr(Env.perc(0.0002, 0.01)) * 0.5;
        Out.ar(0, Pan2.ar((tone + click) * amp, pan));
    }).add;

    s.sync;   // make sure both defs exist on the server before any Synth() call

    // ---- configuration ------------------------------------------------------
    ~engine  = NetAddr("127.0.0.1", 7400);          // where gscore listens
    ~nb      = 6;                                    // number of balls in play
    ~notes   = ["C4", "D4", "E4", "G4", "A4"];       // pentatonic bins (literals sent to gscore)
    ~binx    = [-0.44, -0.22, 0.0, 0.22, 0.44];      // bin x positions (normalized)
    ~even    = [-0.48, -0.32, -0.16, 0.0, 0.16, 0.32, 0.48];  // peg columns, even rows
    ~odd     = [-0.4, -0.24, -0.08, 0.08, 0.24, 0.4];         // peg columns, offset rows
    ~ys      = [0.85, 0.71, 0.57, 0.43, 0.29];       // peg rows (top -> bottom)
    ~noteFreq = IdentityDictionary[
        \C4 -> 60.midicps, \D4 -> 62.midicps, \E4 -> 64.midicps,
        \G4 -> 67.midicps, \A4 -> 69.midicps
    ];
    ~lastDrop = Array.fill(~nb, 0);                  // Main.elapsedTime of each ball's last drop

    // ---- paced OSC send (0.03 s between messages, like the Python `s()`) -----
    // Only call from inside a Routine — `.wait` yields the enclosing thread.
    ~snd = { |... m| ~engine.sendMsg(*m); 0.03.wait; };

    // Recycle a ball to the top. Called from OSC callbacks / the watchdog, so it
    // forks its own Routine to get the little pause between velocity and pos.
    ~drop = { |i|
        ~lastDrop[i] = Main.elapsedTime;
        Routine({
            ~engine.sendMsg("/gscore/scene/ball" ++ i ++ "/physics",
                "velocity", rrand(-0.5, 0.5), -0.4, 0.0);
            0.03.wait;
            ~engine.sendMsg("/gscore/scene/ball" ++ i,
                "pos", rrand(-0.14, 0.14), 1.0, 0.0);
        }).play;
    };

    // ---- open the reply port and register listeners -------------------------
    if(thisProcess.openUDPPort(7401),
        { "gscore-pachinko: listening for replies on UDP 7401".postln; },
        { "gscore-pachinko: UDP 7401 already open (or busy) — continuing".postln; }
    );

    // A ball landed in a bin: play the note, pan by bin, recycle the ball.
    OSCdef(\music_note, { |msg|
        var binid = msg[1], note = msg[2].asSymbol, ball = msg[3];
        var speed = (msg[4] ? 1.0).abs;
        var idx   = binid.asString.drop(3).asInteger;   // "bin2" -> 2
        var pan   = (idx - 2) / 2.0;                     // -1 .. +1 across the five bins
        var freq  = ~noteFreq[note] ? 440;
        var amp   = (0.12 + (speed * 0.05)).clip(0.06, 0.3);
        Synth(\pinNote, [\freq, freq, \amp, amp, \pan, pan]);
        ("  ♪ " ++ note ++ "   (bin " ++ idx ++ ")").postln;
        if(ball.asString.copyRange(0, 3) == "ball") {
            ~drop.(ball.asString.drop(4).asInteger);
        };
    }, '/music/note', recvPort: 7401);

    // A ball struck a pin: a quick percussive plink, speed -> louder/brighter.
    OSCdef(\music_pin, { |msg|
        var speed = (msg[3] ? 1.0).abs;
        var freq  = rrand(1400, 2600);
        var amp   = (0.05 + (speed * 0.03)).clip(0.03, 0.16);
        Synth(\pinPlink, [\freq, freq, \amp, amp, \pan, rrand(-0.4, 0.4)]);
        // ("  · plink (" ++ msg[2] ++ ")").postln;   // uncomment for verbose plink log
    }, '/music/pin', recvPort: 7401);

    // ---- watchdog: re-drop any ball stuck in the pegs -----------------------
    if(~watchdog.notNil) { ~watchdog.stop };
    ~watchdog = Routine({
        loop {
            2.0.wait;
            ~nb.do({ |i|
                if(Main.elapsedTime - ~lastDrop[i] > 4.0) { ~drop.(i) };
            });
        };
    }).play;

    // ---- build the board (paced, ~9 s of setup traffic) ---------------------
    ~build = Routine({
        ~snd.("/gscore/scene", "reset");

        // offset peg grid — small ROUND pegs (sized visual + matching sphere collider)
        ~ys.do({ |y, r|
            var xs = if(r % 2 == 0, { ~even }, { ~odd });
            xs.do({ |x, c|
                var pid = "peg" ++ (r * 100 + c);   // stable unique id per (row, col)
                ~snd.("/gscore/scene/" ++ pid, "new", "circle", 0.022);
                ~snd.("/gscore/scene/" ++ pid ++ "/physics", "enable", "static");
                ~snd.("/gscore/scene/" ++ pid ++ "/collider", "sphere", 0.022);
                ~snd.("/gscore/scene/" ++ pid ++ "/physics", "friction", 0.0);
                ~snd.("/gscore/scene/" ++ pid ++ "/physics", "bounce", 0.7);
                ~snd.("/gscore/scene/" ++ pid, "pos", x, y, 0.0);
            });
        });

        // side walls + thick floor (thick so fast balls can't tunnel through);
        // size the VISUAL to match the collider so they read as walls/floor.
        [[-0.58, "wallL"], [0.58, "wallR"]].do({ |pair|
            var wx = pair[0], nm = pair[1];
            ~snd.("/gscore/scene/" ++ nm, "new", "rect", 0.08, 1.5);
            ~snd.("/gscore/scene/" ++ nm ++ "/physics", "enable", "static");
            ~snd.("/gscore/scene/" ++ nm ++ "/physics", "friction", 0.0);
            ~snd.("/gscore/scene/" ++ nm ++ "/collider", "rect", 0.08, 1.5);
            ~snd.("/gscore/scene/" ++ nm, "pos", wx, 0.5, 0.0);
        });
        ~snd.("/gscore/scene/floor", "new", "rect", 1.2, 0.6);
        ~snd.("/gscore/scene/floor/physics", "enable", "static");
        ~snd.("/gscore/scene/floor/physics", "friction", 0.0);
        ~snd.("/gscore/scene/floor/collider", "rect", 1.2, 0.6);
        ~snd.("/gscore/scene/floor", "pos", 0.0, -0.22, 0.0);

        // five pentatonic bins (sensor areas) — each plays a note as a ball enters
        ~binx.do({ |x, b|
            var bid = "bin" ++ b, note = ~notes[b];
            ~snd.("/gscore/scene/" ++ bid, "new", "rect", 0.2, 0.24);
            ~snd.("/gscore/scene/" ++ bid ++ "/physics", "enable", "area");
            ~snd.("/gscore/scene/" ++ bid ++ "/collider", "rect", 0.2, 0.24);
            ~snd.("/gscore/scene/" ++ bid, "pos", x, 0.12, 0.0);
            ~snd.("/gscore/scene/" ++ bid ++ "/on", "areaEnter", "/music/note", "cooldown", 0.05);
            // payload:  <bin (self)>  <note (literal)>  <ball (other)>  <ball speed>
            ~snd.("/gscore/scene/" ++ bid ++ "/payload", "areaEnter",
                "self", "=" ++ note, "other", "otherspeed");
        });

        // small balls, pinned to the z=0 plane, dropped from the top
        ~nb.do({ |i|
            var bid = "ball" ++ i;
            ~snd.("/gscore/scene/" ++ bid, "new", "circle", 0.02);
            ~snd.("/gscore/scene/" ++ bid ++ "/physics", "enable", "rigid");
            ~snd.("/gscore/scene/" ++ bid ++ "/collider", "sphere", 0.02);
            ~snd.("/gscore/scene/" ++ bid ++ "/physics", "planar", 1);
            ~snd.("/gscore/scene/" ++ bid ++ "/physics", "friction", 0.0);
            ~snd.("/gscore/scene/" ++ bid ++ "/physics", "bounce", 0.5);
            // plink whenever this ball hits a pin. `other peg*` matches any peg id;
            // a small cooldown keeps rapid double-hits in check.
            ~snd.("/gscore/scene/" ++ bid ++ "/on", "collisionEnter", "/music/pin",
                "other", "peg*", "cooldown", 0.03);
            ~snd.("/gscore/scene/" ++ bid ++ "/payload", "collisionEnter",
                "self", "other", "otherspeed");
            ~drop.(i);
        });

        ~snd.("/gscore/physics", "gravity", 0.0, -1.0, 0.0);
        ~snd.("/gscore/physics", "enable", 1);

        // frame the board (it sits a little above the default centre)
        ~snd.("/gscore/camera", "pos", 0.0, 0.42, 2.1);
        ~snd.("/gscore/camera", "lookAt", 0.0, 0.42, 0.0);

        "".postln;
        "Pachinko built — balls raining through the pegs into pentatonic bins.".postln;
        "♪ notes stream below; evaluate the CLEANUP block to stop.".postln;
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
OSCdef(\music_note).free;
OSCdef(\music_pin).free;
~engine.sendMsg("/gscore/physics", "enable", 0);   // freeze the board
"Pachinko stopped.".postln;
)
