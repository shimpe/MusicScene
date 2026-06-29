#!/usr/bin/env python3
"""LilyPond -> single PNG/SVG page, honouring gscore's {input} -> {output} contract.

LilyPond names its own outputs (`-page1.png`, `.cropped.png`, …) and defaults to a full A4 page
with whitespace, so gscore can't call it directly. This wrapper runs LilyPond, finds the produced
file (preferring the tightly-cropped one), and copies it to exactly <output>.

Usage:
    ly_to_score.py <input.ly> <output.(png|svg)> [--page N] [--dpi N] [--no-crop]
                   [--lilypond "<path-or-command>"]

LilyPond is located from --lilypond, else $GSCORE_LILYPOND, else PATH, else common install dirs.
Configure in gscore (Project Settings):
    gscore_osc/notation/engraver/lilypond =
        py "<proj>/tools/ly_to_score.py" {input} {output} --page {page} --lilypond "C:/Program Files/lilypond-2.25.81/bin/lilypond.exe"
    gscore_osc/notation/engraver_output = "png"
"""
import argparse
import glob
import os
import shlex
import shutil
import subprocess
import sys
import tempfile


def resolve_lilypond(explicit: str):
    if explicit:
        if os.path.isfile(explicit):
            return [explicit]
        return shlex.split(explicit, posix=False)
    env = os.environ.get("GSCORE_LILYPOND")
    if env:
        return shlex.split(env, posix=False) if not os.path.isfile(env) else [env]
    found = shutil.which("lilypond")
    if found:
        return [found]
    for pat in (
        r"C:\Program Files\lilypond-*\bin\lilypond.exe",
        r"C:\Program Files (x86)\lilypond-*\bin\lilypond.exe",
        r"C:\Program Files\LilyPond\usr\bin\lilypond.exe",
        os.path.expanduser(r"~\AppData\Local\Programs\lilypond-*\bin\lilypond.exe"),
        "/Applications/LilyPond.app/Contents/Resources/bin/lilypond",
    ):
        hits = sorted(glob.glob(pat))
        if hits:
            return [hits[-1]]  # newest-ish
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--page", type=int, default=1)
    ap.add_argument("--dpi", type=int, default=200)
    ap.add_argument("--no-crop", action="store_true")
    ap.add_argument("--lilypond", default="")
    a = ap.parse_args()

    fmt = os.path.splitext(a.output)[1].lstrip(".").lower() or "png"
    if fmt not in ("png", "svg"):
        fmt = "png"

    lily = resolve_lilypond(a.lilypond)
    if not lily:
        print("ly_to_score: LilyPond not found — pass --lilypond <path>, set $GSCORE_LILYPOND, "
              "or add it to PATH.", file=sys.stderr)
        return 3

    tmp = tempfile.mkdtemp(prefix="gscore_ly_")
    base = os.path.join(tmp, "score")
    cmd = list(lily)
    if fmt == "png":
        cmd += ["--png", f"-dresolution={a.dpi}"]
    else:
        cmd += ["-dbackend=svg"]
    if not a.no_crop:
        cmd += ["-dcrop=#t"]
    cmd += ["-o", base, a.input]

    try:
        r = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e:
        print(f"ly_to_score: cannot run LilyPond ({lily[0]}): {e}", file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return 3
    if r.returncode != 0:
        sys.stderr.write(r.stdout or "")
        sys.stderr.write(r.stderr or "")
        print(f"ly_to_score: LilyPond exited {r.returncode}", file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return r.returncode

    p = a.page
    candidates = [
        f"{base}.cropped.{fmt}",
        f"{base}-page{p}.{fmt}",
        f"{base}-{p}.{fmt}",
        f"{base}.{fmt}",
        f"{base}-page1.{fmt}",
        f"{base}-1.{fmt}",
    ]
    produced = next((c for c in candidates if os.path.exists(c)), None)
    if not produced:
        hits = sorted(glob.glob(os.path.join(tmp, f"*.{fmt}")))
        produced = hits[0] if hits else None
    if not produced:
        print(f"ly_to_score: no {fmt} produced in {tmp}: {os.listdir(tmp)}", file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return 4

    out_dir = os.path.dirname(os.path.abspath(a.output))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    shutil.copyfile(produced, a.output)
    print(f"ly_to_score: wrote {a.output} from {os.path.basename(produced)}")
    shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
