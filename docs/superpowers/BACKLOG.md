# MusicScene — Backlog

Deferred features and open points, gathered from the design specs, the `true-3d-future-phase`
memory, and code TODOs. Items scoped out **on purpose** (v1 boundaries) are listed separately
from features actually intended for future work. When an item is picked up, brainstorm → spec →
plan under `docs/superpowers/` as usual, and move it to the relevant CHANGELOG once shipped.

Last reviewed: 2026-07-08 (after Panola 0.6.0 / MSScore 0.3.0 / MusicScene v0.16.0).

## Panola notation (active area — most likely next)

- **Cross-staff notation** — on the v2 roadmap, never built.
  Source: `specs/2026-07-05-panola-musicscene-score-design.md`.
- **Nested tuplets** (a tuplet-ratio change mid-run that is itself a tuplet) — renders a
  best-effort bracket + warning. Source: `specs/2026-07-05-panola-tuplets-design.md`.
- **Animated string property values** — word-valued properties are static/one-shot only.
  Source: `specs/2026-07-05-panola-expression-design.md`.
- **Inexpressible tuplet fragments** — barline-crossing / degenerate cases fall back to a warned
  partial bracket instead of exact spelling.
  Source: `specs/2026-07-07-panola-barline-crossing-tuplets-design.md`.
- **Meter-splitting cost model** (Parts 5–6 of the source pseudocode) — deferred optional
  refinement. Source: `specs/2026-07-07-panola-meter-splitting-design.md`.

## Notation engine (MusicScene side)

- **Lightweight glyph backend** — `MSNotationRenderer.gd:40` returns "not implemented in v1".
- **Auto-generated notation regions** — v1 regions are manual; a future renderer could
  auto-generate them. Source: `addons/musicscene/notation/MSNotationRegion.gd`.

## 3D / volumetric (longer horizon)

Workstreams (a) volumetric primitives and (b) lighting shipped in 0.10.0. Still deferred
(memory `true-3d-future-phase`, `specs/2026-07-02-true-3d-future-phase.md`):

- **(c) Runtime glTF / `.obj` model loading** — today only pre-imported `.tscn` via
  `instantiate`. The named remaining item if 3D work resumes.
- **Per-material textures, animated 3D backgrounds** — future-phase non-goals.

## Deliberate v1 scoping (documented — not necessarily planned)

Scoped out on purpose; revisit only if a use case appears.

- **Camera:** near/far clip planes, dolly/zoom (pan/zoom) camera.
  Source: `specs/2026-07-01-camera-design.md`.
- **Multi-port OSC:** per-port filtering — whole-list-replace deemed sufficient.
  Source: `specs/2026-07-03-multi-port-osc-output-design.md`.
- **Collision reactors:** arbitrary concave collider shapes.
  Source: `specs/2026-07-04-collision-reactors-design.md`.
- **Sensor zones / joints / event-completion:** assorted v1 out-of-scope items in their specs.
