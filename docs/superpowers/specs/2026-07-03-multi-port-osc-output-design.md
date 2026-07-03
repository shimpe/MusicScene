# Design — Multi-port OSC output

**Date:** 2026-07-03 · **Target version:** 0.11.0 · **Status:** approved, ready for planning

## Motivation

Only one process can `bind()` a given unicast UDP port. gscore sends every reply and event to a
single output port (default 7401) at the most recent sender's IP, so only one listener can receive
that stream at a time. This surfaced while running the SuperCollider pachinko (which owns 7401)
alongside a Python monitor (`gosc.py`): whichever bound 7401 first got all the traffic and the other
was silent.

This change lets gscore fan its outbound OSC out to a **configurable list of ports**, so a client and
one or more monitors can each receive a copy. It is fully backward-compatible: the default list is the
single port `[7401]`, so an unconfigured project behaves exactly as today.

## Goals

- Send every reply **and** event to a list of ports; default `[7401]`.
- Configure the list two ways: a static `network/send_ports` project setting and the runtime
  `/gscore/app output <host> <port> [port2 …]` command.
- Report the active output ports in the `/gscore/info` reply.
- Zero behavior change when unconfigured.

## Non-goals

Per-message routing (different messages to different ports); a distinct host per port; multicast/
broadcast; incremental add/remove of a single port (the `output` command replaces the whole list).
All are out of scope; the whole-list-replace model is sufficient for the monitor use case.

---

## Architecture & files

| File | Change |
|---|---|
| `core/OscServer.gd` | `_send_port: int` → `_send_ports: PackedInt32Array` (default `[7401]`); fan out in `_send_bytes()`; `start()`/`set_output()` take an array; add `parse_ports()`, `_normalize_ports()`, `get_send_ports()`. |
| `nodes/GScoreRoot.gd` | Read new `network/send_ports` (String) alongside `network/send_port` (int); build the startup list; pass it to `server.start(...)`. |
| `core/OscDispatcher.gd` | `/gscore/app output <host> <port…>` collects all trailing ports; append output ports to the `/gscore/info` reply. |
| `tools/test_osc_output.gd` (new) | Unit test for parse/normalize + headless loopback fan-out test. |
| `.github/workflows/ci.yml` | Wire the new test in. |
| `README.md`, `TUTORIAL.md`, `CHANGELOG.md` | Document the setting + multi-port command; `[0.11.0]` entry. |

## Core change — `OscServer.gd`

Replace the scalar `_send_port: int` with `_send_ports: PackedInt32Array` (default `[7401]`). All
outbound OSC already funnels through `_send_bytes()` (used by both `send()` for replies and
`send_bundle()` for events), so the fan-out lives in exactly one place:

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

Host resolution is unchanged (last sender's IP, else the `_send_host` fallback) — the list only
multiplies the destination port. Signature/API changes:

- `start(listen_port: int, send_host: String, send_ports: PackedInt32Array) -> bool`
- `set_output(host: String, send_ports: PackedInt32Array) -> void`
- `get_send_ports() -> PackedInt32Array` (for `/gscore/info` and tests)
- `static func parse_ports(text: String) -> PackedInt32Array` — split on commas and/or whitespace,
  `to_int()` each token, keep values in `1..65535`.
- `func _normalize_ports(raw) -> PackedInt32Array` — de-duplicate preserving first-seen order, drop
  values `< 1` or `> 65535`; **if the result is empty, return `[7401]`** so the list is never empty.

`start()` and `set_output()` pass their incoming array through `_normalize_ports()` before storing it.
The existing `send_to(host, port, …)` explicit-target helper is unrelated to the list and is left
as-is.

## Startup config — `GScoreRoot.gd`

Read both settings and build the list:

```gdscript
var send_ports_str := String(_setting("network/send_ports", ""))
var ports: PackedInt32Array
if send_ports_str.strip_edges() != "":
    ports = server.parse_ports(send_ports_str)   # static fn, called via the existing instance
else:
    ports = PackedInt32Array([int(_setting("network/send_port", 7401))])
server.start(int(_setting("network/listen_port", 7400)),
    String(_setting("network/send_host", "127.0.0.1")), ports)
```

With `network/send_ports` unset (default `""`), the list is `[network/send_port]` = `[7401]` —
byte-for-byte identical to today. Settings are read on demand via
`ProjectSettings.get_setting("gscore_osc/"+key, default)`, so no registration code is required.

## Runtime config — `OscDispatcher.gd`

Extend the existing `output` verb under `/gscore/app`:

```gdscript
"output":
    var host := _s(args, 0)
    var ports := PackedInt32Array()
    for i in range(1, args.size()):
        ports.append(int(_f(args, i)))
    if ports.is_empty():
        ctx.error("bad_arguments", "/gscore/app", "output needs at least one port")
    else:
        ctx.server.set_output(host, ports)
```

`/gscore/app output 127.0.0.1 7401` = today's behavior; `… 7401 7402 7403` fans out to three ports.
A missing port (`output <host>` with nothing after) is a `bad_arguments` error and leaves the current
list unchanged.

Append the active ports to `/gscore/info` so a port conflict is diagnosable at a glance:

```gdscript
func _handle_info() -> void:
    var out := ["gscore_osc", "0.11.0", "listen", ctx.server.get_listen_port(),
        "coord", ctx.mapper.app_mode, "objects", ctx.registry.list_ids().size(), "output"]
    out.append_array(ctx.server.get_send_ports())
    ctx.reply("info", out)
```

## Data flow

reply/event → `ctx.reply(…)` / event emit → `server.send(…)` / `server.send_bundle(…)` →
`_send_bytes(bytes)` → **for each port in `_send_ports`**: `set_dest_address(host, port)` +
`put_packet(bytes)`.

## Error handling

- Invalid, duplicate, or out-of-range ports are dropped by `_normalize_ports`.
- An all-invalid or empty list resolves to `[7401]` (never empty).
- A per-port `set_dest_address` failure skips just that port (best-effort, unchanged semantics).

## Backward compatibility

- Default (no setting, no `output` command) ⇒ `[7401]` ⇒ identical to current behavior.
- The single-port `output <host> <port>` command still works unchanged.
- No project-setting registration is added or removed; the new setting is read with an empty default.

## Testing (headless, `--script`)

1. **Unit — parse/normalize** (`OscServer.parse_ports` / `_normalize_ports`):
   - `parse_ports("7401, 7402 7403")` → `[7401, 7402, 7403]`.
   - drops `"abc"`, `"0"`, `"70000"`, negative; de-dupes `"7401 7401"` → `[7401]`.
   - `_normalize_ports([])` → `[7401]`.
2. **Integration — loopback fan-out**: start an `OscServer` on a high test listen port,
   `set_output("127.0.0.1", [A, B])` (two high test ports), bind two `PacketPeerUDP` receivers on A
   and B, call `server.send("/x", [1])`, poll both receivers across a few frames, and assert **both**
   received the message. Deterministic on localhost.
3. Wire `tools/test_osc_output.gd` into `.github/workflows/ci.yml`.

## Rollout

Version → **0.11.0** (this branch is stacked on the 0.10.0 volumetric/lighting work). Docs updated
(README/TUTORIAL/CHANGELOG). Branch/merge ordering relative to `feat/3d-volumetric-lighting` is decided
when finishing the branch, not in this spec.
