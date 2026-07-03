# Multi-port OSC Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let gscore fan its outbound OSC (replies + events) to a configurable list of ports (default stays the single port 7401), so a client and monitors can each receive a copy.

**Architecture:** All outbound OSC funnels through `OscServer._send_bytes()`; change the scalar `_send_port` to a `_send_ports: PackedInt32Array` and loop it there. Configure the list via a new `network/send_ports` project setting (parsed at startup) and by extending the runtime `/gscore/app/output <host> <port…>` command. Default (empty setting, single-port command) is byte-for-byte identical to today.

**Tech Stack:** Godot 4.7, GDScript. Headless `SceneTree` self-tests via `--script`, wired into GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-07-03-multi-port-osc-output-design.md`

**Conventions:**
- GDScript files use **TAB** indentation — copy the code blocks verbatim (tabs, not spaces).
- `godot` below means the Windows console build:
  `/d/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- Run tests with a timeout and redirect to the scratchpad (SceneTree tests have no self-timeout):
  `timeout 90 "<godot>" --headless --path . --script res://tools/<t>.gd > "<scratchpad>/<t>.log" 2>&1; echo "exit=$?"; cat "<scratchpad>/<t>.log"`
  where `<scratchpad>` = `C:/Scripts/Temp/claude/D--Projects-MusicScene/4ede0533-d976-4a03-a010-fa7d8dd4b832/scratchpad`.
- Tests follow the existing pattern (`tools/test_camera.gd`): `extends SceneTree`, a `_process` frame counter, `check(cond, msg)`, a final `DONE pass=N fail=M` line. CI greps `fail=0` and the absence of `FAIL:`.
- New `tools/*.gd` test files need a committed `.gd.uid` sidecar. Generate it by running `<godot> --headless --import --path .` once after creating the file, then `git add` both the `.gd` and the `.gd.uid`.

---

### Task 1: `OscServer` — port-list state, parse/normalize helpers, and fan-out

Converts the single output port to a normalized list and fans every outbound datagram across it. Also updates the two call sites minimally (still single-port) so the project keeps compiling; Tasks 2 and 3 upgrade those call sites to expose the list.

**Files:**
- Modify: `addons/gscore_osc/core/OscServer.gd`
- Modify: `addons/gscore_osc/nodes/GScoreRoot.gd` (call-site signature fix only)
- Modify: `addons/gscore_osc/core/OscDispatcher.gd` (call-site signature fix only)
- Test: `tools/test_osc_output.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/test_osc_output.gd`:

```gdscript
extends SceneTree
## Headless test for OscServer's multi-port output: the pure parse/normalize helpers
## plus a real loopback check that one send() reaches TWO bound receiver sockets.
##   <godot> --headless --path . --script res://tools/test_osc_output.gd
const OscServer := preload("res://addons/gscore_osc/core/OscServer.gd")

var _f := 0
var _pass := 0
var _fail := 0
var _srv
var _rx_a: PacketPeerUDP
var _rx_b: PacketPeerUDP

const LISTEN := 7490
const PA := 7491
const PB := 7492

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _unit_tests() -> void:
	check(Array(OscServer.parse_ports("7401, 7402 7403")) == [7401, 7402, 7403], "parse csv + spaces")
	check(Array(OscServer.parse_ports("7401 abc 0 70000 7402")) == [7401, 7402], "parse drops invalid/out-of-range")
	check(Array(OscServer.parse_ports("")) == [], "parse empty -> []")
	check(Array(OscServer._normalize_ports([7401, 7401, 7402])) == [7401, 7402], "normalize de-dupes")
	check(Array(OscServer._normalize_ports([])) == [7401], "normalize empty -> [7401]")
	check(Array(OscServer.startup_ports("", 7401)) == [7401], "startup empty setting -> [send_port]")
	check(Array(OscServer.startup_ports("7402, 7403", 7401)) == [7402, 7403], "startup parses setting")
	check(Array(OscServer.startup_ports("garbage", 7401)) == [7401], "startup garbage setting -> [send_port]")

func _setup_loopback() -> void:
	_srv = OscServer.new()
	_srv.verbose = false
	var ok = _srv.start(LISTEN, "127.0.0.1", PackedInt32Array([PA]))
	check(ok, "server binds listen port")
	_srv.set_output("127.0.0.1", PackedInt32Array([PA, PA, 0, PB]))   # dupes/invalid get normalized away
	check(Array(_srv.get_send_ports()) == [PA, PB], "set_output normalizes to [PA, PB]")
	_rx_a = PacketPeerUDP.new(); _rx_a.bind(PA, "*")
	_rx_b = PacketPeerUDP.new(); _rx_b.bind(PB, "*")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		_unit_tests()
		_setup_loopback()
		return false
	# From here on, resend each frame (loopback is reliable, but this avoids a first-frame race)
	# and check both receivers eventually see the fanned-out message.
	_srv.send("/x", [1])
	var got_a := _rx_a.get_available_packet_count() > 0
	var got_b := _rx_b.get_available_packet_count() > 0
	if got_a and got_b:
		check(true, "one send() reached BOTH ports (fan-out)")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	if _f >= 120:
		check(got_a, "port A received")
		check(got_b, "port B received")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run the test (see Conventions). Expected: it fails to run / errors because `OscServer.parse_ports` (and the array-typed `start`/`set_output`) don't exist yet — no `DONE pass=… fail=0` line. Confirm it fails for that reason before implementing.

- [ ] **Step 3: Implement the OscServer changes**

In `addons/gscore_osc/core/OscServer.gd`:

(a) Update the header comment line 5 from:
```gdscript
## Replies and events are sent to the most recent sender's IP on the configured `send_port`
```
to:
```gdscript
## Replies and events are sent to the most recent sender's IP on each configured `send_port`
```

(b) Replace the state line:
```gdscript
var _send_port: int = 7401
```
with:
```gdscript
var _send_ports: PackedInt32Array = PackedInt32Array([7401])
```

(c) Replace `start()` entirely:
```gdscript
func start(listen_port: int, send_host: String, send_ports: PackedInt32Array) -> bool:
	stop()
	_listen_port = listen_port
	_send_host = send_host
	_send_ports = _normalize_ports(send_ports)
	var err := _udp.bind(_listen_port, "*")
	if err != OK:
		push_error("[GScoreOSC] Failed to bind UDP port %d (error %d)" % [_listen_port, err])
		_running = false
		return false
	_running = true
	if verbose:
		print("[GScoreOSC] OSC server listening on udp:%d, replies -> %s:%s"
			% [_listen_port, _send_host, str(Array(_send_ports))])
	return true
```

(d) Replace `set_output()` entirely:
```gdscript
func set_output(host: String, send_ports: PackedInt32Array) -> void:
	_send_host = host
	_send_ports = _normalize_ports(send_ports)
	if verbose:
		print("[GScoreOSC] OSC output set to %s:%s" % [host, str(Array(_send_ports))])
```

(e) Add these helpers right after `set_output()`:
```gdscript
func get_send_ports() -> PackedInt32Array:
	return _send_ports


## Parse a "7401, 7402 7403"-style setting string into valid ports (may contain duplicates).
static func parse_ports(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var norm := text.replace(",", " ").replace("\t", " ").replace("\n", " ")
	for tok in norm.split(" ", false):
		var t := tok.strip_edges()
		if t.is_valid_int():
			var p := t.to_int()
			if p >= 1 and p <= 65535:
				out.append(p)
	return out


## De-duplicate (order-preserving), drop out-of-range ports, and never return empty.
static func _normalize_ports(raw) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in raw:
		var p := int(v)
		if p >= 1 and p <= 65535 and not (p in out):
			out.append(p)
	if out.is_empty():
		out.append(7401)
	return out


## Resolve the startup port list: the `send_ports` string if it yields any, else [send_port].
static func startup_ports(send_ports_str: String, send_port: int) -> PackedInt32Array:
	if send_ports_str.strip_edges() != "":
		var parsed := parse_ports(send_ports_str)
		if not parsed.is_empty():
			return parsed
	return PackedInt32Array([send_port])
```

(f) Replace `_send_bytes()` entirely (fan-out):
```gdscript
func _send_bytes(bytes: PackedByteArray) -> void:
	if not _running:
		return
	var host := _last_sender_ip if _last_sender_ip != "" else _send_host
	if host == "":
		host = "127.0.0.1"
	for port in _send_ports:
		if _udp.set_dest_address(host, port) == OK:
			_udp.put_packet(bytes)
```

- [ ] **Step 4: Fix the two call sites so the project compiles (still single-port)**

In `addons/gscore_osc/nodes/GScoreRoot.gd`, change the third argument of the `server.start(...)` call from:
```gdscript
			int(_setting("network/send_port", 7401)))
```
to:
```gdscript
			PackedInt32Array([int(_setting("network/send_port", 7401))]))
```

In `addons/gscore_osc/core/OscDispatcher.gd`, change the `"output":` case from:
```gdscript
		"output":
			ctx.server.set_output(_s(args, 0), int(_f(args, 1, 7401)))
```
to:
```gdscript
		"output":
			ctx.server.set_output(_s(args, 0), PackedInt32Array([int(_f(args, 1, 7401))]))
```

- [ ] **Step 5: Generate the `.uid`, verify no parse errors, and run the test**

Generate the sidecar and check the whole project still compiles:
```
timeout 120 "<godot>" --headless --import --path . > "<scratchpad>/imp.log" 2>&1; echo "exit=$?"; grep -iE "SCRIPT ERROR|Parse Error" "<scratchpad>/imp.log" || echo "no parse errors"
```
Confirm `tools/test_osc_output.gd.uid` now exists. Then run the test (see Conventions). Expected final line: `DONE pass=12 fail=0`, and no `FAIL:` line.

- [ ] **Step 6: Commit**

```bash
git add addons/gscore_osc/core/OscServer.gd addons/gscore_osc/nodes/GScoreRoot.gd addons/gscore_osc/core/OscDispatcher.gd tools/test_osc_output.gd tools/test_osc_output.gd.uid
git commit -m "feat(osc): fan outbound OSC across a list of ports (default [7401])"
```

---

### Task 2: Startup config — `network/send_ports` setting

Wires the new project setting through `OscServer.startup_ports` so the startup list can be more than one port. Default (empty setting) stays `[send_port]` = `[7401]`.

**Files:**
- Modify: `addons/gscore_osc/nodes/GScoreRoot.gd`

- [ ] **Step 1: Replace the autostart block**

In `addons/gscore_osc/nodes/GScoreRoot.gd`, replace the whole autostart block that Task 1 left as:
```gdscript
	if bool(_setting("network/autostart", true)):
		server.start(
			int(_setting("network/listen_port", 7400)),
			String(_setting("network/send_host", "127.0.0.1")),
			PackedInt32Array([int(_setting("network/send_port", 7401))]))
```
with:
```gdscript
	if bool(_setting("network/autostart", true)):
		var send_ports := OscServer.startup_ports(
			String(_setting("network/send_ports", "")),
			int(_setting("network/send_port", 7401)))
		server.start(
			int(_setting("network/listen_port", 7400)),
			String(_setting("network/send_host", "127.0.0.1")),
			send_ports)
```
(`OscServer` is already preloaded as a const at the top of `GScoreRoot.gd`, so the static call resolves.)

- [ ] **Step 2: Verify no parse errors and that the default is unchanged**

Run the import check (as in Task 1 Step 5) — expect no parse errors. Then run the Task 1 test again — the `startup_ports("", 7401) == [7401]` assertion already covers the default, and this change adds no new observable behavior when `network/send_ports` is unset. Expected: `DONE pass=12 fail=0`.

- [ ] **Step 3: Commit**

```bash
git add addons/gscore_osc/nodes/GScoreRoot.gd
git commit -m "feat(osc): read network/send_ports at startup (empty -> single default)"
```

---

### Task 3: Runtime command — `/gscore/app/output <host> <port…>` + `/gscore/info` ports

Extends the existing `output` app command to accept any number of ports, and exposes the active ports in the `/gscore/info` reply via a small testable `_info_payload()` seam.

**Files:**
- Modify: `addons/gscore_osc/core/OscDispatcher.gd`
- Test: `tools/test_osc_output_cmd.gd` (create)

- [ ] **Step 1: Write the failing test**

Create `tools/test_osc_output_cmd.gd`:

```gdscript
extends SceneTree
## Headless test for the runtime output command + /gscore/info output ports (uses the autoload).
##   <godot> --headless --path . --script res://tools/test_osc_output_cmd.gd
var _f := 0
var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond: _pass += 1; print("PASS: ", msg)
	else: _fail += 1; print("FAIL: ", msg)

func _process(_d: float) -> bool:
	_f += 1
	var osc = root.get_node_or_null("GScoreOSC")
	if osc == null:
		print("FAIL: autoload missing"); return true
	if _f == 2:
		var d = osc.dispatcher
		d.dispatch("/gscore/app/output", ["127.0.0.1", 7401, 7402, 7403])
		check(Array(osc.server.get_send_ports()) == [7401, 7402, 7403], "output sets three ports")
		d.dispatch("/gscore/app/output", ["127.0.0.1", 7411])
		check(Array(osc.server.get_send_ports()) == [7411], "output with one port")
		d.dispatch("/gscore/app/output", ["127.0.0.1"])   # no ports
		check(Array(osc.server.get_send_ports()) == [7411], "output with no port leaves the list unchanged")
		var payload = osc.dispatcher._info_payload()
		check(payload.has("output") and payload.has(7411), "/gscore/info payload includes the output ports")
		print("DONE pass=%d fail=%d" % [_pass, _fail])
		return true
	return false
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run it (Conventions). Expected: fails — the multi-port `output` command isn't implemented yet (it currently reads only one port, so `get_send_ports()` won't equal `[7401, 7402, 7403]`) and `_info_payload()` doesn't exist. No `DONE … fail=0`.

- [ ] **Step 3: Implement the multi-port `output` command**

In `addons/gscore_osc/core/OscDispatcher.gd`, replace the `"output":` case (the single-port version Task 1 left) with:
```gdscript
			"output":
				var out_host := _s(args, 0)
				var out_ports := PackedInt32Array()
				for i in range(1, args.size()):
					out_ports.append(int(_f(args, i)))
				if out_ports.is_empty():
					ctx.error("bad_arguments", "/gscore/app/output", "output needs at least one port")
				else:
					ctx.server.set_output(out_host, out_ports)
```

- [ ] **Step 4: Implement the `/gscore/info` port list**

In the same file, replace `_handle_info()`:
```gdscript
func _handle_info() -> void:
	ctx.reply("info", [
		"gscore_osc", "0.10.0",
		"listen", ctx.server.get_listen_port(),
		"coord", ctx.mapper.app_mode,
		"objects", ctx.registry.list_ids().size(),
	])
```
with:
```gdscript
func _handle_info() -> void:
	ctx.reply("info", _info_payload())


func _info_payload() -> Array:
	var out := [
		"gscore_osc", "0.10.0",
		"listen", ctx.server.get_listen_port(),
		"coord", ctx.mapper.app_mode,
		"objects", ctx.registry.list_ids().size(),
		"output",
	]
	out.append_array(Array(ctx.server.get_send_ports()))
	return out
```
(Leave the `"0.10.0"` string as-is here; Task 4 bumps every version occurrence together.)

- [ ] **Step 5: Generate the `.uid`, run the test**

Run the import check (Task 1 Step 5) to generate `tools/test_osc_output_cmd.gd.uid` and confirm no parse errors. Then run the test. Expected: `DONE pass=4 fail=0`, no `FAIL:`.

- [ ] **Step 6: Commit**

```bash
git add addons/gscore_osc/core/OscDispatcher.gd tools/test_osc_output_cmd.gd tools/test_osc_output_cmd.gd.uid
git commit -m "feat(osc): /gscore/app/output takes a port list; /gscore/info reports it"
```

---

### Task 4: Version bump 0.10.0 → 0.11.0 and docs

**Files:**
- Modify: `addons/gscore_osc/core/OscDispatcher.gd` (version string, 3 occurrences)
- Modify: `addons/gscore_osc/plugin.cfg`
- Modify: `README.md`, `TUTORIAL.md`, `CHANGELOG.md`

- [ ] **Step 1: Bump the version string (3 places in the dispatcher)**

In `addons/gscore_osc/core/OscDispatcher.gd`, replace `"0.10.0"` with `"0.11.0"` in all 3 occurrences (the `version` reply in `dispatch`, the `version` reply in `_handle_root`, and the `"gscore_osc", "0.10.0"` pair now inside `_info_payload`). Verify: `grep -n '0\.10\.0' addons/gscore_osc/core/OscDispatcher.gd` returns nothing; `grep -n '0\.11\.0' addons/gscore_osc/core/OscDispatcher.gd` returns 3 lines.

- [ ] **Step 2: Bump `plugin.cfg`**

In `addons/gscore_osc/plugin.cfg`, change:
```
version="0.10.0"
```
to:
```
version="0.11.0"
```

- [ ] **Step 3: Update `CHANGELOG.md`**

Add this entry at the top of the version entries (note the em-dash `—` and today's date, matching the existing `## [0.10.0] — …` style):
```markdown
## [0.11.0] — 2026-07-03

### Added
- **Multi-port OSC output.** gscore can now fan every reply and event out to a list of ports, so a
  client and one or more monitors each receive a copy. Configure a static list with the
  `gscore_osc/network/send_ports` project setting (e.g. `"7401,7402"`), or at runtime with
  `/gscore/app/output <host> <port> [port2 …]`. `/gscore/info` now reports the active output ports.

### Notes
- Fully backward-compatible: with `network/send_ports` unset the list is the single `network/send_port`
  (default 7401), identical to before; `/gscore/app/output <host> <port>` with one port is unchanged.
```

- [ ] **Step 4: Update `README.md`**

In the network/ports section (near where `network/send_port` / the reply port is documented — find it with `grep -n "send_port\|7401\|reply port\|/gscore/app" README.md`), add:
```markdown
### Multiple output ports

By default gscore sends every reply and event to a single port (`network/send_port`, default 7401),
so only one process can receive them (UDP unicast has one owner per port). To let a client **and**
monitors each get a copy, send to a list of ports:

    # static: project setting gscore_osc/network/send_ports
    "7401,7402,7403"

    # runtime: replaces the whole list (one port = the classic behavior)
    /gscore/app/output 127.0.0.1 7401 7402

`/gscore/info` reports the active list (… `output 7401 7402`). With `network/send_ports` unset,
behaviour is exactly as before.
```

- [ ] **Step 5: Update `TUTORIAL.md`**

Before the "## Next steps" section (find it with `grep -n "^## Next steps" TUTORIAL.md`), add:
```markdown
## Monitoring alongside your client (multiple output ports)

Only one process can bind a UDP port, so a monitor and your client can't both listen on 7401. Tell
gscore to mirror its output to several ports instead:

    /gscore/app/output 127.0.0.1 7401 7402

Now a client on 7401 and a monitor on 7402 each receive every reply and event. You can also set it
statically in Project Settings under `gscore_osc/network/send_ports` (e.g. `"7401,7402"`). Send
`/gscore/info` to see the active ports.
```

- [ ] **Step 6: Verify no parse errors and commit**

Run the import check (Task 1 Step 5) — expect no parse errors. Then:
```bash
git add addons/gscore_osc/core/OscDispatcher.gd addons/gscore_osc/plugin.cfg README.md TUTORIAL.md CHANGELOG.md
git commit -m "docs: multi-port OSC output (0.11.0)"
```

---

### Task 5: Wire the new tests into CI

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add two CI steps**

In `.github/workflows/ci.yml`, after the "Self-tests — lighting" step (added by the 0.10.0 work), add:
```yaml
      - name: Self-tests — OSC output (port list)
        run: |
          ./godot --headless --path . --script res://tools/test_osc_output.gd 2>&1 | tee oscout.log
          grep -q "fail=0" oscout.log && ! grep -q "FAIL:" oscout.log

      - name: Self-tests — OSC output command
        run: |
          ./godot --headless --path . --script res://tools/test_osc_output_cmd.gd 2>&1 | tee oscoutcmd.log
          grep -q "fail=0" oscoutcmd.log && ! grep -q "FAIL:" oscoutcmd.log
```
(If the "Self-tests — lighting" step isn't present because this branch isn't stacked on the 0.10.0 work, add the two steps after any existing `--script` self-test step, before the "Boot check" step.)

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run OSC multi-port output self-tests"
```

---

## Self-Review

**Spec coverage:**
- Fan every reply+event to a port list, default `[7401]` → Task 1 (`_send_ports` + `_send_bytes` loop; loopback test). ✓
- Static `network/send_ports` setting → Task 2 (`startup_ports`; unit-tested in Task 1). ✓
- Runtime `/gscore/app/output <host> <port…>`, zero ports = error → Task 3. ✓
- `/gscore/info` reports ports → Task 3 (`_info_payload`, tested). ✓
- Normalize (de-dupe, drop invalid, never empty) → Task 1 (`_normalize_ports`, tested). ✓
- No behavior change when unconfigured → Task 1 default `[7401]` + Task 2 empty-setting fallback (both asserted). ✓
- Version bump + docs → Task 4; CI → Task 5. ✓
- Non-goals (per-message routing, per-port host, multicast, incremental add/remove) → not implemented. ✓

**Type/name consistency:** `_send_ports: PackedInt32Array`; static `parse_ports`/`_normalize_ports`/`startup_ports`; instance `get_send_ports`/`set_output(host, PackedInt32Array)`/`start(int, String, PackedInt32Array)`; dispatcher `_info_payload() -> Array`. Every call site (`GScoreRoot.server.start(...)`, `OscDispatcher.set_output(...)`, tests) passes a `PackedInt32Array` and reads back via `get_send_ports()`. Command address is `/gscore/app/output` with `args = [host, port…]` throughout.

**Placeholder scan:** none — every step has exact paths, full code, and exact expected output.
