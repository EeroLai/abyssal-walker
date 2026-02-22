# abyssal-walker

[English](README.md) | [繁體中文](README.zh-TW.md)

`abyssal-walker` 是一款使用 Godot 4 開發的 2D 動作 RPG 原型。

這個專案主打快節奏戰鬥與深淵推層玩法，並透過裝備、詞綴、寶石連結、模組與 Crafting，讓玩家逐步打造自己的流派。

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

## 遊戲內容

玩家將操作會自動攻擊的角色，在深淵樓層中持續推進。  
每輪核心流程大致如下：

1. 清怪並完成樓層目標
2. 撿取掉落物與素材
3. 透過裝備、寶石、模組與 Crafting 強化角色
4. 繼續推進，或在卡關時改刷指定樓層

## 核心功能

- 深淵樓層推進，含一般目標與 Boss 里程碑樓層
- Push / Farm / Retry 的進度循環
- 資料驅動設計：敵人、裝備、詞綴、寶石、模組、樓層皆由 `data/*.json` 控制
- 裝備系統：稀有度、前後綴詞綴、背包管理
- 技能寶石 + 支援寶石連結（投射物、連鎖、穿透、範圍等修正）
- 模組盤（Core Board）配置與負載成本機制
- Crafting 系統（`alter`、`augment`、`refine`）
- 異常狀態（`burn`、`freeze`、`shock`、`bleed`）與戰鬥回饋
- HUD 顯示 DPS、擊殺數、掉落過濾、推進狀態與拾取訊息

## 目前已實作內容

- 主可玩場景：`scenes/main/game.tscn`
- 已完成系統：
  - 戰鬥、投射物、近戰/遠程技能行為
  - 敵人生成與樓層循環
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
- `-` / `=`：降低 / 提高目前刷裝樓層
- `N`：挑戰目前失敗樓層
- `Esc`（Pause）：暫停 / 繼續

## 專案結構

- `scenes/main/game.tscn`：主場景
- `scripts/main`：主流程與樓層推進
- `scripts/entities`：玩家、敵人、投射物
- `scripts/core`：數值、裝備、寶石、模組、狀態、Crafting、掉寶
- `scripts/ui`：HUD 與系統面板
- `scripts/autoload`：全域管理與事件流
- `data/*.json`：資料驅動內容

## 快速開始

1. 安裝 Godot 4.x
2. 使用 Godot 開啟本專案資料夾
3. 執行 `scenes/main/game.tscn`
