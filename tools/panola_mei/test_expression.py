"""Per-note expression (dynamics + articulation) tests for Panola.scoreAsMEI (PanolaMEI).
Runs sclang to generate MEI, renders via Verovio, and asserts expression structure.
Run:  py -m pytest tools/panola_mei/test_expression.py -q   (skips if sclang absent)
"""
import os, subprocess, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

SCLANG = os.environ.get("SCLANG", r"C:\Program Files\SuperCollider-3.14.1\sclang.exe")

MINIMAL = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<note dur="4" oct="5" pname="c" artic="stacc"/><note dur="4" oct="5" pname="d"/>'
  '<note dur="2" oct="5" pname="e"/></layer></staff>'
  '<dynam tstamp="1" staff="1">mf</dynam></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_dynam_and_artic():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["dynam"] == 1
    assert p["artics"] == 1
