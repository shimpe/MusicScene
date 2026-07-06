// example_msscore_midi.scd
//
// MSScore plays each voice either on a built-in SuperCollider synth (\internal, the default)
// or on an external/hardware synth over MIDI (\midi). A single score can mix them.
//
// As written, BOTH voices play on SC synths, so this runs with no hardware. To send the bass
// (voice 2) to a hardware synth, open your device in the OPTIONAL block, then switch ~backends
// / ~midiOut in the score block as noted.

// ---- OPTIONAL: open your MIDI device (edit the names for your hardware) --------------------
(
if (MIDIClient.initialized.not) { MIDIClient.init };
~integra = MIDIOut.newByName("INTEGRA-7", "INTEGRA-7");   // <- change to your device
)


// ---- boot the audio server (needed for the \internal voices) ------------------------------
(
s.boot;
)

// ---- build the score ----------------------------------------------------------------------
(
~backends = [\midi, \midi];   // one of \internal  or \midi
~midiOut  = ~integra;

// To play the bass over MIDI instead, comment the two lines above and uncomment these
// (after opening ~integra in the OPTIONAL block):
// ~backends = [\internal, \midi];
// ~midiOut  = ~integra;

~gDEFAULT_LEGATO = 0.9;
~legato = ~gDEFAULT_LEGATO;

~score = MSScore(
	voices:   [ "(c5_4@pdur[0.9]@dyn^mf^@slur^start^ e5 g5 c6 g5_8@slur^end^ f e d e_4@art^stacc^ c_4@art^stacc^)*8", "(c3_2@pdur[0.9] g3_2 d3_4 g3 c3_2)*8" ],
	clefs:    [ \treble, \bass ],
	meter:    "4/4",
	key:      \Cmajor,
	braces:   [ [1, 2] ],
	tempo:    168,
	space:    "2d",
	backends: ~backends,
	midiOut:  ~midiOut,
	channels: [ 0, 1 ],       // used only by \midi voices
	showCursor: true,
	scale:1.5,
	// per-note MIDI control example (sustain pedal from a @ped property) on a \midi voice:
	wrap: [
		// voice 1
		{
			|pat, i|
			Pbindf(pat, \handle, Pfunc {
				|ev|
				if (ev[\art] == \stacc) {
					ev[\legato] = 0.5;
				} {
					if (ev[\slur] == \start) {
						~legato = 1.5;
					};
					if (ev[\slur] == \endstart) {
						~legato = ~gDEFAULT_LEGATO;
					};
					if (ev[\slur] == \end) {
						~legato = ~gDEFAULT_LEGATO;
					};
					ev[\legato] = ~legato;
				};
				0})
		},
		// voice 2
		nil
	]
);
CmdPeriod.doOnce({
	~score.stop;   // stop (all-notes-off for MIDI voices), free synths, clear the scene
});
)
~score.play;   // display the notation, play the voices, follow with the cursor

