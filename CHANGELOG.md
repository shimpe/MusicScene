# Changelog

All notable changes to **gscore_osc** are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [0.2.0] — 2026-06-30

A large feature pass since the initial implementation.

### Added
- **2D and 3D** support, selectable via `gscore_osc/space` (`"2d"` | `"3d"`), behind a spatial
  backend abstraction (`GScoreSpatial2D` / `GScoreSpatial3D`). Same OSC API for both; 3D auto-creates
  a `Camera3D` and uses camera-ray picking; notation renders on a textured quad in world space.
- **Runtime-generated scores**: a notation source may be a file path (`res://` / `user://` /
  absolute), inline data over OSC (SVG/MusicXML/LilyPond/ABC string, or raster bytes as a blob), or
  symbolic music engraved on the fly. `notationData` forces inline data.
- **External engravers**: per-format commands (`notation/engraver/<fmt>`), tokens
  `{input} {output} {outbase} {outdir} {format} {page}`, `res://` resolution, and automatic
  resolution of self-named outputs. Working defaults for **MuseScore** (MusicXML),
  **LilyPond** (`.ly`), and **Verovio** (MEI/ABC, `pip install verovio`).
- **Async (non-blocking) engraving** via `OS.create_process` + polling — the app stays responsive
  while an engraver runs; results are cached.
- **Addressable / following notation**:
  - MuseScore → measure regions + timing (`.mpos`); `measures` query; `cursor measure <n>`.
  - LilyPond → note-level regions + timing (injected Scheme tagger + point-and-click SVG).
  - Verovio → note-level regions + timing (stable SVG ids + timemap).
  - `addressable 1`, `elements` query, clickable note/measure regions, and `cursor follow 1`
    (cursor tracks the transport and emits `/gscore/event/note` / `/gscore/event/measure`).
- SVG notation: prefers Godot's import for `res://`, runtime-rasterizes other paths/inline.
- `TUTORIAL.md` (2D + 3D getting started, all score-display options), bundled engraver wrappers and
  test tools, CI, this changelog.

### Fixed
- OSC argument coercion uses `str()` (not the `String()` constructor) so non-string args (blobs,
  numbers) no longer crash with "Nonexistent 'String' constructor".
- `res://` SVG scores load via Godot's import instead of fragile runtime re-rasterization.
- RefCounted cycle (object ↔ physics adapter) and freed-lambda crashes cleaned up.

## [0.1.0]

Initial implementation: OSC server + codec, dispatcher, registry (OSC-id ⇄ node), built-in objects,
transforms, notation (PNG/SVG, cursor, regions, annotations), 2D physics + collision/area/input
events, signal forwarding, node binding, PackedScene instantiation, transport + time mapping, script
runner, permissions, examples, README.
