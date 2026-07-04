#!/usr/bin/env python3
"""MuseScore -> single PNG/SVG page, honouring MusicScene's {input} -> {output} contract.

MuseScore 4 exports PNG/SVG one file per page with a "-N" suffix (e.g. out-1.png) and pads to the
page, so MusicScene can't call it directly. This wrapper runs MuseScore (trimming to the music with
-T), finds the page file, and copies it to exactly <output>.

Usage:
    mscore_to_score.py <input.(musicxml|mxl|mscz|mei)> <output.(png|svg)>
                       [--page N] [--dpi N] [--trim PX] [--mscore "<path>"]

Accepts any input MuseScore can import (MusicXML/.mxl/.mscz/MEI). MuseScore is located from
--mscore, else $MS_MUSESCORE, else PATH, else common install dirs.
Configure in MusicScene (Project Settings):
    musicscene/notation/engraver/musicxml =
        py "<proj>/tools/mscore_to_score.py" {input} {output} --page {page} --dpi 200
    musicscene/notation/engraver_output = "png"
"""
import argparse
import glob
import os
import shlex
import shutil
import subprocess
import sys
import tempfile


def resolve_mscore(explicit: str):
    if explicit:
        if os.path.isfile(explicit):
            return [explicit]
        return shlex.split(explicit, posix=False)
    env = os.environ.get("MS_MUSESCORE")
    if env:
        return [env] if os.path.isfile(env) else shlex.split(env, posix=False)
    for name in ("MuseScore4", "mscore4", "musescore", "mscore"):
        found = shutil.which(name)
        if found:
            return [found]
    for pat in (
        r"C:\Program Files\MuseScore 4\bin\MuseScore4.exe",
        r"C:\Program Files (x86)\MuseScore 4\bin\MuseScore4.exe",
        r"C:\Program Files\MuseScore 3\bin\MuseScore3.exe",
        "/Applications/MuseScore 4.app/Contents/MacOS/mscore",
    ):
        hits = sorted(glob.glob(pat))
        if hits:
            return [hits[-1]]
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--page", type=int, default=1)
    ap.add_argument("--dpi", type=int, default=200)
    ap.add_argument("--trim", type=int, default=10)
    ap.add_argument("--mscore", default="")
    a = ap.parse_args()

    fmt = os.path.splitext(a.output)[1].lstrip(".").lower() or "png"
    if fmt not in ("png", "svg"):
        fmt = "png"

    ms = resolve_mscore(a.mscore)
    if not ms:
        print("mscore_to_score: MuseScore not found — pass --mscore <path>, set $MS_MUSESCORE, "
              "or add it to PATH.", file=sys.stderr)
        return 3

    tmp = tempfile.mkdtemp(prefix="ms_ms_")
    target = os.path.join(tmp, "score." + fmt)
    cmd = list(ms) + [a.input, "-o", target, "-T", str(a.trim)]
    if fmt == "png":
        cmd += ["-r", str(a.dpi)]

    try:
        r = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e:
        print(f"mscore_to_score: cannot run MuseScore ({ms[0]}): {e}", file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return 3
    if r.returncode != 0:
        sys.stderr.write(r.stdout or "")
        sys.stderr.write(r.stderr or "")
        print(f"mscore_to_score: MuseScore exited {r.returncode}", file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return r.returncode

    stem = os.path.splitext(target)[0]
    p = a.page
    candidates = [
        f"{stem}-{p}.{fmt}",
        f"{stem}.{fmt}",
        f"{stem}-1.{fmt}",
    ]
    produced = next((c for c in candidates if os.path.exists(c)), None)
    if not produced:
        hits = sorted(glob.glob(os.path.join(tmp, f"*.{fmt}")))
        produced = hits[0] if hits else None
    if not produced:
        print(f"mscore_to_score: no {fmt} produced in {tmp}: {os.listdir(tmp)}", file=sys.stderr)
        shutil.rmtree(tmp, ignore_errors=True)
        return 4

    out_dir = os.path.dirname(os.path.abspath(a.output))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    shutil.copyfile(produced, a.output)
    print(f"mscore_to_score: wrote {a.output} from {os.path.basename(produced)}")
    shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
