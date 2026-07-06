// example_msscore_midi.scd
//
// MSScore plays each voice either on a built-in SuperCollider synth (\internal, the default)
// or on an external/hardware synth over MIDI (\midi). A single score can mix them.
//
// As written, BOTH voices play on SC synths, so this runs with no hardware. To send the bass
// (voice 2) to a hardware synth, open your device in the OPTIONAL block, then switch ~backends
// / ~midiOut in the score block as noted.

// ---- OPTIONAL: open your MIDI device (edit the names for your hardware) --------------------
/*
(
if (MIDIClient.initialized.not) { MIDIClient.init };
~integra = MIDIOut.newByName("INTEGRA-7", "INTEGRA-7 MIDI 1");   // <- change to your device
)
*/

// ---- boot the audio server (needed for the \internal voices) ------------------------------
(
s.boot;
)

// ---- build the score ----------------------------------------------------------------------
(
~backends = [\internal, \internal];   // all-internal default
~midiOut  = nil;

// To play the bass over MIDI instead, comment the two lines above and uncomment these
// (after opening ~integra in the OPTIONAL block):
// ~backends = [\internal, \midi];
// ~midiOut  = ~integra;

~score = MSScore(
    voices:   [ "c5_4@dyn^mf^ e5 g5 c6", "c3_2 g3_2" ],
    clefs:    [ \treble, \bass ],
    meter:    "4/4",
    key:      \Cmajor,
    braces:   [ [1, 2] ],
    tempo:    84,
    space:    "2d",
    backends: ~backends,
    midiOut:  ~midiOut,
    channels: [ 0, 1 ],       // used only by \midi voices
    // per-note MIDI control example (sustain pedal from a @ped property) on a \midi voice:
    // wrap: [ nil, { |pat, i| Pbindf(pat, \handle, Pfunc { |ev| ~integra.control(ev[\chan], 64, (ev[\ped] ? 0).asInteger) }) } ]
);
)

~score.play;   // display the notation, play the voices, follow with the cursor
~score.stop;   // stop (all-notes-off for MIDI voices), free synths, clear the scene
