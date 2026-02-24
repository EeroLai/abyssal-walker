# Changelog

All notable changes to this project are documented in this file.

This format is based on Keep a Changelog and uses simple sections:
- `Added`
- `Changed`
- `Fixed`
- `Balance`

## [Unreleased]

### Added
- Skill tag support for `chain`, and a new beam skill: `Arc Lightning`.
- Enemy ranged attack flow with enemy projectile logic.
- Debug convenience: start with all skill gems and extra white-quality backup weapons.

### Changed
- Arc Lightning switched from projectile-style behavior to beam-style chain behavior.
- Core skill and support parsing/display paths updated for chain-related stats/tags.

### Fixed
- Resolved invalid `take_damage` argument cases caused by previously freed projectile references.
- Type mismatch fixes around typed array return paths in player scripts.

### Balance
- Dagger-related skills now attack faster.
- Shadow Tide single-hit performance tuned up.
- Damage variance changed to `+/-8%` with tunable constants preserved.
- Enemy elemental resistance pressure reduced to avoid nullifying elemental builds.

## [Archive]

When this file grows large:
1. Keep recent versions here (about 5-10 releases).
2. Move older entries to `docs/changelog/<year>.md`.
3. Leave one-line summaries here with links to archive files.
