extends RefCounted
## Runs textual OSC scripts: one OSC-style command per line, '#' comments, blank lines ignored.
## Tokens are typed automatically (int/float/bool); double-quoted tokens stay strings. No
## variables in v1.

var ctx = null


func _init(p_ctx) -> void:
	ctx = p_ctx


func run_text(text: String) -> void:
	for line in text.split("\n"):
		_run_line(line)


func run_file(path: String) -> void:
	if not (FileAccess.file_exists(path) or path.begins_with("res://")):
		ctx.error("load_failed", "/gscore/script/load", "Script not found: " + path)
		return
	var content := FileAccess.get_file_as_string(path)
	if content == "" and not FileAccess.file_exists(path):
		ctx.error("load_failed", "/gscore/script/load", "Could not read script: " + path)
		return
	run_text(content)


func _run_line(line: String) -> void:
	var s := line.strip_edges()
	if s == "" or s.begins_with("#"):
		return
	var tokens := _tokenize(s)
	if tokens.is_empty():
		return
	var address := String(tokens[0]["text"])
	var args: Array = []
	for i in range(1, tokens.size()):
		args.append(_typed(tokens[i]))
	ctx.dispatcher.dispatch(address, args)


func _tokenize(s: String) -> Array:
	var out: Array = []
	var i := 0
	var n := s.length()
	while i < n:
		while i < n and (s[i] == " " or s[i] == "\t"):
			i += 1
		if i >= n:
			break
		if s[i] == "\"":
			i += 1
			var start := i
			while i < n and s[i] != "\"":
				i += 1
			out.append({"text": s.substr(start, i - start), "quoted": true})
			i += 1  # skip closing quote
		else:
			var start := i
			while i < n and not (s[i] == " " or s[i] == "\t"):
				i += 1
			out.append({"text": s.substr(start, i - start), "quoted": false})
	return out


func _typed(tok: Dictionary):
	var t := String(tok["text"])
	if tok.get("quoted", false):
		return t
	if t == "true":
		return true
	if t == "false":
		return false
	if t.is_valid_int():
		return t.to_int()
	if t.is_valid_float():
		return t.to_float()
	return t
