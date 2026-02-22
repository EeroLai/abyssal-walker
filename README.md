# abyssal-walker

這是一個使用 Godot 4 製作的 2D 動作 RPG 原型專案。

目前核心內容聚焦在深淵推層、戰鬥、掉寶、裝備詞綴、
技能與支援連結、模組配置，以及 Crafting 系統。

## 遊玩預覽

![Main Gameplay](docs/images/gameplay-main.gif)

## 截圖

![Combat](docs/images/screenshot-combat.png)
![Build Panel](docs/images/screenshot-build-panel.png)
![Crafting](docs/images/screenshot-crafting.png)

請把素材放在 `docs/images/`，檔名使用上面範例，
或自行修改本 README 的圖片路徑。

## 專案結構

- `scenes/main/game.tscn`：主場景
- `scripts/main`：遊戲主流程
- `scripts/entities`：玩家、敵人、投射物
- `scripts/core`：數值、裝備、寶石、模組、狀態、Crafting、掉寶
- `scripts/ui`：HUD 與各系統面板
- `scripts/autoload`：全域管理器
- `data/*.json`：資料驅動內容

## 快速開始

1. 安裝 Godot 4.x。
2. 用 Godot 開啟此資料夾。
3. 執行 `scenes/main/game.tscn`。
