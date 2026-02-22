# abyssal-walker

[English](README.md) | [繁體中文](README.zh-TW.md)

`abyssal-walker` 是一個使用 Godot 4 製作的 2D 動作 RPG 原型專案。

本專案聚焦在快節奏戰鬥、深淵樓層推進，以及透過掉寶、詞綴、寶石與模組進行 Build 構築。

## 遊玩預覽

<p align="center">
  <img src="docs/images/gameplay-main.gif" alt="Main Gameplay" width="860" />
</p>

## 截圖

<p align="center">
  <img src="docs/images/screenshot-combat.png" alt="Combat" width="31%" />
  <img src="docs/images/screenshot-build-panel.png" alt="Build Panel" width="31%" />
  <img src="docs/images/screenshot-crafting.png" alt="Crafting" width="31%" />
</p>

## 遊戲概要

你將操作一名會自動攻擊的角色，在深淵中持續推進更高樓層。  
每一輪遊戲的核心循環是：

1. 清除敵人並完成樓層目標
2. 撿取掉落物與升級資源
3. 透過裝備、寶石、模組與 Crafting 強化 Build
4. 持續推層，或在卡關時切換到指定樓層農裝

## 核心功能

- 深淵推進流程，包含樓層目標與 Boss 里程碑樓層
- 連續失敗後的 Push/Farm/Retry 流程切換
- 資料驅動設計：敵人、道具、詞綴、寶石、模組、樓層皆由 `data/*.json` 配置
- 裝備系統：稀有度、前後綴詞綴、背包管理
- 技能寶石 + 支援寶石連結系統（投射物、連鎖、穿透、範圍等修正）
- 模組面板（Core Board）系統：負載成本與數值方向化配置
- Crafting 素材與行為：`alter`、`augment`、`refine`
- 狀態效果：`burn`、`freeze`、`shock`、`bleed` 與戰鬥回饋
- HUD：DPS、擊殺數、掉落過濾、推進狀態、拾取訊息

## 目前內容快照

- 主要可玩場景：`scenes/main/game.tscn`
- 已實作系統：
  - 戰鬥、投射物、近戰/遠程技能處理
  - 敵人生成與波次/樓層循環
  - 掉落與拾取
  - 裝備面板
  - 技能連結面板
  - Crafting 面板
  - 模組面板

## 操作按鍵

- `I`：裝備面板
- `K`：技能連結面板
- `C`：Crafting 面板
- `M`：模組面板
- `Z`：吸取附近掉落物
- `L`：切換掉落過濾
- `-` / `=`：降低/提高目前農裝樓層
- `N`：挑戰失敗中的樓層
- `Esc`（暫停動作）：暫停/繼續

## 專案結構

- `scenes/main/game.tscn`：主場景
- `scripts/main`：主流程與樓層推進
- `scripts/entities`：玩家、敵人、投射物邏輯
- `scripts/core`：數值、裝備、寶石、模組、狀態、Crafting、掉寶
- `scripts/ui`：HUD 與各系統面板
- `scripts/autoload`：全域管理器與事件流
- `data/*.json`：資料驅動遊戲內容

## 快速開始

1. 安裝 Godot 4.x
2. 使用 Godot 開啟此資料夾
3. 執行 `scenes/main/game.tscn`
