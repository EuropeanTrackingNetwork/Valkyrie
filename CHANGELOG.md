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
- Safe guard at startup to make sure that if the config file, or other files required for the startup function are not available during startup the app will be unusable.
- Safe guard added in createDateTime.m to give more explicit error if the config file did not load properly.
- The version of valkyrie that is running/being called will be displayed in the startup window title and at the bottom of the window. It will aslo be saved in the log file.

### Changed
-

### Fixed
- The valkyrieVersion.m was incorectly places in the /build folder. It has been moved to the /app_source folder that is part of the compile.
