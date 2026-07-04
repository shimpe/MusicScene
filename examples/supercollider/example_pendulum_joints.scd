// =============================================================================
// Double-pendulum JOINTS demo — a SuperCollider port of
// tools/example_pendulum_joints.py
//
// A static pivot and two rigid arms are joined by two hinges, so a double pendulum
// swings under gravity. Five pentatonic pads (C D E G A) sit across the bottom of
// the swing; when the pendulum TIP (arm2) crosses one, MusicScene emits
//
//     /music/note  <pad-id>  <note>  <tip-speed>
//
// Unlike the Python version (which just prints the notes), THIS program synthesises
// them locally: a soft marimba/mallet per note, panned to the pad's position across
// the swing, tip speed -> amplitude. No external synth needed.
//
// NOTE ON MOTION:  this is a demo of *joints + zones*, not a perpetual engine. A game
// physics solver bleeds energy, so the pendulum swings energetically for a while and
// then settles — re-evaluate the build block to wind it up again. For motion that
// stays chaotic forever, see example_chaos_globe.scd.
//
// REQUIRES MusicScene 0.8.x+ (3D space). MusicScene listens on 7400 and replies to 7401.
//
// USAGE:
//   1. Boot the audio server (evaluating the block below does it).
//   2. Run the Godot project with MusicScene set to 3D (exactly ONE instance).
//   3. Put the cursor in the big ( ... ) block and press Ctrl+Enter (Cmd+Enter).
//   4. To re-wind the pendulum, evaluate the block again; to stop, run CLEANUP.
// =============================================================================

(
s.waitForBoot({

    // A soft marimba/mallet for the pad notes: a quick attack, a short 4th-partial
    // "chime" that decays fast, and a little reverb.
    SynthDef(\padMallet, { |freq = 440, amp = 0.3, pan = 0|
        var env  = EnvGen.kr(Env.perc(0.003, 0.8, 1, -4), doneAction: 2);
        var bar  = SinOsc.ar(freq * 3.93) * 0.25 * EnvGen.kr(Env.perc(0.002, 0.12));
        var sig  = ((SinOsc.ar(freq) * 0.6) + bar) * env * amp;
        sig = sig + (FreeVerb.ar(sig, 0.25, 0.6, 0.4) * 0.3);
        Out.ar(0, Pan2.ar(sig, pan));
    }).add;

    s.sync;

    // ---- configuration ------------------------------------------------------
    ~engine   = NetAddr("127.0.0.1", 7400);
    ~noteFreq = IdentityDictionary[
        \C4 -> 60.midicps, \D4 -> 62.midicps, \E4 -> 64.midicps,
        \G4 -> 67.midicps, \A4 -> 69.midicps
    ];
    // pad id -> stereo pan (left pad = low note on the left, right pad = high on the right)
    ~padPan = IdentityDictionary[
        \padA -> -0.9, \padB -> -0.45, \padC -> 0.0, \padD -> 0.45, \padE -> 0.9
    ];

    // paced OSC send (0.03 s between messages, like the Python `s()`); Routine-only.
    ~snd = { |... m| ~engine.sendMsg(*m); 0.03.wait; };

    // ---- open the reply port + listen ---------------------------------------
    if(thisProcess.openUDPPort(7401),
        { "MusicScene-pendulum: listening for replies on UDP 7401".postln; },
        { "MusicScene-pendulum: UDP 7401 already open (or busy) — continuing".postln; }
    );

    OSCdef(\music_note, { |msg|
        var padid = msg[1].asSymbol, note = msg[2].asSymbol;
        var speed = (msg[3] ? 1.0).abs;
        var pan  = ~padPan[padid] ? 0;
        var freq = ~noteFreq[note] ? 440;
        var amp  = (0.14 + (speed * 0.05)).clip(0.07, 0.34);
        Synth(\padMallet, [\freq, freq, \amp, amp, \pan, pan]);
        ("  ♪ " ++ note ++ "   (" ++ padid ++ ")").postln;
    }, '/music/note', recvPort: 7401);

    // ---- build the linkage + pads -------------------------------------------
    ~build = Routine({
        ~snd.("/ms/scene", "reset");

        // static pivot + two rigid arms + two hinges (both about Z, so the whole
        // linkage swings in the screen plane). Colliders are created automatically
        // when physics is enabled, so the tip can trigger the pad zones out of the box.
        ~snd.("/ms/scene/post", "new", "circle");
        ~snd.("/ms/scene/post/physics", "enable", "static");
        ~snd.("/ms/scene/post", "pos", 0.0, 0.7, 0.0);
        ~snd.("/ms/scene/post/collider", "disabled", 1);   // anchor only: don't bounce the tip off it

        ~snd.("/ms/scene/arm1", "new", "circle");
        ~snd.("/ms/scene/arm1/physics", "enable", "rigid");
        ~snd.("/ms/scene/arm1", "pos", 0.22, 0.7, 0.0);

        ~snd.("/ms/scene/arm2", "new", "circle");
        ~snd.("/ms/scene/arm2/physics", "enable", "rigid");
        ~snd.("/ms/scene/arm2", "pos", 0.44, 0.7, 0.0);    // both arms out to one side = lots of energy

        ~snd.("/ms/joint/h1", "new", "hinge", "post", "arm1");
        ~snd.("/ms/joint/h1", "axis", 0, 0, 1);
        ~snd.("/ms/joint/h2", "new", "hinge", "arm1", "arm2");
        ~snd.("/ms/joint/h2", "axis", 0, 0, 1);

        // five pentatonic pads across the swing; left -> right = low -> high. Each pad
        // fires only for the pendulum tip (arm2); the tip's speed rides along as velocity.
        [
            ["padA", -0.34, 0.50, "C4"],
            ["padB", -0.18, 0.36, "D4"],
            ["padC",  0.00, 0.30, "E4"],
            ["padD",  0.18, 0.36, "G4"],
            ["padE",  0.34, 0.50, "A4"]
        ].do({ |p|
            var pid = p[0], x = p[1], y = p[2], note = p[3];
            ~snd.("/ms/scene/" ++ pid, "new", "rect");
            ~snd.("/ms/scene/" ++ pid ++ "/physics", "enable", "area");
            ~snd.("/ms/scene/" ++ pid ++ "/collider", "rect", 0.16, 0.14);
            ~snd.("/ms/scene/" ++ pid, "pos", x, y, 0.0);
            // only the tip triggers; a small cooldown avoids double-hits on a slow pass
            ~snd.("/ms/scene/" ++ pid ++ "/on", "areaEnter", "/music/note", "other", "arm2", "cooldown", 0.08);
            // payload:  <pad id>  <note (literal)>  <tip speed>
            ~snd.("/ms/scene/" ++ pid ++ "/payload", "areaEnter", "self", "=" ++ note, "otherspeed");
        });

        ~snd.("/ms/physics", "debug", 1);            // show the hinges + pad zones (send "debug 0" to hide)
        ~snd.("/ms/physics", "gravity", 0.0, -1.0, 0.0);
        ~snd.("/ms/physics", "enable", 1);

        "".postln;
        "Double pendulum swinging — ♪ notes stream below.".postln;
        "It settles after a while; re-evaluate the block to wind it up again.".postln;
        "".postln;
    });
    ~build.play;
});
)


// =============================================================================
// CLEANUP — put the cursor inside this block and evaluate it to stop.
// =============================================================================
(
OSCdef(\music_note).free;
~engine.sendMsg("/ms/physics", "enable", 0);   // freeze the pendulum
"Pendulum stopped.".postln;
)
