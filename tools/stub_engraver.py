#!/usr/bin/env python3
"""Stub engraver for testing the external notation backend.
Usage: stub_engraver.py <input> <output> [format]
Ignores the input and writes a placeholder PNG (a copy of scores/page1.png) to <output>,
standing in for a real MusicXML/LilyPond/ABC -> PNG engraver.
"""
import os
import shutil
import sys

out = sys.argv[2]
src = os.path.join(os.path.dirname(__file__), "..", "scores", "page1.png")
shutil.copyfile(src, out)
print("[stub_engraver] wrote", out, "from input", sys.argv[1])
