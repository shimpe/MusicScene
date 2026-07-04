// =============================================================================
// Chaotic "snow-globe" — a SuperCollider port of tools/example_chaos_globe.py
//
// Several balls are sealed inside a box; this program slowly ROTATES the direction
// of gravity, so they tumble and cascade endlessly, never settling. Five pentatonic
// sensor zones in a ring (C D E G A) each emit a note as a ball passes through:
//
//     /music/note  <zone>  <note>  <ball-speed>
//
// Unlike the Python version (which just prints the notes), THIS program synthesises
// them locally: a warm, reverberant bell per note, panned to the zone's position in
// the ring, ball speed -> amplitude. So it needs no external synth — sclang drives
// the physics AND plays the evolving, never-repeating melody.
//
// WHY ROTATING GRAVITY?  A game physics engine bleeds energy, so any self-contained
// mechanism winds down within seconds. Continuously turning the gravity vector is an
// inexhaustible energy source, so the motion stays chaotic forever. A little linear
// damping keeps the balls slow enough that they never tunnel out of the box.
//
// REQUIRES gscore_osc 0.8.x+ (3D space). gscore listens on 7400 and replies to 7401.
//
// USAGE:
//   1. Boot the audio server (evaluating the block below does it).
//   2. Run the Godot project with gscore_osc set to 3D (exactly ONE instance).
//   3. Put the cursor in the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. To stop, evaluate the CLEANUP block at the bottom.
// =============================================================================

(
s.waitForBoot({

    // A warm bell for the zone notes: additive partials, a long tail and generous
    // reverb so the piece reads as an evolving ambient texture.
    SynthDef(\globeBell, { |freq = 440, amp = 0.3, pan = 0|
        var env = EnvGen.kr(Env.perc(0.005, 2.2, 1, -3.5), doneAction: 2);
        var partials = SinOsc.ar(freq * [1, 2.01, 3.02, 4.5], 0, [0.5, 0.3, 0.16, 0.09]);
        var sig = partials.sum * env * amp;
        sig = sig + (FreeVerb.ar(sig, 0.45, 0.85, 0.4) * 0.5);
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    s.sync;

    // ---- configuration ------------------------------------------------------
    ~engine   = NetAddr("127.0.0.1", 7400);
    ~notes    = ["C4", "D4", "E4", "G4", "A4"];
    ~noteFreq = IdentityDictionary[
        \C4 -> 60.midicps, \D4 -> 62.midicps, \E4 -> 64.midicps,
        \G4 -> 67.midicps, \A4 -> 69.midicps
    ];

    // paced OSC send (0.03 s between messages, like the Python `s()`); Routine-only.
    ~snd = { |... m| ~engine.sendMsg(*m); 0.03.wait; };

    // ---- open the reply port + listen ---------------------------------------
    if(thisProcess.openUDPPort(7401),
        { "gscore-snowglobe: listening for replies on UDP 7401".postln; },
        { "gscore-snowglobe: UDP 7401 already open (or busy) — continuing".postln; }
    );

    OSCdef(\music_note, { |msg|
        var zoneid = msg[1], note = msg[2].asSymbol;
        var speed = (msg[3] ? 1.0).abs;
        var k    = zoneid.asString.drop(4).asInteger;   // "zone2" -> 2
        var pan  = (90 + (k * 72)).degrad.cos;          // ring position -> stereo (-1..+1)
        var freq = ~noteFreq[note] ? 440;
        var amp  = (0.14 + (speed * 0.05)).clip(0.06, 0.32);
        Synth(\globeBell, [\freq, freq, \amp, amp, \pan, pan]);
        ("  ♪ " ++ note ++ "   (zone " ++ k ++ ")").postln;
    }, '/music/note', recvPort: 7401);

    // ---- build the sealed box, zones and balls ------------------------------
    ~build = Routine({
        ~snd.("/gscore/scene", "reset");

        // sealed box: four THICK static walls (thick so fast balls can't tunnel through)
        [
            ["top",  0.0,  0.66, 1.5, 0.3],
            ["bot",  0.0, -0.66, 1.5, 0.3],
            ["lft", -0.66, 0.0,  0.3, 1.5],
            ["rgt",  0.66, 0.0,  0.3, 1.5]
        ].do({ |wl|
            var name = wl[0], x = wl[1], y = wl[2], w = wl[3], h = wl[4];
            ~snd.("/gscore/scene/" ++ name, "new", "rect");
            ~snd.("/gscore/scene/" ++ name ++ "/physics", "enable", "static");
            ~snd.("/gscore/scene/" ++ name ++ "/physics", "friction", 0.0);
            ~snd.("/gscore/scene/" ++ name ++ "/collider", "rect", w, h);
            ~snd.("/gscore/scene/" ++ name, "pos", x, y, 0.0);
        });

        // five pentatonic sensor zones arranged in a ring
        ~notes.do({ |note, k|
            var a = (90 + (k * 72)).degrad;
            var zx = 0.42 * a.cos, zy = 0.42 * a.sin;
            var zid = "zone" ++ k;
            ~snd.("/gscore/scene/" ++ zid, "new", "rect");
            ~snd.("/gscore/scene/" ++ zid ++ "/physics", "enable", "area");
            ~snd.("/gscore/scene/" ++ zid ++ "/collider", "rect", 0.26, 0.26);
            ~snd.("/gscore/scene/" ++ zid, "pos", zx, zy, 0.0);
            // any ball entering emits a note; small cooldown so a slow pass doesn't retrigger
            ~snd.("/gscore/scene/" ++ zid ++ "/on", "areaEnter", "/music/note", "cooldown", 0.08);
            ~snd.("/gscore/scene/" ++ zid ++ "/payload", "areaEnter", "self", "=" ++ note, "otherspeed");
        });

        // a handful of balls; light LINEAR DAMPING caps their speed so they can never
        // tunnel out of the box, while gravity still tosses them around.
        6.do({ |i|
            var b = "ball" ++ i;
            ~snd.("/gscore/scene/" ++ b, "new", "circle");
            ~snd.("/gscore/scene/" ++ b ++ "/physics", "enable", "rigid");
            ~snd.("/gscore/scene/" ++ b ++ "/physics", "planar", 1);          // pin to z=0 (no out-of-plane drift)
            ~snd.("/gscore/scene/" ++ b ++ "/physics", "friction", 0.0);
            ~snd.("/gscore/scene/" ++ b ++ "/physics", "bounce", 0.35);
            ~snd.("/gscore/scene/" ++ b ++ "/physics", "damping", 1.4, 0.0);  // linear, angular
            ~snd.("/gscore/scene/" ++ b, "pos", -0.35 + (0.14 * i), 0.0, 0.0);
        });

        ~snd.("/gscore/physics", "debug", 1);            // show the box + zones (send "debug 0" to hide)
        ~snd.("/gscore/physics", "gravity", 0.0, -1.0, 0.0);
        ~snd.("/gscore/physics", "enable", 1);

        "".postln;
        "Snow-globe built — rotating gravity keeps the balls tumbling forever.".postln;
        "♪ notes stream below; evaluate the CLEANUP block to stop.".postln;
        "".postln;

        // ---- start the gravity 'shake' now that the box exists --------------
        if(~shake.notNil) { ~shake.stop };
        ~theta = 0.0;
        ~shake = Routine({
            loop {
                ~theta = ~theta + 0.8;                   // advance the gravity direction
                ~engine.sendMsg("/gscore/physics", "gravity", ~theta.cos, ~theta.sin, 0.0);
                0.8.wait;
            };
        }).play;
    });
    ~build.play;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
if(~shake.notNil) { ~shake.stop };
OSCdef(\music_note).free;
~engine.sendMsg("/gscore/physics", "gravity", 0.0, -1.0, 0.0);   // gravity back to down
~engine.sendMsg("/gscore/physics", "enable", 0);                 // freeze the balls
"Snow-globe stopped.".postln;
)
