# abyssal-walker

[English](README.md) | [繁體中文](README.zh-TW.md)

`abyssal-walker` 是以 Godot 4 製作的 2D 動作 RPG 原型，核心是行動制的風險與回報循環：

- 在大廳準備
- 進入一場行動
- 戰鬥與撿寶，決定是否撤離
- 成功撤離可入庫，失敗則失去本場戰利品

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

## 目前玩法循環

1. 進入 `Lobby`
2. 設定 `Operation Level` 與 `Lives`
3. 從倉庫配置本次行動裝載
4. 進入深淵戰鬥並推進遭遇
5. 收集掉落（裝備 / 主技能寶石 / 輔助寶石 / 模組）
6. 選擇撤離或繼續推進
7. 確認本場結算後返回大廳

## 核心系統

- 行動狀態（`operation_level`、`danger`、`lives`）
- 風險驅動的掉落品質
- 本場背包戰利品（`run_backpack_loot`）
- 持久化倉庫戰利品（`stash_loot`）
- 持久化倉庫材料（`stash_materials`）
- 撤離/失敗後需手動確認的結算流程
- `data/*.json` 驅動內容配置

## 操作鍵位

- `I`：裝備面板
- `K`：技能面板
- `C`：製作面板
- `M`：模組面板
- `Z`：拾取附近掉落
- `L`：切換掉落篩選
- `E`：確認撤離 / 確認結算返回
- `F`：撤離視窗期間選擇繼續
- `N`：挑戰暫存失敗樓層
- `Esc`：暫停

## 主要場景

- 大廳：`scenes/main/lobby.tscn`
- 戰鬥：`scenes/main/game.tscn`

## 快速開始

1. 安裝 Godot 4.x
2. 用 Godot 開啟本專案資料夾
3. 執行專案（入口場景為 Lobby）

## 版本紀錄

請參考 `CHANGELOG.md`。
