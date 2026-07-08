"""Hairpin tests for Panola.scoreAsMEI (PanolaMEI). sclang -> MEI -> Verovio render + assert.
Run:  py -m pytest tools/panola_mei/test_hairpins.py -q   (skips if sclang absent)
"""
import os, tempfile, shutil, pytest
from tools.panola_mei.render_check import render_props

MINIMAL = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp>'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>'
  '<section><measure n="1"><staff n="1"><layer n="1">'
  '<note dur="4" oct="5" pname="c"/><note dur="4" oct="5" pname="d"/>'
  '<note dur="4" oct="5" pname="e"/><note dur="4" oct="5" pname="f"/></layer></staff>'
  '<hairpin form="cres" tstamp="1" tstamp2="0m+4" staff="1"/></measure></section></score></mdiv></body></music></mei>')


def test_render_props_counts_hairpin():
    p = render_props(MINIMAL)
    assert p["ok"] is True
    assert p["hairpins"] == 1
