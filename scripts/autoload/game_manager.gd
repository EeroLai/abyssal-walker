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

enum OperationType {
	NORMAL,
}

const DPS_WINDOW_DURATION := 5.0
const RISK_PER_FLOOR_CLEAR: int = 10
const RISK_PER_ELITE_KILL: int = 8
const RISK_PER_BOSS_KILL: int = 20
const RISK_TIER_STEP: int = 25
const DEFAULT_OPERATION_LIVES: int = 3
const STARTER_STASH_MATERIALS: Dictionary = {
	"alter": 40,
	"augment": 30,
	"refine": 20,
}

var current_state: GameState = GameState.MENU
var current_floor: int = 1
var is_in_abyss: bool = false
var loot_filter_mode: LootFilterMode = LootFilterMode.ALL
var risk_score: int = 0
var extraction_interval: int = 3
var extraction_window_open: bool = false
var stash_materials: Dictionary = {}
var stash_loot: Dictionary = {
	"equipment": [],
	"skill_gems": [],
	"support_gems": [],
	"modules": [],
}
var run_backpack_loot: Dictionary = {
	"equipment": [],
	"skill_gems": [],
	"support_gems": [],
	"modules": [],
}
var operation_loadout: Dictionary = {
	"equipment": [],
	"skill_gems": [],
	"support_gems": [],
	"modules": [],
}
var last_run_extracted_summary: Dictionary = {}
var last_run_failed_summary: Dictionary = {}
var operation_session: Dictionary = {
	"operation_level": 1,
	"operation_type": OperationType.NORMAL,
	"lives_max": DEFAULT_OPERATION_LIVES,
	"lives_left": DEFAULT_OPERATION_LIVES,
	"danger": 0,
}

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
	_ensure_starter_stash()


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
	if get_lives_left() <= 0:
		reset_operation()


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
	add_danger(1)
	operation_session.operation_level = maxi(int(operation_session.operation_level), current_floor + 1)
	_emit_operation_session_changed()
	current_floor += 1


func fail_floor() -> void:
	EventBus.floor_failed.emit(current_floor)
	session_stats.deaths += 1


func reset_risk() -> void:
	risk_score = 0
	extraction_window_open = false
	EventBus.risk_score_changed.emit(risk_score, get_risk_tier())


func start_operation(
	operation_level: int = 1,
	operation_type: int = OperationType.NORMAL,
	lives: int = DEFAULT_OPERATION_LIVES
) -> void:
	operation_session = {
		"operation_level": maxi(1, operation_level),
		"operation_type": operation_type,
		"lives_max": maxi(1, lives),
		"lives_left": maxi(1, lives),
		"danger": 0,
	}
	clear_run_backpack_loot()
	_emit_operation_session_changed()


func reset_operation() -> void:
	start_operation(1, OperationType.NORMAL, DEFAULT_OPERATION_LIVES)


func get_operation_level() -> int:
	return int(operation_session.get("operation_level", 1))


func get_operation_type() -> int:
	return int(operation_session.get("operation_type", OperationType.NORMAL))


func get_lives_max() -> int:
	return int(operation_session.get("lives_max", DEFAULT_OPERATION_LIVES))


func get_lives_left() -> int:
	return int(operation_session.get("lives_left", DEFAULT_OPERATION_LIVES))


func get_danger() -> int:
	return int(operation_session.get("danger", 0))


func add_danger(amount: int) -> void:
	if amount <= 0:
		return
	operation_session.danger = max(0, get_danger() + amount)
	_emit_operation_session_changed()


func consume_life() -> int:
	var left: int = maxi(0, get_lives_left() - 1)
	operation_session.lives_left = left
	_emit_operation_session_changed()
	return left


func restore_lives() -> void:
	operation_session.lives_left = get_lives_max()
	_emit_operation_session_changed()


func get_effective_drop_level(fallback_floor: int) -> int:
	var floor_from_operation := get_operation_level() + get_danger()
	return clampi(maxi(fallback_floor, floor_from_operation), 1, 100)


func get_operation_summary() -> Dictionary:
	return operation_session.duplicate(true)


func _emit_operation_session_changed() -> void:
	EventBus.operation_session_changed.emit(get_operation_summary())


func _ensure_starter_stash() -> void:
	if not stash_materials.is_empty():
		return
	for material_id in STARTER_STASH_MATERIALS.keys():
		var id: String = str(material_id)
		var amount: int = int(STARTER_STASH_MATERIALS[id])
		if amount > 0:
			stash_materials[id] = amount


func add_risk(amount: int) -> void:
	if amount <= 0:
		return
	risk_score += amount
	EventBus.risk_score_changed.emit(risk_score, get_risk_tier())


func add_floor_clear_risk() -> void:
	add_risk(RISK_PER_FLOOR_CLEAR)


func add_elite_kill_risk() -> void:
	add_risk(RISK_PER_ELITE_KILL)
	add_danger(1)


func add_boss_kill_risk() -> void:
	add_risk(RISK_PER_BOSS_KILL)
	add_danger(2)


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
		var moved_loot := deposit_run_backpack_loot_to_stash()
		last_run_extracted_summary = {
			"floor": floor_number,
			"risk": risk_score,
			"tier": get_risk_tier(),
			"materials_carried": 0,
			"stash_total": get_stash_material_total(),
			"loot_moved": moved_loot,
			"stash_loot": get_stash_loot_counts(),
		}
		EventBus.run_extracted.emit(last_run_extracted_summary.duplicate(true))


func apply_death_material_penalty(player: Player) -> Dictionary:
	if player == null:
		return {"kept": 0, "lost": 0}
	var kept_total: int = _get_material_total(player)
	var lost_loot := lose_run_backpack_loot()
	var summary := {
		"kept": kept_total,
		"lost": 0,
		"tier": get_risk_tier(),
		"risk": risk_score,
		"stash_total": get_stash_material_total(),
		"loot_lost": lost_loot,
	}
	last_run_failed_summary = summary.duplicate(true)
	EventBus.run_failed.emit(summary)
	return summary


func _get_material_total(player: Player) -> int:
	if player == null:
		return 0
	var total: int = 0
	for material_id in player.materials.keys():
		total += player.get_material_count(str(material_id))
	return total


func clear_run_backpack_loot() -> void:
	run_backpack_loot = {
		"equipment": [],
		"skill_gems": [],
		"support_gems": [],
		"modules": [],
	}


func clear_operation_loadout() -> void:
	operation_loadout = {
		"equipment": [],
		"skill_gems": [],
		"support_gems": [],
		"modules": [],
	}


func add_loot_to_run_backpack(item: Variant) -> void:
	if item is EquipmentData:
		run_backpack_loot.equipment.append((item as EquipmentData).duplicate(true))
	elif item is SkillGem:
		run_backpack_loot.skill_gems.append((item as SkillGem).duplicate(true))
	elif item is SupportGem:
		run_backpack_loot.support_gems.append((item as SupportGem).duplicate(true))
	elif item is Module:
		run_backpack_loot.modules.append((item as Module).duplicate(true))


func get_run_backpack_loot_counts() -> Dictionary:
	return {
		"equipment": int(run_backpack_loot.equipment.size()),
		"skill_gems": int(run_backpack_loot.skill_gems.size()),
		"support_gems": int(run_backpack_loot.support_gems.size()),
		"modules": int(run_backpack_loot.modules.size()),
		"total_gems": int(run_backpack_loot.skill_gems.size() + run_backpack_loot.support_gems.size()),
	}


func get_stash_loot_counts() -> Dictionary:
	return {
		"equipment": int(stash_loot.equipment.size()),
		"skill_gems": int(stash_loot.skill_gems.size()),
		"support_gems": int(stash_loot.support_gems.size()),
		"modules": int(stash_loot.modules.size()),
		"total_gems": int(stash_loot.skill_gems.size() + stash_loot.support_gems.size()),
	}


func get_operation_loadout_counts() -> Dictionary:
	return {
		"equipment": int(operation_loadout.equipment.size()),
		"skill_gems": int(operation_loadout.skill_gems.size()),
		"support_gems": int(operation_loadout.support_gems.size()),
		"modules": int(operation_loadout.modules.size()),
		"total_gems": int(operation_loadout.skill_gems.size() + operation_loadout.support_gems.size()),
	}


func get_stash_loot_snapshot() -> Dictionary:
	return {
		"equipment": stash_loot.equipment.duplicate(true),
		"skill_gems": stash_loot.skill_gems.duplicate(true),
		"support_gems": stash_loot.support_gems.duplicate(true),
		"modules": stash_loot.modules.duplicate(true),
	}


func get_operation_loadout_snapshot() -> Dictionary:
	return {
		"equipment": operation_loadout.equipment.duplicate(true),
		"skill_gems": operation_loadout.skill_gems.duplicate(true),
		"support_gems": operation_loadout.support_gems.duplicate(true),
		"modules": operation_loadout.modules.duplicate(true),
	}


func move_stash_loot_to_loadout(category: String, index: int) -> bool:
	if not stash_loot.has(category) or not operation_loadout.has(category):
		return false
	var source: Array = stash_loot[category]
	if index < 0 or index >= source.size():
		return false
	var item = source[index]
	source.remove_at(index)
	var target: Array = operation_loadout[category]
	target.append(item)
	return true


func move_loadout_loot_to_stash(category: String, index: int) -> bool:
	if not stash_loot.has(category) or not operation_loadout.has(category):
		return false
	var source: Array = operation_loadout[category]
	if index < 0 or index >= source.size():
		return false
	var item = source[index]
	source.remove_at(index)
	var target: Array = stash_loot[category]
	target.append(item)
	return true


func apply_operation_loadout_to_player(player: Player) -> void:
	if player == null:
		return
	for item in operation_loadout.equipment:
		var eq: EquipmentData = item
		if not player.add_to_inventory(eq):
			stash_loot.equipment.append(eq)
	for item in operation_loadout.skill_gems:
		var gem: SkillGem = item
		if not player.add_skill_gem_to_inventory(gem):
			stash_loot.skill_gems.append(gem)
	for item in operation_loadout.support_gems:
		var support: SupportGem = item
		if not player.add_support_gem_to_inventory(support):
			stash_loot.support_gems.append(support)
	for item in operation_loadout.modules:
		var mod: Module = item
		if not player.add_module_to_inventory(mod):
			stash_loot.modules.append(mod)
	clear_operation_loadout()


func deposit_run_backpack_loot_to_stash() -> Dictionary:
	var moved := get_run_backpack_loot_counts()
	stash_loot.equipment.append_array(run_backpack_loot.equipment)
	stash_loot.skill_gems.append_array(run_backpack_loot.skill_gems)
	stash_loot.support_gems.append_array(run_backpack_loot.support_gems)
	stash_loot.modules.append_array(run_backpack_loot.modules)
	clear_run_backpack_loot()
	return moved


func lose_run_backpack_loot() -> Dictionary:
	var lost := get_run_backpack_loot_counts()
	clear_run_backpack_loot()
	return lost


func get_last_run_extracted_summary() -> Dictionary:
	return last_run_extracted_summary.duplicate(true)


func get_last_run_failed_summary() -> Dictionary:
	return last_run_failed_summary.duplicate(true)


func sync_player_materials_from_stash(player: Player) -> void:
	if player == null:
		return
	player.materials.clear()
	for material_id in stash_materials.keys():
		var id: String = str(material_id)
		var count: int = int(stash_materials.get(id, 0))
		if count > 0:
			player.materials[id] = count


func set_stash_material_count(id: String, count: int) -> void:
	if id == "":
		return
	if count <= 0:
		stash_materials.erase(id)
		return
	stash_materials[id] = count


func get_stash_material_count(id: String) -> int:
	if id == "":
		return 0
	return int(stash_materials.get(id, 0))


func get_stash_materials_copy() -> Dictionary:
	return stash_materials.duplicate(true)


func get_stash_material_total() -> int:
	var total: int = 0
	for material_id in stash_materials.keys():
		total += int(stash_materials.get(str(material_id), 0))
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
