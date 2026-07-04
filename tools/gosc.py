# gosc.py — minimal OSC client for MusicScene
import socket, struct, threading, time

HOST, SEND_PORT, RECV_PORT = "127.0.0.1", 7400, 7401

def _pad(b): return b + b"\x00" * ((4 - len(b) % 4) % 4)
def _ostr(s): return _pad(s.encode() + b"\x00")

def msg(addr, *args):
    tt, payload = ",", b""
    for a in args:
        if isinstance(a, bool):  tt += "T" if a else "F"
        elif isinstance(a, int): tt += "i"; payload += struct.pack(">i", a)
        elif isinstance(a, float): tt += "f"; payload += struct.pack(">f", a)
        else: tt += "s"; payload += _ostr(str(a))
    return _ostr(addr) + _ostr(tt) + payload

def _rstr(d, i):
    e = d.index(b"\x00", i); s = d[i:e].decode("utf-8", "replace"); i = e + 1
    return s, i + ((4 - i % 4) % 4)

def decode(d):
    if d[:8] == b"#bundle\x00":
        out, i = [], 16
        while i + 4 <= len(d):
            n = struct.unpack_from(">i", d, i)[0]; i += 4
            out += decode(d[i:i+n]); i += n
        return out
    addr, i = _rstr(d, 0)
    if i >= len(d): return [(addr, [])]
    tt, i = _rstr(d, i); args = []
    for c in tt[1:]:
        if c == "i": args.append(struct.unpack_from(">i", d, i)[0]); i += 4
        elif c == "f": args.append(round(struct.unpack_from(">f", d, i)[0], 4)); i += 4
        elif c in "sS": v, i = _rstr(d, i); args.append(v)
        elif c == "T": args.append(True)
        elif c == "F": args.append(False)
        elif c in "htd": i += 8
    return [(addr, args)]

_recv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
_recv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
_recv.bind((HOST, RECV_PORT)); _recv.settimeout(0.3)
_send = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

def _listen():
    while True:
        try: data, _ = _recv.recvfrom(65535)
        except socket.timeout: continue
        for a, ar in decode(data): print("  <-", a, ar)
threading.Thread(target=_listen, daemon=True).start()

def s(addr, *args):
    _send.sendto(msg(addr, *args), (HOST, SEND_PORT))
    print("->", addr, list(args)); time.sleep(0.05)

if __name__ == "__main__":
    import code; code.interact(local=globals())   # interactive: type s("/ms/ping")
	