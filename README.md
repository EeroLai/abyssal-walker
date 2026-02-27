# abyssal-walker

[English](README.md) | [蝜?銝剜?](README.zh-TW.md)

`abyssal-walker` is a Godot 4 action RPG prototype built around an operation-style risk/reward loop:

- Prepare in lobby
- Enter an operation run
- Loot and decide whether to extract
- Bank rewards on extraction, or lose run loot on failure

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

1. Enter `Lobby`
2. Set `Operation Level` and `Lives`
3. Configure operation loadout from stash loot
4. Enter run and clear abyss encounters
5. Collect loot (equipment / skill gems / support gems / modules)
6. Choose to extract or keep pushing
7. Confirm run summary and return to lobby

## Core Systems

- Operation session state (`operation_level`, `danger`, `lives`)
- Risk-scaled drop quality
- Run backpack loot (`run_backpack_loot`)
- Persistent stash loot (`stash_loot`)
- Persistent stash materials (`stash_materials`)
- Manual confirm extraction/failure summary flow
- Data-driven content in `data/*.json`

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
3. Run the project (entry scene is lobby)

## Changelog

See `CHANGELOG.md`.
