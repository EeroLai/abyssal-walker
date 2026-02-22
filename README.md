# abyssal-walker

《abyssal-walker》是一個使用 Godot 4 製作的 2D 動作 RPG 原型專案。  
目前聚焦在深淵推層、戰鬥、掉寶、裝備詞綴、技能與支援連結、模組配置，以及 Crafting 系統。

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

## 專案結構

- `scenes/main/game.tscn`：主場景
- `scripts/main`：遊戲主流程
- `scripts/entities`：玩家、敵人、投射物
- `scripts/core`：數值、裝備、寶石、模組、狀態、Crafting、掉寶
- `scripts/ui`：HUD 與系統面板
- `scripts/autoload`：全域管理器
- `data/*.json`：資料驅動內容

## 快速開始

1. 安裝 Godot 4.x
2. 用 Godot 開啟此資料夾
3. 執行 `scenes/main/game.tscn`
