# Changelog

All notable changes to this project are documented in this file.

This format is based on Keep a Changelog and uses simple sections:
- `Added`
- `Changed`
- `Fixed`
- `Balance`

## [Unreleased]

### Added
- New Lobby scene (`scenes/main/lobby.tscn`) as project entry.
- Lobby stash loot browser with category switching:
  - Equipment
  - Skill Gems
  - Support Gems
  - Modules
- Lobby operation loadout management:
  - Move stash loot into loadout
  - Move loadout loot back to stash
  - Clear loadout
- Run summary panel in HUD (manual confirm flow with `E`).
- Operation loadout application to player at run start.
- Run loot storage model:
  - `run_backpack_loot`
  - `stash_loot`

### Changed
- Main scene switched from game directly to lobby (`project.godot`).
- Core loop changed to operation-based extraction flow.
- Materials changed to stash-only persistent resources (not run risk assets).
- Extract and fail return flow now waits for player confirmation instead of instant transition.
- Drop scaling unified around operation strength (`operation_level + danger`) across equipment/gems/modules.

### Fixed
- Fixed multiple encoding/mojibake issues in gameplay and UI scripts.
- Fixed lobby scene parse issues caused by BOM/encoding mismatch.
- Fixed lobby `@onready` node path mismatches causing null instance access.
- Removed obsolete floor +/- controls and related dead code paths.

### Balance
- Danger progression integrated with floor clear / elite / boss events.
- Module drop selection weighted by operation effective level.

## [1.1.0] - 2026-02-24

Release notes: `docs/releases/v1.1.0.md`

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
