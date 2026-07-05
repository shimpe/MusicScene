# Panola ↔ MusicScene Score Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user write music as Panola string(s) and get correct multi-staff MEI notation from Panola, then show + play + follow it in MusicScene with one call.

**Architecture:** Hybrid. A pure `Panola.asMEI`/`scoreAsMEI` transform in the Panola quark turns parsed notes + score prefs into an MEI string (usable outside MusicScene). An `MSScore` SuperCollider class in this repo sends that MEI, plays the voices, and drives a note-accurate cursor by replaying MusicScene's addressable `elements` timemap. The MEI string is the only contract.

**Tech stack:** SuperCollider (Panola quark + `MSScore`), MEI (Verovio via the bundled `verovio_render.py`), Python 3 (the reference/oracle + rendering harness), Godot 4.7 headless (`MSNotationBackendSvg` for rasterisation checks).

**Spec:** `docs/superpowers/specs/2026-07-05-panola-musicscene-score-design.md`

**CRITICAL CONSTRAINT — read before executing.** SuperCollider cannot be run in the authoring/CI environment.
- **Phase 1 (Python reference + harness)** is fully automatable and TDD'd here. It is the *executable spec* for the MEI mapping and the oracle the SC port is checked against.
- **Phase 2 (`Panola.asMEI`, sclang) and Phase 3 (`MSScore`, sclang)** are **written, not run** by the agent. Their "test" is: (a) mirror the validated Phase-1 reference exactly; (b) a provided `.scd` that the **user** evaluates to dump MEI to files / run the live demo; (c) the agent re-validates the dumped MEI files with the Phase-1 harness. Do not claim these phases "pass tests" — claim "code written; MEI output validated by rendering; interactive behaviour pending user run."

**Two repos.**
- This repo (`D:\Projects\MusicScene`): Phase 1 (`tools/panola_mei/`), Phase 3 (`MSScore`), Phase 4 (example + docs).
- The Panola quark (`C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola`, its own git repo): Phase 2 (`Classes/Panola.sc`). Commit Phase-2 changes in *that* repo, not this one.

**Conventions used throughout.**
- Verovio wrapper (renders any MEI/MusicXML/ABC to a cropped SVG): `addons/musicscene/tools/verovio_render.py <in> <out.svg> --page 1`. Requires `pip install verovio` (already installed for `py`).
- Godot: `/d/Godot/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe --headless --path . --script <gd>`.
- Beats are in quarter-notes (quarter = 1 beat), matching Panola's `durationPattern`.
- MEI middle C = `oct="4"` = MIDI 60 = Panola `c4` (no octave offset).

---

## File structure

| File | Repo | Responsibility |
|---|---|---|
| `tools/panola_mei/ref.py` | MusicScene | Reference mapping: structured notes + prefs → MEI string (pitch, meter engine, ties, multi-staff, key). The oracle. |
| `tools/panola_mei/render_check.py` | MusicScene | Render an MEI string via the Verovio wrapper + report `(ok, treble_clefs, bass_clefs, measures, has_tie, has_keysig)`. |
| `tools/panola_mei/test_ref.py` | MusicScene | pytest suite driving `ref.py` outputs through `render_check.py` and asserting properties. |
| `Classes/Panola.sc` | Panola quark | `asMEI`, `*scoreAsMEI`, `pr_meiEvents` (SC port of `ref.py`). |
| `Classes/tests/test_asMEI.scd` | Panola quark | Dumps MEI for sample Panola strings to `<tmp>/panola_asMEI_*.mei` for harness validation. |
| `examples/supercollider/MSScore.sc` | MusicScene | The orchestration class (show/play/stop, cursor). |
| `examples/supercollider/example_panola_score.scd` | MusicScene | Worked example + acceptance test. |
| `TUTORIAL.md`, `README.md`, `CHANGELOG.md` | MusicScene | Document the front door. |

**Structured-notes interchange format** (produced by Panola in Phase 2; hand-written in Phase 1 tests). One *voice* is a list of *events*; each event is a `dict`:
```python
# note:  {"kind":"note",  "pnames":["c"], "accids":["s"], "octs":[5], "meidur":4, "dots":0, "beats":1.0}
# chord: {"kind":"note",  "pnames":["c","e","g"], "accids":[None,None,None], "octs":[4,4,4], "meidur":4, "dots":0, "beats":1.0}
# rest:  {"kind":"rest",  "meidur":4, "dots":0, "beats":1.0}
```
`accids[i]` is one of `None`/`"s"`/`"x"`/`"f"`/`"ff"` (Panola modifier → MEI). `beats` is the event's quarter-note length (equals `(4/meidur)*(2-1/2**dots)` for plain durations). `meidur`/`dots` describe a *single* note value; the meter engine may split it.

---

## Phase 1 — MEI reference + rendering harness (Python, this repo, fully TDD)

### Task 1: Rendering harness

**Files:**
- Create: `tools/panola_mei/__init__.py` (empty)
- Create: `tools/panola_mei/render_check.py`
- Test: `tools/panola_mei/test_ref.py`

- [ ] **Step 1: Write the failing test** (`tools/panola_mei/test_ref.py`)

```python
import subprocess, re, os, tempfile
from tools.panola_mei.render_check import render_props

WRAP = os.path.join("addons", "musicscene", "tools", "verovio_render.py")

MINIMAL_GRAND = (
  '<?xml version="1.0" encoding="UTF-8"?>'
  '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0"><music><body><mdiv><score>'
  '<scoreDef meter.count="4" meter.unit="4" key.sig="0"><staffGrp symbol="brace" bar.thru="true">'
  '<staffDef n="1" lines="5" clef.shape="G" clef.line="2"/>'
  '<staffDef n="2" lines="5" clef.shape="F" clef.line="4"/></staffGrp></scoreDef>'
  '<section><measure n="1">'
  '<staff n="1"><layer n="1"><note dur="1" oct="5" pname="c"/></layer></staff>'
  '<staff n="2"><layer n="1"><note dur="1" oct="3" pname="c"/></layer></staff>'
  '</measure></section></score></mdiv></body></music></mei>')

def test_render_props_reads_a_grand_staff():
    p = render_props(MINIMAL_GRAND)
    assert p["ok"] is True
    assert p["treble_clefs"] >= 1 and p["bass_clefs"] >= 1
    assert p["measures"] == 1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `py -m pytest tools/panola_mei/test_ref.py -q`
Expected: FAIL — `ModuleNotFoundError` / `render_props` undefined.

- [ ] **Step 3: Implement `render_check.py`**

```python
import subprocess, re, os, tempfile

WRAP = os.path.join("addons", "musicscene", "tools", "verovio_render.py")

def render_props(mei: str) -> dict:
    """Render an MEI string via the bundled Verovio wrapper and report structural properties."""
    with tempfile.TemporaryDirectory() as d:
        inp = os.path.join(d, "s.mei"); outp = os.path.join(d, "s.svg")
        open(inp, "w", encoding="utf-8").write(mei)
        r = subprocess.run(["py", WRAP, inp, outp, "--page", "1"], capture_output=True, text=True)
        svg = open(outp, encoding="utf-8").read() if os.path.exists(outp) else ""
    return {
        "ok": r.returncode == 0 and "<svg" in svg,
        "returncode": r.returncode,
        "stderr": r.stderr,
        "treble_clefs": svg.count("E050"),   # G-clef glyph (def + uses)
        "bass_clefs": svg.count("E062"),     # F-clef glyph
        "measures": mei.count("<measure "),
        "has_tie": ('tie="i"' in mei) or ('tie="t"' in mei),
        "sharps": svg.count("E262"), "flats": svg.count("E260"),
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `py -m pytest tools/panola_mei/test_ref.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/panola_mei/__init__.py tools/panola_mei/render_check.py tools/panola_mei/test_ref.py
git commit -m "test(panola-mei): MEI rendering harness"
```

### Task 2: Note/chord/rest → MEI element

**Files:** Create `tools/panola_mei/ref.py`; Modify `tools/panola_mei/test_ref.py`.

- [ ] **Step 1: Write the failing test** (append to `test_ref.py`)

```python
from tools.panola_mei.ref import mei_element

def test_mei_element_note_chord_rest():
    assert mei_element({"kind":"note","pnames":["c"],"accids":["s"],"octs":[5],"meidur":4,"dots":0,"beats":1.0}) \
        == '<note dur="4" oct="5" pname="c" accid="s"/>'
    assert mei_element({"kind":"note","pnames":["c"],"accids":[None],"octs":[4],"meidur":4,"dots":1,"beats":1.5}) \
        == '<note dur="4" dots="1" oct="4" pname="c"/>'
    assert mei_element({"kind":"note","pnames":["c","e","g"],"accids":[None,None,None],"octs":[4,4,4],"meidur":2,"dots":0,"beats":2.0}) \
        == '<chord dur="2"><note oct="4" pname="c"/><note oct="4" pname="e"/><note oct="4" pname="g"/></chord>'
    assert mei_element({"kind":"rest","meidur":4,"dots":0,"beats":1.0}) == '<rest dur="4"/>'
```

- [ ] **Step 2: Run to verify it fails.** Run: `py -m pytest tools/panola_mei/test_ref.py::test_mei_element_note_chord_rest -q` → FAIL (`ref` undefined).

- [ ] **Step 3: Implement in `ref.py`**

```python
def _dur_attrs(meidur, dots):
    return f' dur="{meidur}"' + (f' dots="{dots}"' if dots else "")

def _accid(a):   # None omitted; accid string otherwise
    return f' accid="{a}"' if a else ""

def _note_body(pname, accid, oct):
    return f'<note oct="{oct}" pname="{pname}"{_accid(accid)}/>'

def mei_element(ev, override_dur=None, override_dots=None, tie=None):
    md = override_dur if override_dur is not None else ev["meidur"]
    dt = override_dots if override_dots is not None else ev["dots"]
    tiestr = f' tie="{tie}"' if tie else ""
    if ev["kind"] == "rest":
        return f'<rest{_dur_attrs(md, dt)}/>'
    if len(ev["pnames"]) == 1:
        return (f'<note{_dur_attrs(md, dt)} oct="{ev["octs"][0]}" pname="{ev["pnames"][0]}"'
                f'{_accid(ev["accids"][0])}{tiestr}/>')
    inner = "".join(f'<note oct="{o}" pname="{p}"{_accid(a)}{tiestr}/>'
                    for p, a, o in zip(ev["pnames"], ev["accids"], ev["octs"]))
    return f'<chord{_dur_attrs(md, dt)}>{inner}</chord>'
```

- [ ] **Step 4: Run to verify it passes.** Same command → PASS.
- [ ] **Step 5: Commit.** `git add tools/panola_mei/ref.py tools/panola_mei/test_ref.py && git commit -m "feat(panola-mei): note/chord/rest -> MEI element"`

### Task 3: Duration decomposition (beat length → tied note values)

**Files:** Modify `ref.py`, `test_ref.py`.

- [ ] **Step 1: Failing test**

```python
from tools.panola_mei.ref import decompose

def test_decompose_beats_to_note_values():
    assert decompose(1.0) == [(4, 0)]           # quarter
    assert decompose(1.5) == [(4, 1)]           # dotted quarter (single value)
    assert decompose(2.0) == [(2, 0)]           # half
    assert decompose(4.0) == [(1, 0)]           # whole
    assert decompose(2.5) == [(2, 0), (8, 0)]   # half + eighth (tied)
    assert decompose(3.0) == [(2, 1)]           # dotted half
    assert decompose(3.5) == [(2, 1), (8, 0)]   # dotted half + eighth
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement**

```python
# (meidur, dots) -> beats, largest first. Covers whole..sixteenth incl. single dots.
_VALUES = [(1,0,4.0),(2,1,3.0),(2,0,2.0),(4,1,1.5),(4,0,1.0),(8,1,0.75),(8,0,0.5),(16,0,0.25)]

def decompose(beats, eps=1e-6):
    """Express a beat length as [(meidur, dots), ...] tied note values, greedily largest-first."""
    out = []
    remaining = beats
    while remaining > eps:
        for md, dt, b in _VALUES:
            if b <= remaining + eps:
                out.append((md, dt)); remaining -= b; break
        else:
            break   # smaller than a sixteenth — drop (shouldn't happen for our inputs)
    return out
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit.** `git commit -am "feat(panola-mei): beat-length -> tied note-value decomposition"`

### Task 4: Meter engine (bin one voice into measures with auto-ties)

**Files:** Modify `ref.py`, `test_ref.py`.

- [ ] **Step 1: Failing test**

```python
from tools.panola_mei.ref import bar_beats, voice_to_measures

def test_bar_beats():
    assert bar_beats("4/4") == 4.0
    assert bar_beats("3/4") == 3.0
    assert bar_beats("6/8") == 3.0

def _n(pname, oct, meidur, dots=0):
    beats = (4/meidur)*(2 - 1/(2**dots))
    return {"kind":"note","pnames":[pname],"accids":[None],"octs":[oct],"meidur":meidur,"dots":dots,"beats":beats}

def test_voice_binning_no_cross():
    # two half notes = one 4/4 bar
    ms = voice_to_measures([_n("c",4,2), _n("d",4,2)], 4.0)
    assert len(ms) == 1 and len(ms[0]) == 2
    assert '<note dur="2" oct="4" pname="c"/>' in "".join(ms[0])

def test_voice_binning_ties_across_barline():
    # a whole note (4 beats) starting on beat 3 of a 4/4 bar -> split 2 + 2, tied
    ms = voice_to_measures([_n("c",4,2), _n("c",4,1)], 4.0)  # half, then whole
    assert len(ms) == 2
    joined = "".join(ms[0]) + "".join(ms[1])
    assert 'tie="i"' in joined and 'tie="t"' in joined
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** (uses `mei_element` + `decompose`)

```python
def bar_beats(meter):
    num, den = (int(x) for x in meter.split("/"))
    return num * (4.0 / den)

def voice_to_measures(events, barbeats, eps=1e-6):
    """Bin one voice's events into a list of measures (each a list of MEI element strings),
    splitting-and-tying any event that crosses a barline."""
    measures = [[]]
    pos = 0.0   # beats into the current measure
    for ev in events:
        remaining = ev["beats"]
        first_fragment = True
        while remaining > eps:
            room = barbeats - pos
            take = min(room, remaining)
            crosses = remaining > room + eps
            last_fragment = not crosses
            for k, (md, dt) in enumerate(decompose(take)):
                is_first_piece = first_fragment and k == 0
                is_last_piece = last_fragment and k == len(decompose(take)) - 1
                if ev["kind"] == "rest":
                    tie = None
                else:
                    tie = None
                    if not (is_first_piece and is_last_piece):
                        tie = "i" if is_first_piece else ("t" if is_last_piece else "m")
                measures[-1].append(mei_element(ev, override_dur=md, override_dots=dt, tie=tie))
            pos += take; remaining -= take; first_fragment = False
            if barbeats - pos < eps:            # bar full -> next measure
                measures.append([]); pos = 0.0
    if not measures[-1]:                         # drop a trailing empty measure
        measures.pop()
    return measures
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Render-level test + commit**

```python
def test_binning_renders():
    from tools.panola_mei.ref import score_to_mei
    events = [_n("c",5,4), _n("d",5,4), _n("e",5,2), _n("c",5,1)]  # spills into a 2nd bar
    mei = score_to_mei([events], "4/4", "0", ["treble"], None)
    p = render_props(mei)
    assert p["ok"] and p["measures"] == 2 and p["has_tie"]
```

(This references `score_to_mei` from Task 5; write Task 5 before running this render test.)
`git commit -am "feat(panola-mei): meter engine with auto-ties"`

### Task 5: Multi-staff assembly (`score_to_mei`)

**Files:** Modify `ref.py`, `test_ref.py`.

- [ ] **Step 1: Failing test**

```python
from tools.panola_mei.ref import score_to_mei

def test_two_staff_grand_staff_renders():
    rh = [_n("c",5,4), _n("e",5,4), _n("g",5,2)]
    lh = [_n("c",3,2), _n("g",2,2)]
    mei = score_to_mei([rh, lh], "4/4", "0", ["treble", "bass"], [[1,2]])
    p = render_props(mei)
    assert p["ok"] and p["treble_clefs"] >= 1 and p["bass_clefs"] >= 1 and p["measures"] == 1

def test_voices_padded_to_equal_measures():
    long = [_n("c",5,1), _n("d",5,1)]   # 2 bars
    short = [_n("c",3,1)]               # 1 bar -> padded to 2
    mei = score_to_mei([long, short], "4/4", "0", ["treble","bass"], None)
    # both staves present in both measures
    assert mei.count("<staff n=\"2\">") == 2
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement**

```python
_CLEF = {"treble": ("G","2"), "bass": ("F","4"), "alto": ("C","3"), "tenor": ("C","4")}

def _staffgrp(nstaves, clefs, braces):
    defs = {n: f'<staffDef n="{n}" lines="5" clef.shape="{_CLEF[clefs[n-1]][0]}" clef.line="{_CLEF[clefs[n-1]][1]}"/>'
            for n in range(1, nstaves + 1)}
    braces = braces or []
    in_brace = {n for a, b in braces for n in range(a, b + 1)}
    out = []
    n = 1
    while n <= nstaves:
        grp = next(((a, b) for a, b in braces if a == n), None)
        if grp:
            a, b = grp
            out.append('<staffGrp symbol="brace" bar.thru="true">'
                       + "".join(defs[k] for k in range(a, b + 1)) + "</staffGrp>")
            n = b + 1
        else:
            out.append(defs[n]); n += 1
    return "<staffGrp>" + "".join(out) + "</staffGrp>"

def _empty_measure_rest(barbeats):
    return "".join(f'<rest{_dur_attrs(md, dt)}/>' for md, dt in decompose(barbeats))

def score_to_mei(voices, meter, keysig, clefs, braces):
    bb = bar_beats(meter)
    per_voice = [voice_to_measures(v, bb) for v in voices]
    nmeasures = max((len(m) for m in per_voice), default=0)
    for m in per_voice:                                   # pad shorter voices with whole-bar rests
        while len(m) < nmeasures:
            m.append([_empty_measure_rest(bb)])
    body = ""
    for i in range(nmeasures):
        body += f'<measure n="{i+1}">'
        for s, m in enumerate(per_voice, start=1):
            body += f'<staff n="{s}"><layer n="1">' + "".join(m[i]) + "</layer></staff>"
        body += "</measure>"
    return ('<?xml version="1.0" encoding="UTF-8"?>'
            '<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="4.0.0">'
            '<music><body><mdiv><score>'
            f'<scoreDef meter.count="{meter.split("/")[0]}" meter.unit="{meter.split("/")[1]}" key.sig="{keysig}">'
            + _staffgrp(len(voices), clefs, braces) + '</scoreDef>'
            f'<section>{body}</section>'
            '</score></mdiv></body></music></mei>')
```

- [ ] **Step 4: Run → PASS** (and re-run Task 4's `test_binning_renders`).
- [ ] **Step 5: Commit.** `git commit -am "feat(panola-mei): multi-staff assembly + rest-padding"`

### Task 6: Key signature + accidentals relative to key

**Files:** Modify `ref.py`, `test_ref.py`.

- [ ] **Step 1: Failing test**

```python
from tools.panola_mei.ref import key_to_sig, accid_in_key

def test_key_lookup_and_relative_accidentals():
    assert key_to_sig("Cmajor") == "0"
    assert key_to_sig("Gmajor") == "1s"
    assert key_to_sig("Dminor") == "1f"
    assert key_to_sig("CsharpMinor") == "4s"
    # In G major (F#), an f# needs NO accid; an f-natural needs accid="n"; c stays plain.
    assert accid_in_key("f", "s", "Gmajor") is None
    assert accid_in_key("f", None, "Gmajor") == "n"
    assert accid_in_key("c", None, "Gmajor") is None
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement**

```python
# order of sharps / flats by letter
_SHARP_ORDER = ["f","c","g","d","a","e","b"]
_FLAT_ORDER  = ["b","e","a","d","g","c","f"]
_KEYSIG = {  # key name (lowercase, no space) -> (count, "s"|"f")
  "cmajor":(0,None),"aminor":(0,None),
  "gmajor":(1,"s"),"eminor":(1,"s"),"dmajor":(2,"s"),"bminor":(2,"s"),
  "amajor":(3,"s"),"fsharpminor":(3,"s"),"emajor":(4,"s"),"csharpminor":(4,"s"),
  "bmajor":(5,"s"),"gsharpminor":(5,"s"),
  "fmajor":(1,"f"),"dminor":(1,"f"),"bflatmajor":(2,"f"),"gminor":(2,"f"),
  "eflatmajor":(3,"f"),"cminor":(3,"f"),"aflatmajor":(4,"f"),"fminor":(4,"f"),
  "dflatmajor":(5,"f"),"bflatminor":(5,"f"),
}

def _key_alters(key):
    """Return {letter: 's'|'f'} for the pitch letters altered by the key signature."""
    cnt, kind = _KEYSIG[key.lower()]
    order = _SHARP_ORDER if kind == "s" else _FLAT_ORDER
    return {order[i]: kind for i in range(cnt)}

def key_to_sig(key):
    cnt, kind = _KEYSIG[key.lower()]
    return "0" if cnt == 0 else f"{cnt}{kind}"

def accid_in_key(pname, accid, key):
    """The accid attribute to EMIT for a note, given the key sig. None = omit (already in key)."""
    alt = _key_alters(key).get(pname)       # what the key does to this letter ('s'/'f'/None)
    want = accid                            # what the note actually is (None=natural, 's','f','x','ff')
    if want == alt:
        return None                         # key already provides it -> omit
    if want is None:
        return "n" if alt else None         # natural that contradicts the key needs explicit natural
    return want                             # explicit accidental differing from key
```

Then wire it in: `score_to_mei` takes `key` (name) — compute `keysig = key_to_sig(key)` and, when emitting each note, replace its `accids[i]` with `accid_in_key(pname, accids[i], key)`. Add a `key`-name parameter path (keep the raw-`keysig` path for the harness tests above by accepting either a `"0"`-style string or a key name; detect a name if it isn't purely `[0-9][sf]?`).

- [ ] **Step 4: Add a render test + run**

```python
def test_gmajor_avoids_redundant_sharps():
    fis = {"kind":"note","pnames":["f"],"accids":["s"],"octs":[5],"meidur":4,"dots":0,"beats":1.0}
    mei = score_to_mei([[fis, fis, fis, fis]], "4/4", "Gmajor", ["treble"], None)
    assert 'accid="s"' not in mei          # F# is implied by the key sig
    assert render_props(mei)["ok"]
```

Run: `py -m pytest tools/panola_mei/test_ref.py -q` → all PASS.

- [ ] **Step 5: Commit.** `git commit -am "feat(panola-mei): key signature + accidentals relative to key"`

**End of Phase 1: `ref.py` is the validated reference for the whole mapping.**

---

## Phase 2 — `Panola.asMEI` / `scoreAsMEI` (Panola quark, sclang — written, user-verified)

**Repo:** `C:\Users\Stefaan Himpe\AppData\Local\SuperCollider\Extensions\panola` (commit there).
**Method:** Port `tools/panola_mei/ref.py` to SuperCollider *function-for-function*, but source the per-note data from Panola's parse tree instead of the hand-written dicts.

### Task 7: `pr_meiEvents` — structured events from the parse tree

**Files:** Modify `Classes/Panola.sc`.

- [ ] **Step 1: Add the helper.** It mirrors the interchange format. Reuse existing extraction: iterate `parsed_notation.result` after `pr_resetDefaults`; per element resolve pitch via the same logic as `pr_extractNotationNote` (letter/modifier/octave, handling `'previous'` octave default) and duration via the same logic as `durationPattern`/`notationdurationPattern` (`dur`, `durdots`, and `beats`). Return an `Array` of `IdentityDictionary` events:

```supercollider
// returns: [ ( \kind: \note|\rest, \pnames:[...], \accids:[...], \octs:[...], \meidur:Int, \dots:Int, \beats:Float ), ... ]
pr_meiEvents {
    var events = [];
    var octDefault = gOCTAVE_DEFAULT.asInteger;
    var durDefault = gDURATION_DEFAULT.asInteger, dotsDefault = 0;
    this.pr_resetDefaults;
    parsed_notation.result.do({ |el|
        var isChord = (el['type'] == 'chord');
        var isRest = (el['type'] == 'rest');
        var noteEls = isChord.if({ el['notes'] }, { [el] });
        var durEl = noteEls[0];
        var meidur = durEl['info']['note']['duration']['dur'];
        var dots = durEl['info']['note']['duration']['durdots'];
        var pnames = [], accids = [], octs = [];
        // --- resolve duration 'previous' defaults ---
        if (meidur == 'previous') { meidur = durDefault } { durDefault = meidur.asInteger };
        if (dots == 'previous') { dots = dotsDefault } { dotsDefault = dots.asInteger };
        meidur = meidur.asInteger; dots = dots.asInteger;
        // --- resolve pitch per (sub)note ---
        if (isRest.not) {
            noteEls.do({ |ne|
                var nn = ne['info']['note']['pitch']['notename'];
                var oct = ne['info']['note']['pitch']['octave'];
                var mod = ne['info']['note']['pitch']['notemodifier'];
                if (oct == 'previous') { oct = octDefault } { octDefault = oct.asInteger };
                pnames = pnames.add(nn.asString);
                octs = octs.add(oct.asInteger);
                accids = accids.add(
                    (mod == 'sharp').if({ "s" },
                    { (mod == 'doublesharp').if({ "x" },
                    { (mod == 'flat').if({ "f" },
                    { (mod == 'doubleflat').if({ "ff" }, { nil }) }) }) }));
            });
        };
        events = events.add(
            IdentityDictionary[
                \kind -> isRest.if({ \rest }, { \note }),
                \pnames -> pnames, \accids -> accids, \octs -> octs,
                \meidur -> meidur, \dots -> dots,
                \beats -> (4/meidur)*(2 - (1/(2 ** dots)))
            ]);
    });
    ^events;
}
```

> **Verification (agent):** you cannot run this. Cross-check every branch against `pr_extractNotationNote` (lines 399–438) and `durationPattern` (601–664) in the same file to be sure the `'previous'`-default handling matches. The octave-default handling here is a simplification — if Panola's octave default is stateful across the string, mirror exactly what `pr_extractNotationNote` does with `~cOCTAVE_DEFAULT`.

- [ ] **Step 2: Commit (Panola repo).** `git -C "<panola>" commit -am "feat: pr_meiEvents structured note export for MEI"`

### Task 8: `asMEI` (single staff) — port of `voice_to_measures` + element/decompose/key

**Files:** Modify `Classes/Panola.sc`.

- [ ] **Step 1: Port the pure helpers** (`decompose`, `mei_element`, `bar_beats`, `key_to_sig`, `accid_in_key`, `voice_to_measures`) as **private methods** (`pr_decompose`, `pr_meiElement`, …), translating `tools/panola_mei/ref.py` line-for-line to SC (arrays, `IdentityDictionary`, string `++`). Then:

```supercollider
asMEI {
    | meter="4/4", key="Cmajor", clef=\treble |
    ^Panola.pr_scoreAsMEI([this.pr_meiEvents], meter, key, [clef], nil);
}
```

- [ ] **Step 2: Verify by dumping + rendering** (see Task 10). No auto-run.
- [ ] **Step 3: Commit (Panola repo).** `git -C "<panola>" commit -am "feat: Panola:asMEI single-staff MEI export"`

### Task 9: `*scoreAsMEI` (multi-staff) — port of `score_to_mei`

**Files:** Modify `Classes/Panola.sc`.

- [ ] **Step 1: Implement the class method** (mirrors `score_to_mei`; takes `Panola` instances):

```supercollider
*scoreAsMEI {
    | voices, meter="4/4", key="Cmajor", clefs=nil, braces=nil |
    var eventLists = voices.collect({ |p| p.pr_meiEvents });
    clefs = clefs ? voices.collect({ \treble });
    ^Panola.pr_scoreAsMEI(eventLists, meter, key, clefs, braces);
}
```

`pr_scoreAsMEI(eventLists, meter, key, clefs, braces)` is the SC port of `score_to_mei` (bin each voice with `pr_voiceToMeasures`, pad shorter voices with `pr_emptyMeasureRest`, build the `<staffGrp>` with brace nesting, wrap in the MEI scaffold, `key.sig` from `pr_keyToSig`, accidentals via `pr_accidInKey`).

- [ ] **Step 2: Commit (Panola repo).** `git -C "<panola>" commit -am "feat: Panola.*scoreAsMEI multi-staff MEI export"`

### Task 10: SC dump test + harness cross-check

**Files:** Create `Classes/tests/test_asMEI.scd` (Panola repo). Add `tools/panola_mei/test_asMEI_files.py` (this repo).

- [ ] **Step 1: SC dump script** (`test_asMEI.scd`) — the **user runs this once**:

```supercollider
(
var dir = "C:/Scripts/Temp/claude/panola_mei/";   // any writable dir
File.mkdir(dir);
var cases = [
    ["single_treble",  Panola.scoreAsMEI([Panola("c5_4 e g c6_2 | b5_4 a g2")], "4/4", "Cmajor", [\treble], nil)],
    ["grand_staff",    Panola.scoreAsMEI([Panola("c5_4 e g a"), Panola("c3_2 g,2")], "4/4", "Cmajor", [\treble,\bass], [[1,2]])],
    ["ties",           Panola.scoreAsMEI([Panola("c5_2 c5_1 c5_4")], "4/4", "Cmajor", [\treble], nil)],   // whole across barline
    ["gmajor",         Panola.scoreAsMEI([Panola("f#5_4 g a b")], "4/4", "Gmajor", [\treble], nil)],
    ["csharpminor",    Panola.scoreAsMEI([Panola("c#5_4 d# e f#"), Panola("c#3_2 g#,2")], "4/4", "CsharpMinor", [\treble,\bass], [[1,2]])],
];
cases.do({ |c| File.use(dir ++ c[0] ++ ".mei", "w", { |f| f.write(c[1]) }) });
("wrote " ++ cases.size ++ " MEI files to " ++ dir).postln;
)
```

- [ ] **Step 2: Harness cross-check** (`tools/panola_mei/test_asMEI_files.py`, this repo) — the **agent runs this** after the user dumps the files:

```python
import glob, os
from tools.panola_mei.render_check import render_props
DIR = "C:/Scripts/Temp/claude/panola_mei"
def test_all_dumped_mei_render():
    files = glob.glob(os.path.join(DIR, "*.mei"))
    assert files, "run test_asMEI.scd in SuperCollider first"
    for f in files:
        p = render_props(open(f, encoding="utf-8").read())
        assert p["ok"], f"{os.path.basename(f)} failed: rc={p['returncode']} {p['stderr'][:200]}"
    # spot checks
    ties = render_props(open(os.path.join(DIR,"ties.mei"),encoding="utf-8").read())
    assert ties["has_tie"]
    grand = render_props(open(os.path.join(DIR,"grand_staff.mei"),encoding="utf-8").read())
    assert grand["treble_clefs"] >= 1 and grand["bass_clefs"] >= 1
```

- [ ] **Step 3:** User runs `test_asMEI.scd`; agent runs `py -m pytest tools/panola_mei/test_asMEI_files.py -q` → PASS. Fix `Panola.sc` if any file fails to render, comparing against `ref.py`.
- [ ] **Step 4: Commit** the harness cross-check in this repo; commit `test_asMEI.scd` in the Panola repo.

---

## Phase 3 — `MSScore` (MusicScene, sclang — written, interactive-verified)

**File:** Create `examples/supercollider/MSScore.sc`. No automated test (needs sclang + a live MusicScene + audio). Written to the spec's data flow; verified by the Phase-4 example.

### Task 11: class skeleton + `.show`

- [ ] Implement `MSScore` (a plain class): store `voices` (wrap strings into `Panola`), `meter`, `key`, `clefs`, `braces`, `tempo`, `id`, `space`, `engine` (`NetAddr`), `replyPort`. `.show` builds MEI via `Panola.scoreAsMEI(panolas, meter, key, clefs, braces)` and sends, paced, in a `Routine`: `new notation`, `background "white"`, `scale`, `pos` (space-aware), `addressable 1`, `notationData mei <mei>`. Commit.

### Task 12: `.play` — playback

- [ ] `.play` runs `.show`, then starts a `TempoClock(tempo/60)` and plays `Ppar(panolas.collect { |p,i| p.asPbind(instr[i], include_tempo:false) }).play(~clock, quant:0)`. Default `instr` `\default` (or a bundled `\pnote`). Commit.

### Task 13: cursor via `elements`

- [ ] After `.show`, open `replyPort` (`thisProcess.openUDPPort`), register `OSCdef(\ms_elements, { |msg| ... }, '/ms/reply')` filtering the `elements` topic; parse `[id, i, when, line, char, u, v, ...]` into an ordered, de-duped `[(when,u)]` list (unique `when`s). Request `elements` after a short render delay; retry up to 3× until non-empty. Then in `.play`, fork a cursor routine on `~clock`: for each `(when,u)`, `wait` to `when*4` beats, `sendMsg("/ms/scene/<id>/cursor","pos",u,0.5)`. If no `elements` within timeout → warn + linear sweep over `totalDuration`. `cursor show 1` at start. Commit.

### Task 14: `.stop`

- [ ] `.stop`: stop the `Ppar` player + cursor routine, stop the clock, `s.freeAll`, `OSCdef(\ms_elements).free`, `sendMsg("/ms/scene","clear")`. Commit.

---

## Phase 4 — Example + docs (MusicScene)

### Task 15: worked example

**File:** Create `examples/supercollider/example_panola_score.scd`.

- [ ] A complete `( s.waitForBoot({ ... }) )` block: define a simple `\pnote`, build an `MSScore` with a 2–3 voice Panola score (treble + bass, braced), `.play`; a CLEANUP block calling `~score.stop`. Header comment mirroring the other examples (requires Verovio; set `~space`). This doubles as the acceptance test the user runs. Commit.

### Task 16: docs

**Files:** Modify `TUTORIAL.md` (examples list), `README.md` (notation section — mention the Panola front door), `CHANGELOG.md` (Unreleased → Added).

- [ ] Add a TUTORIAL bullet: "Write a score in Panola and get live notation + audio + a following cursor with `MSScore` — `examples/supercollider/example_panola_score.scd`." Note the two entry points (`Panola.scoreAsMEI` standalone; `MSScore(...).play`). CHANGELOG "Added" entry. Commit.

---

## Self-review

- **Spec coverage:** note mapping (T2), meter+ties (T3–T4), decomposition (T3), multi-staff+braces+padding (T5), key+relative accidentals (T6), `Panola.asMEI`/`scoreAsMEI` (T7–T9), `MSScore` show/play/stop (T11/12/14), note-accurate cursor + fallback (T13), example (T15), docs (T16), testing strategy (T1 + T10). Covered.
- **Type consistency:** the event dict keys (`kind/pnames/accids/octs/meidur/dots/beats`) are identical in T2, T4, T5, and the SC `pr_meiEvents` (T7). `mei_element`/`decompose`/`voice_to_measures`/`score_to_mei`/`key_to_sig`/`accid_in_key` names are used consistently; SC private ports use the `pr_` prefix of the same names.
- **Constraint honesty:** Phases 2–3 are explicitly "written, not auto-run"; their verification is the T10 dump-and-render cross-check and the T15 interactive example.
