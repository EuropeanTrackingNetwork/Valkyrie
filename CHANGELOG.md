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
