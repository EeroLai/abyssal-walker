# abyssal-walker

[English](README.md) | [繁體中文](README.zh-TW.md)

`abyssal-walker` 是一個以 Godot 4 製作的動作 RPG 原型，核心循環建立在「深淵信標」驅動的冒險流程上：

- 在大廳整理資源與配裝
- 選擇一顆 `Abyss Beacon`
- 進入深淵、戰鬥、撿裝、累積風險
- 成功抽離帶回收益，或在失敗時失去本趟掉落

## 遊戲預覽

<p align="center">
  <img src="readme-assets/gameplay-main.gif" alt="Main Gameplay" width="860" />
</p>

## 截圖

<p align="center">
  <img src="readme-assets/screenshot-combat.png" alt="Combat" width="31%" />
  <img src="readme-assets/screenshot-build-panel.png" alt="Build Panel" width="31%" />
  <img src="readme-assets/screenshot-crafting.png" alt="Crafting" width="31%" />
</p>

## 目前玩法循環

1. 進入 `Lobby`
2. 檢查倉庫資源並整理本次出擊的 loadout
3. 從持有庫存中選擇一顆 `Abyss Beacon`
4. 如果目前沒有任何信標，可改用 `Baseline Dive`
5. 依照信標設定開啟本次探索，信標會決定：
   - `base_difficulty`
   - `max_depth`
   - `lives_max`
   - `modifier_ids`
6. 逐層推進、累積 `danger`，並處理菁英與一般敵人
7. 在抽離視窗中決定要撤出，或繼續往下推進
8. 在信標的 `max_depth` 遭遇尾王
9. 回到大廳結算；成功抽離可保留成果，失敗則會失去本趟 `run_backpack_loot`

## 核心系統

- 以大廳為中心的準備流程
- 深淵信標庫存與消耗
- 當信標庫存為 0 時提供保底用的 `Baseline Dive`
- 由信標決定每趟 run 的深度、命數與 modifier
- 難度與掉落品質主軸：
  - `base_difficulty + depth - 1 + danger`
- 本趟風險掉落：
  - `run_backpack_loot`
- 永久保留的倉庫資源：
  - `stash_loot`
  - `stash_materials`
- 每次出擊前可從 stash 配置 loadout
- 深淵相關內容採資料驅動：
  - `data/abyss/floors.json`
  - `data/abyss/beacon_modifiers.json`
  - `data/abyss/beacon_templates.json`

## 信標系統

- 現在不是手動設定 run 參數，而是透過信標決定整趟探索內容。
- 信標目前的主要欄位包括：
  - `base_difficulty`
  - `max_depth`
  - `lives_max`
  - `modifier_ids`
  - `template_id`
- 啟動信標後會消耗該信標。
- 尾王一定會掉落信標。
- 一般怪與菁英怪也有較低機率掉落信標。
- 最高深度的高端信標只會從 Boss 掉落池出現。

## 操作鍵位

- `I`：裝備面板
- `K`：技能面板
- `C`：Crafting 面板
- `M`：模組面板
- `Z`：吸取附近掉落物
- `L`：切換掉落過濾
- `E`：確認抽離 / 確認結算返回
- `F`：在抽離視窗中選擇繼續
- `N`：挑戰待重試樓層
- `Esc`：暫停

## 主要場景

- 大廳：`scenes/main/lobby.tscn`
- 遊戲：`scenes/main/game.tscn`

## 快速開始

1. 安裝 Godot 4.x
2. 用 Godot 開啟本專案資料夾
3. 執行專案
4. 進入點目前是大廳場景

## 版本紀錄

請參考 `CHANGELOG.md`。
