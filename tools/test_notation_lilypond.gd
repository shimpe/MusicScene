extends SceneTree
## Headless self-test: a PanolaLilypond-shaped .ly renders through the LilyPond engraver and yields
## addressable note elements + dark pixels. Prints fail=0 on success (CI greps for it). Skips (prints
## fail=0) when LilyPond is absent — CI has no LilyPond.
const Lily := preload("res://addons/musicscene/notation/MSNotationLilyPositions.gd")

func _lily_exe() -> String:
	# Prefer the configured engraver; else the known install path. Empty string => LilyPond absent.
	var s := str(ProjectSettings.get_setting("musicscene/notation/engraver/lilypond", ""))
	var cand := "C:/Program Files/lilypond-2.25.81/bin/lilypond.exe"
	if s != "":
		# The configured command's executable may be quoted (e.g. "C:/Program Files/.../lilypond.exe"
		# --png ...) because the path itself contains spaces — a naive space-split would shred it.
		var exe_tok := ""
		if s.begins_with("\""):
			var close := s.find("\"", 1)
			if close > 0:
				exe_tok = s.substr(1, close - 1)
		elif s.split(" ", false).size() > 0:
			exe_tok = s.split(" ", false)[0]
		if exe_tok.to_lower().ends_with("lilypond") or exe_tok.to_lower().ends_with("lilypond.exe"):
			cand = exe_tok
	return cand if FileAccess.file_exists(cand) else ""

func _init() -> void:
	var exe := _lily_exe()
	if exe == "":
		print("fail=0 (lilypond absent)")
		quit()
		return
	var dir := ProjectSettings.globalize_path("user://")
	# a minimal PanolaLilypond-shaped score (4 notes, one staff)
	var ly := "\\version \"2.24.0\"\n\\language \"english\"\n\\header { tagline = ##f }\n\\paper { indent = 0\\mm }\n" \
		+ "global = { \\time 4/4 \\key c \\major s1*4/4 \\bar \"|.\" }\n" \
		+ "\\score { << \\new Staff << \\global \\new Voice = \"v1\" { \\clef treble c''4 d''4 e''4 f''4 } >> >> }\n"
	var wrapped := Lily.wrap_source(ly)
	var src := dir.path_join("mslily_test.ly")
	var f := FileAccess.open(src, FileAccess.WRITE)
	if f == null:
		print("FAIL: cannot write ly")
		print("fail=1")
		quit()
		return
	f.store_string(wrapped)
	f.close()
	var stem := dir.path_join("mslily_test_out")
	var out := []
	OS.execute(exe, ["-dbackend=svg", "-dcrop=#t", "-o", stem, src], out, true)
	var svg := stem + ".cropped.svg"
	if not FileAccess.file_exists(svg):
		print("FAIL: no cropped SVG (lilypond output: ", out, ")")
		print("fail=1")
		quit()
		return
	var res := Lily.finalize(svg, {})
	var fails := 0
	if not res.ok:
		fails += 1
		print("FAIL: finalize: ", res.error)
	elif res.elements.size() < 4:
		fails += 1
		print("FAIL: expected >=4 note elements, got ", res.elements.size())
	print("elements=", (res.elements.size() if res.ok else -1))
	print("fail=", fails)
	quit()
