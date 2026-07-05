/*
MSScore — write a score in Panola, then show + play + follow it in MusicScene, with one call.

    (
    ~score = MSScore(
        voices: [ "c5_4 e2 g4 | a2 g4 f", "<c4_4 e4 g4> <c4_4 e4 g4> r_4 <b3_4 d4 g4>", "c3_2 g2_2" ],
        clefs:  [\treble, \treble, \bass],
        meter: "4/4", key: \Cmajor, braces: [[2,3]], tempo: 84, space: "2d"
    );
    )
    ~score.play;   // display the notation, play the voices, follow with the cursor
    ~score.stop;   // stop, free synths, clear

`voices` may be Panola strings (wrapped automatically) or ready Panola instances. The MEI comes from
Panola.scoreAsMEI (see the Panola quark). The cursor is note-accurate: MusicScene is made `addressable`,
so it reports each note's on-page position (`elements`); MSScore replays that timemap on the same clock
as playback. If `elements` never arrives (e.g. Verovio missing), the cursor falls back to a linear sweep.

INSTALL: put this file on SuperCollider's class path (e.g. copy to your Extensions folder, or add
`examples/supercollider` via Preferences), then recompile the class library. Requires the Panola quark
with PanolaMEI, and MusicScene running (Verovio working; `pip install verovio`).
*/
MSScore {
	var <voices, <clefs, <meter, <key, <braces, <tempo, <id, <space, <instruments, <scoreScale;
	var <engine, <replyPort, <clock, <player, <cursorRoutine, <elements, <oscdef, <totalBeats;

	*new { | voices, clefs, meter = "4/4", key = \Cmajor, braces, tempo = 84, instruments,
		id = "score", space = "2d", scoreScale, host = "127.0.0.1", listenPort = 7400, replyPort = 7401 |
		^super.new.init(voices, clefs, meter, key, braces, tempo, instruments, id, space, scoreScale, host, listenPort, replyPort);
	}

	init { | v, cl, m, k, br, t, instr, i, sp, sc, host, lport, rport |
		voices = v.collect({ |x| x.isKindOf(Panola).if({ x }, { Panola(x) }) });
		clefs = cl ? voices.collect({ \treble });
		meter = m; key = k; braces = br; tempo = t; id = i; space = sp;
		instruments = instr ? voices.collect({ \default });
		scoreScale = sc ? (sp == "3d").if({ 1.5 }, { 0.6 });
		engine = NetAddr(host, lport); replyPort = rport;
		elements = [];
		totalBeats = voices.collect({ |p| p.totalDuration }).maxItem;
	}

	// The MEI document for this score (also usable standalone / to write to a .mei file).
	mei { ^Panola.scoreAsMEI(voices, meter, key, clefs, braces) }

	// Display the notation and start listening for note positions. Non-blocking.
	show {
		var m = this.mei;
		this.pr_listen;
		elements = [];
		Routine({
			var snd = { |... a| engine.sendMsg(*a); 0.02.wait };
			snd.("/ms/scene/" ++ id, "new", "notation");
			snd.("/ms/scene/" ++ id, "background", "white");
			snd.("/ms/scene/" ++ id, "scale", scoreScale);
			if (space == "3d") { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0, 0.0) } { snd.("/ms/scene/" ++ id, "pos", 0.0, 0.0) };
			snd.("/ms/scene/" ++ id ++ "/cursor", "show", 1);
			snd.("/ms/scene/" ++ id, "addressable", 1);
			snd.("/ms/scene/" ++ id, "notationData", "mei", m);
			// nudge for the note-position reply once it has rendered
			0.6.wait;
			6.do({ if (elements.size == 0) { engine.sendMsg("/ms/scene/" ++ id, "elements"); 0.4.wait } });
		}).play;
	}

	// Show, then (once positions arrive) play the voices and follow with the cursor.
	play {
		this.show;
		Routine({
			var tries = 0;
			0.6.wait;
			while { (elements.size == 0) and: { tries < 8 } } { tries = tries + 1; 0.35.wait };
			this.pr_startPlayback;
		}).play;
	}

	stop {
		clock.notNil.if({ clock.stop; clock = nil });
		player.notNil.if({ player.stop });
		cursorRoutine.notNil.if({ cursorRoutine.stop });
		Server.default.freeAll;
		oscdef.notNil.if({ oscdef.free; oscdef = nil });
		engine.sendMsg("/ms/scene", "clear");
	}

	// ---- private ---------------------------------------------------------
	pr_listen {
		thisProcess.openUDPPort(replyPort);
		oscdef = OSCdef(("msScore_" ++ id).asSymbol, { |msg|
			// /ms/reply "elements" <id> [<index> <when> <line> <char> <u> <v>] ...
			if ((msg[1].asSymbol == \elements) and: { msg[2].asSymbol == id.asSymbol }) {
				var items = msg.copyRange(3, msg.size - 1), out = [];
				(items.size div: 6).do({ |k| out = out.add([items[(k*6)+1], items[(k*6)+4]]) });   // [when, u]
				elements = out.sort({ |a, b| a[0] < b[0] });
			};
		}, '/ms/reply', recvPort: replyPort);
	}

	pr_startPlayback {
		clock = TempoClock(tempo / 60);
		player = Ppar(voices.collect({ |p, i| p.asPbind(instruments[i], include_tempo: false) })).play(clock, quant: 0);
		cursorRoutine = Routine({
			var last = 0.0;
			if (elements.size > 0) {                       // note-accurate: replay the timemap
				elements.do({ |e|
					var beat = e[0] * 4;                   // `when` is in whole notes -> quarter beats
					(beat - last).max(0).wait; last = beat;
					engine.sendMsg("/ms/scene/" ++ id ++ "/cursor", "pos", e[1], 0.5);
				});
			} {                                            // fallback: linear sweep across the page
				var steps = 96, dur = totalBeats / 96;
				(steps + 1).do({ |kk|
					engine.sendMsg("/ms/scene/" ++ id ++ "/cursor", "pos", 0.12 + ((kk / steps) * 0.86), 0.5);
					if (kk < steps) { dur.wait };
				});
			};
		}).play(clock);
	}
}
