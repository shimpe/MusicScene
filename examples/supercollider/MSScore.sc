/*
MSScore — write a score in Panola, then show + play + follow it in MusicScene, with one call.

    (
    ~score = MSScore(
        voices: [ "c5_4 e5 g5 c6", "<c4_4 e4 g4> <c4_4 e4 g4> r_4 <b3_4 d4 g4>", "c3_2 g3_2" ],
        clefs:  [\treble, \treble, \bass],
        meter: "4/4", key: \Cmajor, braces: [[2,3]], tempo: 84, space: "2d", scale: 0.9
    );
    )
    ~score.play;   // display the notation, play the voices, follow with the cursor
    ~score.stop;   // stop, free synths, clear

`voices` may be Panola strings (wrapped automatically) or ready Panola instances. `scale` sizes the score
in the scene (raise it if the notation looks too small); it defaults to 2.5 in "3d" and 0.7 in "2d". The
MEI comes from Panola.scoreAsMEI (see the Panola quark).

The cursor is note-accurate and needs no reply round-trip: MusicScene is made `addressable`, so it knows
every note's on-page position (and which staff-system it is in, since Verovio may wrap a wide score onto
several lines). MSScore just tells it "the cursor is at beat N" on its own audio clock via `cursor at`;
MusicScene maps that beat to the right note position and confines the line to that note's system. One
clock drives both audio and cursor, so they stay in sync.

INSTALL: put this file on SuperCollider's class path (e.g. copy to your Extensions folder, or add
`examples/supercollider` via Preferences), then recompile the class library. Requires the Panola quark
with PanolaMEI, and MusicScene running (Verovio working; `pip install verovio`).
*/
MSScore {
	var <voices, <clefs, <meter, <key, <braces, <tempo, <id, <space, <instruments, <scale;
	var <engine, <clock, <player, <cursorRoutine, <totalBeats, <showDelay;

	*new { | voices, clefs, meter = "4/4", key = \Cmajor, braces, tempo = 84, instruments,
		id = "score", space = "2d", scale, showDelay = 1.0, host = "127.0.0.1", listenPort = 7400 |
		^super.new.init(voices, clefs, meter, key, braces, tempo, instruments, id, space, scale, showDelay, host, listenPort);
	}

	init { | v, cl, m, k, br, t, instr, i, sp, sc, sd, host, lport |
		voices = v.collect({ |x| x.isKindOf(Panola).if({ x }, { Panola(x) }) });
		clefs = cl ? voices.collect({ \treble });
		meter = m; key = k; braces = br; tempo = t; id = i; space = sp;
		instruments = instr ? voices.collect({ \default });
		scale = sc ? (sp == "3d").if({ 2.5 }, { 0.7 });   // pass `scale:` to enlarge/shrink the score
		showDelay = sd;                                    // seconds to let the notation render before playing
		engine = NetAddr(host, lport);
		totalBeats = voices.collect({ |p| p.totalDuration }).maxItem;
	}

	// The MEI document for this score (also usable standalone / to write to a .mei file).
	mei { ^Panola.scoreAsMEI(voices, meter, key, clefs, braces) }

	// Display the notation (addressable, so MusicScene knows note positions). Non-blocking.
	show {
		var m = this.mei;
		Routine({
			var snd = { |... a| engine.sendMsg(*a); 0.02.wait };
			snd.("/ms/scene/" ++ id, "new", "notation");
			snd.("/ms/scene/" ++ id, "background", "white");
			snd.("/ms/scene/" ++ id, "scale", scale);
			if (space == "3d") { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0, 0.0) } { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0) };
			snd.("/ms/scene/" ++ id ++ "/cursor", "show", 1);
			snd.("/ms/scene/" ++ id, "addressable", 1);
			snd.("/ms/scene/" ++ id, "notationData", "mei", m);
		}).play;
	}

	// Show, wait for the notation to render, then play the voices and follow with the cursor.
	play {
		this.show;
		Routine({ showDelay.wait; this.pr_startPlayback; }).play;
	}

	stop {
		clock.notNil.if({ clock.stop; clock = nil });
		player.notNil.if({ player.stop });
		cursorRoutine.notNil.if({ cursorRoutine.stop });
		Server.default.freeAll;
		engine.sendMsg("/ms/scene", "clear");
	}

	pr_startPlayback {
		var startBeat;
		clock = TempoClock(tempo / 60);
		player = Ppar(voices.collect({ |p, i| p.asPbind(instruments[i], include_tempo: false) })).play(clock, quant: 0);
		startBeat = clock.beats;
		// on the SAME clock as the audio, tell MusicScene where the cursor is (whole-note time = beats/4);
		// MusicScene maps it to the note position + system. ~16 updates per beat for smooth motion.
		cursorRoutine = Routine({
			while { (clock.beats - startBeat) <= (totalBeats + 0.5) } {
				engine.sendMsg("/ms/scene/" ++ id ++ "/cursor", "at", (clock.beats - startBeat) / 4);
				0.0625.wait;
			};
		}).play(clock, quant: 0);
	}
}
