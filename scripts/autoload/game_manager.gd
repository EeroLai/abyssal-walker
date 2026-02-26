extends Node

enum GameState {
	MENU,
	PLAYING,
	PAUSED,
	GAME_OVER,
}

enum LootFilterMode {
	ALL,
	MAGIC_PLUS,
	RARE_ONLY,
	GEMS_AND_MODULES,
}

const DPS_WINDOW_DURATION := 5.0
const RISK_PER_FLOOR_CLEAR: int = 10
const RISK_PER_ELITE_KILL: int = 8
const RISK_PER_BOSS_KILL: int = 20
const RISK_TIER_STEP: int = 25
const DEATH_MATERIAL_KEEP_RATIO: float = 0.65

var current_state: GameState = GameState.MENU
var current_floor: int = 1
var is_in_abyss: bool = false
var loot_filter_mode: LootFilterMode = LootFilterMode.ALL
var risk_score: int = 0
var extraction_interval: int = 3
var extraction_window_open: bool = false

var session_stats: Dictionary = {
	"kills": 0,
	"damage_dealt": 0,
	"damage_taken": 0,
	"items_picked": 0,
	"time_played": 0.0,
	"deaths": 0,
}

var idle_stats: Dictionary = {
	"kills_per_minute": 0.0,
	"damage_per_minute": 0.0,
	"drops_per_minute": 0.0,
	"current_dps": 0.0,
}

var _damage_window: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_signals()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("pause"):
			toggle_pause()
			get_viewport().set_input_as_handled()


func _connect_signals() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_died.connect(_on_player_died)
	EventBus.item_picked_up.connect(_on_item_picked_up)


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		session_stats.time_played += delta
		_update_dps()


func start_game() -> void:
	current_state = GameState.PLAYING
	is_in_abyss = true
	_reset_session_stats()
	reset_risk()


func pause_game() -> void:
	if current_state == GameState.PLAYING:
		current_state = GameState.PAUSED
		get_tree().paused = true
		EventBus.game_paused.emit()


func resume_game() -> void:
	if current_state == GameState.PAUSED:
		current_state = GameState.PLAYING
		get_tree().paused = false
		EventBus.game_resumed.emit()


func toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		pause_game()
	elif current_state == GameState.PAUSED:
		resume_game()


func enter_floor(floor_number: int) -> void:
	current_floor = floor_number
	EventBus.floor_entered.emit(floor_number)


func complete_floor() -> void:
	EventBus.floor_cleared.emit(current_floor)
	current_floor += 1


func fail_floor() -> void:
	EventBus.floor_failed.emit(current_floor)
	session_stats.deaths += 1


func reset_risk() -> void:
	risk_score = 0
	extraction_window_open = false
	EventBus.risk_score_changed.emit(risk_score, get_risk_tier())


func add_risk(amount: int) -> void:
	if amount <= 0:
		return
	risk_score += amount
	EventBus.risk_score_changed.emit(risk_score, get_risk_tier())


func add_floor_clear_risk() -> void:
	add_risk(RISK_PER_FLOOR_CLEAR)


func add_elite_kill_risk() -> void:
	add_risk(RISK_PER_ELITE_KILL)


func add_boss_kill_risk() -> void:
	add_risk(RISK_PER_BOSS_KILL)


func get_risk_tier() -> int:
	if risk_score <= 0:
		return 0
	return int(floor(float(risk_score) / float(RISK_TIER_STEP)))


func should_open_extraction_window(floor_number: int) -> bool:
	if floor_number <= 0:
		return false
	return floor_number % extraction_interval == 0


func open_extraction_window(floor_number: int, timeout_sec: float) -> void:
	extraction_window_open = true
	EventBus.extraction_window_opened.emit(floor_number, timeout_sec)


func close_extraction_window(floor_number: int, extracted: bool, player: Player = null) -> void:
	extraction_window_open = false
	EventBus.extraction_window_closed.emit(floor_number, extracted)
	if extracted:
		EventBus.run_extracted.emit({
			"floor": floor_number,
			"risk": risk_score,
			"tier": get_risk_tier(),
			"materials_carried": _get_material_total(player),
		})


func apply_death_material_penalty(player: Player) -> Dictionary:
	if player == null:
		return {"kept": 0, "lost": 0}
	var kept_total: int = 0
	var lost_total: int = 0
	for material_id in player.materials.keys():
		var id: String = str(material_id)
		var current: int = player.get_material_count(id)
		if current <= 0:
			continue
		var kept: int = int(floor(float(current) * DEATH_MATERIAL_KEEP_RATIO))
		var lost: int = maxi(0, current - kept)
		player.materials[id] = kept
		kept_total += kept
		lost_total += lost
	var summary := {
		"kept": kept_total,
		"lost": lost_total,
		"keep_ratio": DEATH_MATERIAL_KEEP_RATIO,
		"tier": get_risk_tier(),
		"risk": risk_score,
	}
	EventBus.run_failed.emit(summary)
	return summary


func _get_material_total(player: Player) -> int:
	if player == null:
		return 0
	var total: int = 0
	for material_id in player.materials.keys():
		total += player.get_material_count(str(material_id))
	return total


func resume_playing() -> void:
	current_state = GameState.PLAYING


func get_current_dps() -> float:
	return idle_stats.current_dps


func get_kills_per_minute() -> float:
	return idle_stats.kills_per_minute


func set_loot_filter_mode(mode: int) -> void:
	var clamped_mode: int = clampi(mode, LootFilterMode.ALL, LootFilterMode.GEMS_AND_MODULES)
	loot_filter_mode = clamped_mode
	EventBus.loot_filter_changed.emit(loot_filter_mode)


func cycle_loot_filter_mode() -> int:
	var next_mode := int(loot_filter_mode) + 1
	if next_mode > LootFilterMode.GEMS_AND_MODULES:
		next_mode = LootFilterMode.ALL
	set_loot_filter_mode(next_mode)
	return loot_filter_mode


func get_loot_filter_name() -> String:
	match loot_filter_mode:
		LootFilterMode.ALL:
			return "All"
		LootFilterMode.MAGIC_PLUS:
			return "Magic+"
		LootFilterMode.RARE_ONLY:
			return "Rare+"
		LootFilterMode.GEMS_AND_MODULES:
			return "Gems/Modules"
		_:
			return "All"


func should_show_loot(item: Variant) -> bool:
	match loot_filter_mode:
		LootFilterMode.ALL:
			return true
		LootFilterMode.MAGIC_PLUS:
			if item is EquipmentData:
				return item.rarity >= StatTypes.Rarity.BLUE
			return true
		LootFilterMode.RARE_ONLY:
			if item is EquipmentData:
				return item.rarity >= StatTypes.Rarity.YELLOW
			return true
		LootFilterMode.GEMS_AND_MODULES:
			return item is SkillGem or item is SupportGem or item is Module
		_:
			return true


func _reset_session_stats() -> void:
	session_stats = {
		"kills": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"items_picked": 0,
		"time_played": 0.0,
		"deaths": 0,
	}
	_damage_window.clear()


func _on_damage_dealt(_source: Node, _target: Node, damage_info: Dictionary) -> void:
	var damage: float = damage_info.get("final_damage", 0.0)
	session_stats.damage_dealt += damage
	_damage_window.append({
		"time": session_stats.time_played,
		"damage": damage,
	})


func _on_enemy_died(_enemy: Node, _position: Vector2) -> void:
	session_stats.kills += 1
	EventBus.kill_count_changed.emit(session_stats.kills)


func _on_player_died() -> void:
	fail_floor()


func _on_item_picked_up(_item_data) -> void:
	session_stats.items_picked += 1


func _update_dps() -> void:
	var current_time: float = session_stats.time_played
	var cutoff_time: float = current_time - DPS_WINDOW_DURATION
	_damage_window = _damage_window.filter(
		func(entry: Dictionary) -> bool: return float(entry.time) >= cutoff_time
	)

	var total_damage: float = 0.0
	for entry: Dictionary in _damage_window:
		total_damage += float(entry.damage)

	var window_duration: float = minf(DPS_WINDOW_DURATION, current_time)
	if window_duration > 0.0:
		idle_stats.current_dps = total_damage / window_duration
		EventBus.dps_updated.emit(idle_stats.current_dps)

	if session_stats.time_played > 0.0:
		var minutes: float = session_stats.time_played / 60.0
		idle_stats.kills_per_minute = session_stats.kills / minutes
		idle_stats.damage_per_minute = session_stats.damage_dealt / minutes
		idle_stats.drops_per_minute = session_stats.items_picked / minutes
