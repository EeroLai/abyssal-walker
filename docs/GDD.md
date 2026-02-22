# Abyssal Walker - Game Design Document (GDD)

## 文件資訊
- 專案名稱：Abyssal Walker
- 引擎版本：Godot 4.6（GL Compatibility）
- 文件版本：v0.1（依目前程式碼實作狀態）
- 更新日期：2026-02-22
- 主執行場景：`scenes/main/game.tscn`

## 1. 遊戲定位
### 1.1 類型與核心體驗
- 2D ARPG（自動戰鬥 + 養成 + 爬塔）
- 核心樂趣：
  - 透過裝備、寶石連結、模組組出 Build
  - 在深淵樓層中持續推進與刷裝
  - 於死亡與資源壓力下做樓層策略切換（Push/Farm/Retry）

### 1.2 目標玩家
- 喜歡 PoE / Vampire Survivors 式數值成長與配裝的玩家
- 偏好短局循環、穩定掉落回饋與系統疊加深度

## 2. 核心玩法循環
1. 進入樓層（`Game._start_floor`）
2. 玩家 AI 自動索敵、移動、攻擊（`PlayerAI` + `Player`）
3. 擊殺敵人，觸發掉落（裝備 / 寶石 / 模組 / 材料）
4. 拾取後開面板調整 Build（裝備、寶石連結、Crafting、模組）
5. 完成樓層目標後進入下一層
6. 在高壓樓層死亡時進入 Farm 復原路線，再挑戰失敗層

## 3. 操作與介面
### 3.1 快捷鍵
- `I`：裝備面板
- `K`：技能/寶石連結面板
- `C`：Crafting 面板
- `M`：模組面板
- `Z`：嘗試吸附拾取所有地上物
- `L`：切換掉落過濾器
- `-` / `=`：快速調整農層
- `N`：挑戰待重試失敗樓層
- `Esc` / `Pause`：暫停/關閉面板

### 3.2 HUD
- 顯示：樓層、HP、DPS、擊殺數、敵人數、背包數、狀態圖示
- 顯示掉落訊息 feed（合併同類項目）
- 顯示進度模式與目標（Push/Farm/Retry、剩餘死亡次數）
- 受擊紅框視覺提示

## 4. 系統設計（目前已完成）
### 4.1 戰鬥系統
- 玩家為自動戰鬥：
  - AI 狀態：`IDLE/ROAMING/CHASING/ATTACKING`
  - 攻擊優先：最近 / 最低血 / 菁英優先
  - 遠程可切換保持距離、風箏等移動風格
- 攻擊型態：
  - 近戰範圍攻擊（含錐形/環形）
  - 投射物（追蹤、穿透、連鎖、爆炸）
  - 特例技能：`flurry`、`arrow_rain`、`shadow_strike`
- 傷害模型：
  - 基礎攻擊 -> 元素轉換 -> 技能倍率/輔助倍率 -> 暴擊 -> 最終增傷
  - 防守端含防禦、抗性、閃避、格擋、格擋減傷
  - 支援穿透、破甲、抗性削減

### 4.2 異常狀態
- 四種狀態：`burn`、`freeze`、`shock`、`bleed`
- 邏輯：
  - Burn/Bleed：DOT
  - Freeze：凍結（停移動/攻擊）
  - Shock：提高承傷
- 套用機率由傷害元素比例 + 基礎機率 + 屬性加成決定

### 4.3 敵人與深淵樓層
- 樓層資料驅動：`data/abyss/floors.json`
- 生成機制：
  - 每層讀取敵人組合、數量、倍率
  - 漸進縮放（HP/ATK/數量/掉率/經驗）
  - Boss 層（每 10 層）固定目標為擊殺 Boss
- 菁英系統：
  - 詞綴如 swift/armored/rage/thorns/death_burst 等
  - 含強化外觀標記與行為效果
- 進度模式：
  - `PUSHING`：正常推層
  - `FARMING`：失敗後回農層回補
  - `RETRYING`：回挑戰失敗層
- 死亡規則：
  - 單層最多 3 命，超過後會觸發回退/重試流程

### 4.4 掉落與拾取
- 擊殺後可掉落：
  - 裝備（隨機部位、稀有度、詞綴）
  - 技能寶石 / 輔助寶石
  - 模組
  - Crafting 材料（alter/augment/refine）
- 掉落物功能：
  - 浮動待撿、磁吸撿取、延遲可撿
  - 掉落過濾器（All / Magic+ / Rare / Gems+Modules）
  - 稀有度光柱與圖示表現

### 4.5 裝備系統
- 部位：
  - 主手、副手、頭、身、手、腳、腰、項鍊、雙戒指
- 稀有度：
  - 白 / 藍 / 黃（橙類型枚舉已預留）
- Affix 系統：
  - Prefix / Suffix 分池
  - tier + 權重抽取
  - 群組互斥（避免同群重複）
  - iLvl 100 特殊詞綴保底機制
- 面板功能：
  - 裝備/背包互換
  - 比較新舊裝備屬性差值
  - Tooltip 與統計摘要

### 4.6 寶石系統（Skill + Support Link）
- 技能寶石（Skill Gem）：
  - 決定攻擊主型態、武器限制、標籤、基礎參數
- 輔助寶石（Support Gem）：
  - 對技能提供 modifier（投射數、連鎖、範圍、速度、異常機率等）
  - 支援標籤相容性檢查
- Link 規則：
  - 1 主技能 + 多輔助（上限 5 格）
  - 不允許同 ID 輔助重複
- 背包與拖曳：
  - 技能/輔助背包各自容量
  - 支援槽位與背包互拖交換
- 進階：
  - 同 ID 同等級寶石可合成升級（至等級上限）

### 4.7 Crafting 系統
- 材料：
  - `alter`：重骰一條詞綴數值
  - `augment`：新增一條詞綴（未滿上限）
  - `refine`：提升一條詞綴朝 tier 上限前進
- 面板功能：
  - 選取背包裝備
  - 顯示材料數量與可否使用
  - 操作後即時刷新裝備詞綴結果

### 4.8 模組系統（Core Board）
- Core Board：
  - 8 格槽位
  - Load 容量上限 100
  - 不可裝重複 module id
- 模組分類：
  - Attack / Defense / Utility / Special
- 模組效果：
  - 透過 `StatModifier` 直接套用到玩家 `StatContainer`
- 面板功能：
  - 板上與背包互換
  - 即時顯示當前 Load 使用量與數值摘要

### 4.9 里程碑獎勵
- 每 20 層起，每 10 層觸發一次里程碑獎勵
- 以三選一寶石獎勵介面選擇，未選到會 fallback 掉地
- 同樓層里程碑只可領取一次

### 4.10 場次統計與掉落過濾
- Session Stats：擊殺、總傷害、掉落數、遊玩時間、死亡數
- 即時計算近 5 秒 DPS 並顯示於 HUD
- 掉落過濾模式可循環切換，會即時影響地上物顯示

## 5. 內容資料盤點（Data Driven）
### 5.1 技能寶石（10）
- `slash`, `whirlwind`, `stab`, `flurry`, `shadow_strike`
- `shoot`, `arrow_rain`, `piercing_shot`
- `magic_bolt`, `destruction_orb`

### 5.2 輔助寶石（15）
- `split`, `chain`, `pierce`, `area_expand`, `concentrate`
- `faster_casting`, `damage_amp`
- `added_fire`, `added_ice`, `added_lightning`, `added_bleed`
- `life_leech`, `knockback`, `multistrike`, `charge`

### 5.3 敵人（7）
- `slime`, `skeleton`, `fire_imp`, `ice_elemental`, `lightning_wisp`, `golem`, `abyss_watcher`

### 5.4 Crafting 材料（3）
- `alter`, `augment`, `refine`

### 5.5 模組（20）
- Attack：暴率/暴傷/攻速/元素增傷等
- Defense：格擋/閃避/生命/吸血/回復
- Utility：掉落率/掉落品質
- Special：四類異常機率強化

### 5.6 裝備基底（32）
- 武器/副手：11
- 防具：11
- 飾品：10

### 5.7 樓層錨點設定
- `default`, `1`, `5`, `10`, `15`, `20`, `25`

## 6. 技術架構
### 6.1 專案分層
- `scripts/autoload`
  - `EventBus`：全域事件中心
  - `DataManager`：載入所有 JSON 資料並提供 Factory/查詢
  - `GameManager`：遊戲狀態、統計、DPS、掉落過濾
  - `SaveManager`：存檔框架
- `scripts/main`
  - `Game`：主流程協調（場景管理、樓層循環、面板開關、掉落）
- `scripts/entities`
  - `Player`, `PlayerAI`, `EnemyBase`, `Projectile`
- `scripts/core`
  - `stats`, `equipment`, `gems`, `modules`, `status`, `crafting`, `loot`
- `scripts/ui`
  - `HUD`, `EquipmentPanel`, `SkillLinkPanel`, `CraftingPanel`, `ModulePanel`, `FloorRewardPanel`

### 6.2 事件驅動架構
- 主要訊號流：
  - 受傷/擊殺/死亡 -> `EventBus` -> HUD/流程/統計更新
  - 撿物/裝備變更/寶石升級 -> `EventBus` -> UI 即時反映
  - 樓層進入/完成/失敗 -> `GameManager` + `Game`

### 6.3 資料驅動架構
- 裝備、詞綴、敵人、樓層、寶石、模組、材料均由 `data/*.json` 驅動
- `DataManager` 在 `_ready()` 一次載入，提供 runtime factory（建立 Gem/Module）

## 7. 視覺與表現
- 目前以幾何/程式化視覺為主（placeholder 風格）
- 已有特效：
  - 近戰弧形/環形斬擊
  - 箭雨降落區域特效
  - 命中特效粒子
  - 傷害數字（元素色 + 暴擊放大）
  - 地面掉落光柱

## 8. 已完成度與未完成項目
### 8.1 已完成（可遊玩主循環）
- 從進場 -> 戰鬥 -> 掉落 -> 配裝 -> 推層 的完整可玩循環
- 四大 build 系統（裝備/寶石/Crafting/模組）全部可操作
- 深淵推層與失敗後 Farm/Retry 策略流程
- HUD 與多面板互通、導航、暫停狀態管理

### 8.2 明確未完成
- `SaveManager` 目前只完成基本 JSON 存讀框架
- 玩家完整資料（裝備、寶石、模組、材料、背包）尚未真正序列化與還原

## 9. 後續建議里程碑
### Milestone A（短期）
- 完成 Save/Load 完整資料落地
- 補齊 Boss 特殊技能行為（目前資料有 abilities，邏輯未完整展開）

### Milestone B（中期）
- 補更多樓層錨點與環境機制
- 新增更多技能/輔助互動，擴大 Build 空間

### Milestone C（中長期）
- 美術替換（角色、敵人、特效、UI skin）
- Meta progression（天賦樹、長線資源）
- 新模式（限時挑戰、詞綴賽季）

---

本文件為「目前程式碼實作狀態」的對齊版 GDD，可作為後續製作排程與任務拆分基準。
