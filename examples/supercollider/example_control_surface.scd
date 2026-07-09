/*
Sound engine for a MusicControls panel exposed through MusicScene (INSTRUMENT_UI_TUTORIAL.md).

The Godot project contains no glue code at all: the panel is a plain scene of MusicControls
nodes, each carrying an OscExposable child. Everything below -- which Godot signal becomes which
musical OSC address -- is configured from here, over OSC, at startup.

    sclang --> 127.0.0.1:7400    /ms/... setup, and /ms/scene/<id> call|prop to drive the UI
    Godot  --> 127.0.0.1:57120   /synth/... forwarded control signals

USAGE
    1. Run the Godot project (panel.tscn as main scene, both addons enabled).
    2. Boot this file in SuperCollider.
    3. Play the on-screen keyboard and turn the knobs.

Requires the MusicControls addon (https://github.com/shimpe/MusicControls) alongside MusicScene.
*/

(
s.waitForBoot({
	var ms = NetAddr("127.0.0.1", 7400);       // MusicScene's listen port

	~params = IdentityDictionary[
		\cutoff -> 1200, \reso -> 15, \wave -> 1, \filterOn -> 1
	];
	~voices = IdentityDictionary.new;          // midi note -> Synth

	SynthDef(\surfaceVoice, { |out = 0, note = 60, vel = 0.8, gate = 1,
		wave = 1, cutoff = 1200, reso = 15, filterOn = 1|
		var freq = note.midicps;
		var sig = Select.ar(wave.clip(0, 3), [
			SinOsc.ar(freq), Saw.ar(freq), Pulse.ar(freq, 0.5), WhiteNoise.ar
		]);
		var rq = (1 - (reso / 100)).clip(0.05, 1.0);
		var env = EnvGen.kr(Env.adsr(0.01, 0.15, 0.7, 0.3), gate, doneAction: 2);
		sig = Select.ar(filterOn.clip(0, 1), [sig, RLPF.ar(sig, cutoff.clip(20, 20000), rq)]);
		Out.ar(out, Pan2.ar(sig * vel * env * 0.2, 0));
	}).add;

	SynthDef(\surfaceMeter, { |rate = 30|
		var sig = In.ar(0, 2);
		SendReply.kr(Impulse.kr(rate), '/level', [Amplitude.kr(sig[0]), Amplitude.kr(sig[1])]);
	}).add;

	s.sync;
	~meter = Synth(\surfaceMeter, addAction: \addToTail);

	// --- tell MusicScene where to send, and what to forward -----------------

	// By default MusicScene replies on 7401. Point everything at sclang's own port instead.
	ms.sendMsg("/ms/app/output", "127.0.0.1", NetAddr.langPort);

	// "When this control emits that Godot signal, send me this OSC message."
	// Payload tokens: self = the osc_id, value = the first signal arg, argN = the Nth.
	ms.sendMsg("/ms/scene/cutoff/signal", "value_changed", "/synth/param", "payload", "self", "value");
	ms.sendMsg("/ms/scene/reso/signal",   "value_changed", "/synth/param", "payload", "self", "value");
	ms.sendMsg("/ms/scene/wave/signal",   "value_changed", "/synth/wave",  "payload", "value");
	ms.sendMsg("/ms/scene/filter/signal", "enable_toggled", "/synth/filter", "payload", "value");
	ms.sendMsg("/ms/scene/keys/signal",   "note_pressed",  "/synth/note/on",  "payload", "arg0", "arg1");
	ms.sendMsg("/ms/scene/keys/signal",   "note_released", "/synth/note/off", "payload", "arg0");

	// --- panel -> engine ---------------------------------------------------

	// The osc_id travels as the first argument, so one handler serves every knob.
	OSCdef(\param, { |msg|
		var id = msg[1].asSymbol, value = msg[2];
		~params[id] = value;
		~voices.do { |voice| voice.set(id, value) };
		"param % = %".format(id, value.round(0.001)).postln;
	}, '/synth/param');

	OSCdef(\wave, { |msg|
		~params[\wave] = msg[1];
		~voices.do { |voice| voice.set(\wave, msg[1]) };
		"wave = %".format(msg[1]).postln;
	}, '/synth/wave');

	// ModulePanel.enable_toggled carries a real OSC boolean, and a Boolean is not a number in
	// sclang -- `true > 0` raises "not understood". Convert before it reaches the server.
	OSCdef(\filter, { |msg|
		var on = if (msg[1] == true or: { msg[1] == 1 }) { 1 } { 0 };
		~params[\filterOn] = on;
		~voices.do { |voice| voice.set(\filterOn, on) };
		"filter %".format(if (on > 0) { "on" } { "bypassed" }).postln;
	}, '/synth/filter');

	OSCdef(\noteOn, { |msg|
		var note = msg[1].asInteger, vel = msg[2];
		~voices[note] !? { |old| old.set(\gate, 0) };
		~voices[note] = Synth(\surfaceVoice,
			[\note, note, \vel, vel] ++ ~params.getPairs, ~meter, \addBefore);
		ms.sendMsg("/ms/scene/keys", "call", "highlight_note", note, 1);   // light the key
		"note on  %".format(note).postln;
	}, '/synth/note/on');

	OSCdef(\noteOff, { |msg|
		var note = msg[1].asInteger;
		~voices[note] !? { |voice| voice.set(\gate, 0) };
		~voices.removeAt(note);
		ms.sendMsg("/ms/scene/keys", "call", "highlight_note", note, 0);
		"note off %".format(note).postln;
	}, '/synth/note/off');

	// --- engine -> panel ---------------------------------------------------

	// `call` invokes a method listed in the control's OscExposable.osc_methods.
	OSCdef(\level, { |msg|
		ms.sendMsg("/ms/scene/meter", "call", "set_stereo_level", msg[3], msg[4]);
	}, '/level');

	// `prop` writes a property listed in osc_properties. Use it to load a preset into the UI:
	// the knob moves, and echoes one /synth/param back at us (harmless -- same value, once).
	~preset = { |cutoff = 3000, reso = 40|
		ms.sendMsg("/ms/scene/cutoff", "prop", "value", cutoff);
		ms.sendMsg("/ms/scene/reso", "prop", "value", reso);
	};

	// MusicScene answers mistakes instead of failing silently -- always listen for this.
	OSCdef(\msError, { |msg| "MusicScene error: %".format(msg[1..]).warn }, '/ms/error');

	CmdPeriod.doOnce({ ~voices.do(_.free); OSCdef.freeAll });
	"control surface ready — play the Godot panel.  ~preset.(500, 80) to move the knobs".postln;
});
)
