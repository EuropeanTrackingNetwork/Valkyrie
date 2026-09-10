# Changelog

All notable changes to Valkyrie are documented in this file.

Format loosely follows [Keep a Changelog](https://keepachangelog.com/), and
versioning follows [Semantic Versioning](https://semver.org/):
`MAJOR.MINOR.PATCH`

- **MAJOR** — breaking change (input file format, saved-session compatibility, workflow removed)
- **MINOR** — new feature, backwards compatible
- **PATCH** — bug fixes only

Each entry here should match a tagged GitHub release (`vX.Y.Z`) and the value
returned by `app_source/valkyrieVersion.m` at that commit.

## [Unreleased]

### Added
-

### Changed
-

### Fixed
-

---

## [1.0.0] — 2026-09-04

### Added
- New column added: minICI. This records the minimum ICI in a minute, where clicks were recorded
- Error log (diary) added.
- Version label added.

### Changed
- Buttons visible in night mode.
- Updates to matching between POD files and metadata logic.

## [1.0.1] - 2026-09-10

### Added
- Safeguard at startup: if the configuration file or anything else the startup
  routine needs is unavailable, the app now reports it immediately and disables
  the file and metadata buttons, instead of continuing in a half-initialised state.
- Safeguard in `createDateTime.m`: a clearer error when the configuration did not
  load, and malformed date/time values are now reported per row with the offending
  value instead of failing with an opaque conversion error.
- The running version is shown in the window title and at the bottom of the window,
  and written to the session log together with the application path.

### Changed
- `build_valkyrie.m` now verifies before compiling that `valkyrieVersion.m` is
  detected as a dependency and resolves from `app_source`, and passes it explicitly
  in `AdditionalFiles`.

### Fixed
- `valkyrieVersion.m` was incorrectly placed in `/build` and therefore not
  guaranteed to be part of the compiled app. Moved to `/app_source`.
- A failure during startup could leave the app running with no configuration
  loaded. The first visible symptom was a misleading "Metadata Error: Dot indexing
  is not supported for variables of this type" when loading a metadata file. Such
  failures are now reported at launch.

### Note
- Several distinct installers were circulated as 1.0.0. If you are unsure which
  build you have, reinstall 1.0.1 — from this release on, every published
  installer corresponds to a tagged commit.