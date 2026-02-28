# abyssal-walker

[English](README.md) | [Traditional Chinese](README.zh-TW.md)

`abyssal-walker` is a Godot 4 action RPG prototype built around a beacon-driven abyss run loop:

- Prepare in the lobby
- Select an `Abyss Beacon`
- Dive, loot, and manage danger
- Extract rewards or lose run loot on failure

## Gameplay Preview

<p align="center">
  <img src="readme-assets/gameplay-main.gif" alt="Main Gameplay" width="860" />
</p>

## Screenshots

<p align="center">
  <img src="readme-assets/screenshot-combat.png" alt="Combat" width="31%" />
  <img src="readme-assets/screenshot-build-panel.png" alt="Build Panel" width="31%" />
  <img src="readme-assets/screenshot-crafting.png" alt="Crafting" width="31%" />
</p>

## Current Gameplay Loop

1. Enter the `Lobby`
2. Review stash resources and configure the operation loadout
3. Select an `Abyss Beacon` from inventory
4. If no beacon is available, start a `Baseline Dive`
5. Enter the run with beacon-defined:
   - `base_difficulty`
   - `max_depth`
   - `lives_max`
   - `modifier_ids`
6. Clear floors, build `danger`, and fight elites on the way down
7. Decide whether to extract during extraction windows or push deeper
8. Defeat the boss at the beacon's `max_depth`
9. Bring rewards back to the lobby, or lose run backpack loot on failure

## Core Systems

- Lobby-driven preparation flow
- Beacon inventory and consumption
- `Baseline Dive` fallback when beacon inventory is empty
- Beacon-generated runs with:
  - template-based depth/life distributions
  - data-driven modifiers
  - boss-guaranteed beacon drops
- Effective scaling based on:
  - `base_difficulty + depth - 1 + danger`
- Run risk inventory:
  - `run_backpack_loot`
- Persistent storage:
  - `stash_loot`
  - `stash_materials`
- Loadout prep from stash before each run
- Data-driven abyss content in:
  - `data/abyss/floors.json`
  - `data/abyss/beacon_modifiers.json`
  - `data/abyss/beacon_templates.json`

## Beacon System

- Beacons define the structure of each run instead of manual run parameter setup.
- Standard beacon fields include:
  - `base_difficulty`
  - `max_depth`
  - `lives_max`
  - `modifier_ids`
  - `template_id`
- Beacons are consumed on activation.
- Bosses always drop a beacon.
- Normal and elite enemies can also drop beacons at lower rates.
- Boss-only high-end templates can reach the deepest runs.

## Controls

- `I`: Equipment panel
- `K`: Skill panel
- `C`: Crafting panel
- `M`: Module panel
- `Z`: Pickup nearby loot
- `L`: Cycle loot filter
- `E`: Confirm extraction / confirm summary return
- `F`: Continue during extraction window
- `N`: Challenge pending failed floor
- `Esc`: Pause

## Main Scenes

- Lobby: `scenes/main/lobby.tscn`
- Game: `scenes/main/game.tscn`

## Quick Start

1. Install Godot 4.x
2. Open this project folder in Godot
3. Run the project
4. The project starts in the lobby

## Changelog

See `CHANGELOG.md`.
