# Changelog

All notable changes to this project are documented in this file.
本檔案記錄此專案的重要更新內容。

This format is based on Keep a Changelog and uses simple sections:
格式參考 Keep a Changelog，並使用以下區塊：
- `Added`
- `Changed`
- `Fixed`
- `Balance`

## [Unreleased]

### Added

### Changed

### Fixed

### Balance

## [1.1.0] - 2026-02-24

Release notes: `docs/releases/v1.1.0.md`
版本說明：`docs/releases/v1.1.0.md`

### Added
- Skill tag support for `chain`, and a new beam skill: `Arc Lightning`.
- Enemy ranged attack flow with enemy projectile logic.
- Debug convenience: start with all skill gems and extra white-quality backup weapons.
- 新增 `chain` 技能標籤支援，並加入新技能 `Arc Lightning`（電弧）。
- 新增怪物遠程攻擊流程與敵方投射物邏輯。
- 新增測試便利功能：開局提供全技能與白裝備用武器。

### Changed
- Arc Lightning switched from projectile-style behavior to beam-style chain behavior.
- Core skill and support parsing/display paths updated for chain-related stats/tags.
- `Arc Lightning` 從投射物改為射線連鎖表現。
- 技能與輔助寶石的解析/顯示流程已支援連鎖相關詞條。

### Fixed
- Resolved invalid `take_damage` argument cases caused by previously freed projectile references.
- Type mismatch fixes around typed array return paths in player scripts.
- 修正投射物已釋放後仍傳入 `take_damage` 的無效參數問題。
- 修正玩家腳本中 typed array 回傳路徑型別不一致問題。

### Balance
- Dagger-related skills now attack faster.
- Shadow Tide single-hit performance tuned up.
- Damage variance changed to `+/-8%` with tunable constants preserved.
- Enemy elemental resistance pressure reduced to avoid nullifying elemental builds.
- 匕首相關技能攻速提高。
- 暗影潮汐單段技能的效率與傷害倍率提高。
- 傷害浮動改為 `+/-8%`，並保留可調常數。
- 降低敵方元素抗性壓力，避免元素流派傷害過低。

## [Archive]

When this file grows large:
1. Keep recent versions here (about 5-10 releases).
2. Move older entries to `docs/changelog/<year>.md`.
3. Leave one-line summaries here with links to archive files.
