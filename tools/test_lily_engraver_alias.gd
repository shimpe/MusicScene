extends SceneTree
## Regression guard for the "blank LilyPond notation" bug: MSScore/OSC may name the LilyPond engine
## "ly" OR "lilypond", but the documented project setting key is notation/engraver/lilypond. Both
## aliases MUST resolve to the same engraver, or the render silently fails (blank score). Needs no
## LilyPond install (pure setting lookup), so it runs in CI. Prints fail=0 on success.
const ExternalBackend := preload("res://addons/musicscene/notation/MSNotationBackendMusicXML.gd")

func _init() -> void:
	ProjectSettings.set_setting("musicscene/notation/engraver/lilypond",
		"\"/opt/lilypond/bin/lilypond\" {input} {output}")
	var by_ly := ExternalBackend.engraver_exe("ly")
	var by_name := ExternalBackend.engraver_exe("lilypond")
	var fails := 0
	if by_name == "":
		fails += 1
		print("FAIL: engraver_exe('lilypond') empty despite the setting configured")
	if by_ly != by_name:
		fails += 1
		print("FAIL: 'ly' -> '%s' but 'lilypond' -> '%s' (aliases must resolve identically)" % [by_ly, by_name])
	print("alias_ly=", by_ly)
	print("fail=", fails)
	quit()
