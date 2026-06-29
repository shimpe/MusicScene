#!/usr/bin/env python3
"""Dependency-free OSC test client for gscore_osc.

Sends a sequence of /gscore commands to the running Godot project and prints every reply/event
received. Doubles as a minimal reference OSC implementation for Python clients.

Usage:
    py tools/osc_test.py [send_port] [recv_port]
Defaults: send to 127.0.0.1:7400, listen on 127.0.0.1:7401 (matches project defaults).
"""
import socket
import struct
import sys
import threading
import time

HOST = "127.0.0.1"
SEND_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 7400
RECV_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 7401


# ---------------- OSC encode ----------------
def _pad(b: bytes) -> bytes:
    return b + b"\x00" * ((4 - len(b) % 4) % 4)


def _ostr(s: str) -> bytes:
    return _pad(s.encode("utf-8") + b"\x00")


def osc_msg(addr: str, *args) -> bytes:
    tt = ","
    payload = b""
    for a in args:
        if isinstance(a, bool):
            tt += "T" if a else "F"
        elif isinstance(a, int):
            tt += "i"; payload += struct.pack(">i", a)
        elif isinstance(a, float):
            tt += "f"; payload += struct.pack(">f", a)
        else:
            tt += "s"; payload += _ostr(str(a))
    return _ostr(addr) + _ostr(tt) + payload


# ---------------- OSC decode ----------------
def _rstr(data: bytes, i: int):
    end = data.index(b"\x00", i)
    s = data[i:end].decode("utf-8", "replace")
    i = end + 1
    i += (4 - i % 4) % 4
    return s, i


def decode(data: bytes):
    out = []
    if data[:8] == b"#bundle\x00":
        i = 16
        while i + 4 <= len(data):
            size = struct.unpack_from(">i", data, i)[0]; i += 4
            out += decode(data[i:i + size]); i += size
        return out
    addr, i = _rstr(data, 0)
    if i >= len(data):
        return [(addr, [])]
    tt, i = _rstr(data, i)
    args = []
    for c in tt[1:]:
        if c == "i":
            args.append(struct.unpack_from(">i", data, i)[0]); i += 4
        elif c == "f":
            args.append(round(struct.unpack_from(">f", data, i)[0], 4)); i += 4
        elif c in "ht":
            args.append(struct.unpack_from(">q", data, i)[0]); i += 8
        elif c == "d":
            args.append(struct.unpack_from(">d", data, i)[0]); i += 8
        elif c in "sS":
            s, i = _rstr(data, i); args.append(s)
        elif c == "T":
            args.append(True)
        elif c == "F":
            args.append(False)
        elif c == "b":
            n = struct.unpack_from(">i", data, i)[0]; i += 4 + n + ((4 - n % 4) % 4)
            args.append("<blob>")
    return [(addr, args)]


# ---------------- runtime ----------------
# NOTE: sockets live inside main() so this module is import-safe (no side effects on import).

def main():
    recv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    recv_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    recv_sock.bind((HOST, RECV_PORT))
    send_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    received = []
    state = {"stop": False}

    def listener():
        recv_sock.settimeout(0.3)
        while not state["stop"]:
            try:
                data, _ = recv_sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            for addr, args in decode(data):
                received.append((addr, args))
                print(f"  <- {addr} {args}")

    def send(addr, *args):
        send_sock.sendto(osc_msg(addr, *args), (HOST, SEND_PORT))
        print(f"-> {addr} {list(args)}")
        time.sleep(0.05)

    t = threading.Thread(target=listener, daemon=True)
    t.start()
    time.sleep(0.3)

    print("\n== basic ==")
    send("/gscore/ping")
    send("/gscore/version")
    send("/gscore/info")

    print("\n== notation ==")
    send("/gscore/scene", "clear")
    send("/gscore/scene/score", "new", "notation")
    send("/gscore/scene/score", "notation", "png", "res://scores/page1.png")
    send("/gscore/scene/score", "pos", 0.0, 0.0)
    send("/gscore/scene/score", "scale", 0.9)
    send("/gscore/scene/score/cursor", "show", 1)
    send("/gscore/scene/score/cursor", "pos", 0.2, 0.5)
    send("/gscore/scene/score/cursor", "color", 1.0, 0.0, 0.0, 0.8)
    send("/gscore/scene/score/region", "m1", "rect", 0.1, 0.25, 0.2, 0.1)
    send("/gscore/scene/score/region", "m1", "highlight", 1)
    send("/gscore/scene/score", "notationInfo")
    send("/gscore/scene/score", "pages")

    print("\n== physics ==")
    send("/gscore/scene/floor", "new", "rect")
    send("/gscore/scene/floor", "pos", 0.0, -0.8)
    send("/gscore/scene/floor", "size", 1.8, 0.05)
    send("/gscore/scene/floor/physics", "enable", "static")
    send("/gscore/scene/floor/collider", "rect", 1.8, 0.05)
    send("/gscore/scene/ball", "new", "circle")
    send("/gscore/scene/ball", "pos", 0.0, 0.8)
    send("/gscore/scene/ball/physics", "enable", "rigid")
    send("/gscore/scene/ball/collider", "circle", 0.05)
    send("/gscore/scene/ball/physics", "bounce", 0.7)
    send("/gscore/scene/ball/on", "collisionEnter", "/synth/hit", "minIntensity", 0.05, "cooldown", 0.05)
    send("/gscore/scene/ball/payload", "collisionEnter", "self", "other", "intensity", "x", "y", "time")
    send("/gscore/physics", "enable", 1)
    send("/gscore/physics", "gravity", 0.0, -1.0)

    print("\n== queries / binding / instantiate ==")
    send("/gscore/scene/list")
    send("/gscore/scene/ball", "exists")
    send("/gscore/scene/ball", "capabilities")
    send("/gscore/app/root", "/root/Main/Stage")
    send("/gscore/bindRel", "existingBall", "Actors/ExistingBall")
    send("/gscore/scene/existingBall", "capabilities")
    send("/gscore/assets/allowScene", "res://osc_spawnable/PhysicalNote.tscn")
    send("/gscore/scene/note42", "instantiate", "res://osc_spawnable/PhysicalNote.tscn")
    send("/gscore/scene/note42", "exists")
    send("/gscore/scene/score", "dump")

    print("\n== waiting for collision events (4s) ==")
    time.sleep(4.0)

    state["stop"] = True
    time.sleep(0.4)

    print("\n==== SUMMARY ====")
    addrs = [a for a, _ in received]
    def got(pred):
        return any(pred(a, args) for a, args in received)
    checks = {
        "pong": "/gscore/pong" in addrs,
        "reply version": got(lambda a, ar: a == "/gscore/reply" and ar[:1] == ["version"]),
        "reply notationInfo": got(lambda a, ar: a == "/gscore/reply" and ar[:1] == ["notationInfo"]),
        "reply pages": got(lambda a, ar: a == "/gscore/reply" and ar[:1] == ["pages"]),
        "reply scene/list": got(lambda a, ar: a == "/gscore/reply" and ar[:1] == ["scene/list"]),
        "reply exists": got(lambda a, ar: a == "/gscore/reply" and ar[:1] == ["exists"]),
        "reply capabilities": got(lambda a, ar: a == "/gscore/reply" and ar[:1] == ["capabilities"]),
        "reply dump": got(lambda a, ar: a == "/gscore/reply" and ar[:1] == ["dump"]),
        "/synth/hit": "/synth/hit" in addrs,
        "/gscore/event/physics": "/gscore/event/physics" in addrs,
    }
    ok = 0
    for name, passed in checks.items():
        print(f"  [{'PASS' if passed else 'FAIL'}] {name}")
        ok += 1 if passed else 0
    print(f"\n{ok}/{len(checks)} checks passed; {len(received)} messages received.")


if __name__ == "__main__":
    main()
