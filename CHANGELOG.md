# Changelog

All notable changes to this project are documented in this file.

This format is based on Keep a Changelog and uses simple sections:
- `Added`
- `Changed`
- `Fixed`
- `Balance`

## [Unreleased]

## [2.3.0] - 2026-02-28

### Added
- Data-driven abyss beacon modifier definitions via:
  - `data/abyss/beacon_modifiers.json`
- Data-driven abyss beacon template definitions via:
  - `data/abyss/beacon_templates.json`
- Boss-only high-end beacon template:
  - `abyssal`

### Changed
- Beacon modifier logic now loads from data tables instead of hardcoded definitions in script.
- Beacon template generation now loads from data tables for:
  - source pools
  - template weights
  - base difficulty offsets
  - depth ranges
  - lives ranges
  - modifier roll pools
  - post-generation constraints
- Beacon instances now store `template_id` so generation data and lobby presentation share the same source of truth.
- Lobby beacon cards now derive type labels and accent colors from template metadata instead of heuristic checks.
- Baseline dive is now only offered when beacon inventory is empty.

### Balance
- Normal enemy beacon drops now skew further toward safe/balanced templates.
- Pressure beacons no longer appear from normal enemy drops.
- Elite drops now favor balanced/deep templates with lower pressure weight.
- Boss drops now split between balanced, deep, pressure, and low-weight abyssal templates.
- Deep beacon depth ranges were tightened so `20-50` is no longer the default boss deep-roll band.
- Maximum depth `50` is now reserved for the low-weight boss-only `abyssal` template.
- Pressure beacon depth ranges were reduced to keep them focused on short high-risk runs.

## [2.2.0] - 2026-02-28

### Added
- Abyss beacon run model with dedicated beacon data and modifier systems:
  - `AbyssBeaconData`
  - `BeaconModifierSystem`
- Lobby beacon inventory flow with card-based selection UI.
- Baseline fallback dive that can start a lowest-tier run without consuming a beacon.
- Beacon inventory runtime event:
  - `beacon_inventory_changed`
- Beacon acquisition HUD notifications.
- Beacon drop generation pipeline for:
  - Normal enemies
  - Elite enemies
  - Bosses

### Changed
- Lobby run start flow now uses selected beacons instead of direct `Operation Level` / `Lives` setup.
- Operation session semantics were rewritten around:
  - `base_difficulty`
  - `max_depth`
  - `modifier_ids`
- Effective scaling formula is now based on:
  - `base_difficulty + depth - 1 + danger`
- Boss spawn cadence now resolves at beacon `max_depth` instead of `% 10` floor rhythm.
- Beacon selection UI moved away from simple list/dropdown selection into a grid-style inventory presentation.

### Fixed
- Fixed boss spawning logic being mixed between floor anchor config and run depth cadence.
- Fixed elite spawn chance scaling from raw floor progression instead of effective difficulty.
- Fixed combat/drop configuration responsibilities that were previously scattered through `game.gd`.

### Balance
- Bosses now always award a beacon.
- Normal enemies now have a very low chance to award a beacon, and elites have a low chance.
- Beacon depth distribution is now split by source:
  - Normal/elite drops stay in the low-to-mid range
  - Boss drops can reach the highest deep-run ranges
- Beacon modifiers now affect combat pressure and beacon rewards through enemy HP/ATK/count, elite rate, beacon quality, and extra boss beacon reward.

## [2.1.0] - 2026-02-28

### Changed
- Unified operation loadout return logic into a single loot ledger state machine for all tracked categories:
  - Equipment
  - Skill Gems
  - Support Gems
  - Modules
- Added dedicated transition events for runtime swap tracking:
  - `support_gem_changed`
  - `module_changed`

### Fixed
- Fixed displaced item tracking when swapping with run-dropped items:
  - Replacing equipped equipment with run-dropped equipment now correctly tracks the old item for end-of-run resolution.
  - Same displaced-tracking rule now applies consistently to skill gems, support gems, and modules.
- Fixed end-of-run reconciliation edge cases where operation loadout items could remain in player inventory instead of being resolved by policy.

## [2.0.1] - 2026-02-27

### Fixed
- Fixed module load cost becoming `0` after extract -> lobby -> re-enter flow when operating module equip/unequip.
- Fixed support gem disappearing when equip attempt fails due to incompatibility and then unequipping from support slot.

## [2.0.0] - 2026-02-27

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
