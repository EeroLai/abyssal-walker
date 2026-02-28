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
const DEFAULT_OPERATION_LIVES: int = 3
const DEFAULT_OPERATION_MAX_DEPTH: int = 25
const ABYSS_BEACON_DATA_SCRIPT := preload("res://scripts/abyss/abyss_beacon_data.gd")
const BEACON_MODIFIER_SYSTEM := preload("res://scripts/abyss/beacon_modifier_system.gd")
const STARTER_STASH_MATERIALS: Dictionary = {
	"alter": 40,
	"augment": 30,
	"refine": 20,
}

var current_state: GameState = GameState.MENU
var current_floor: int = 1
var is_in_abyss: bool = false
var loot_filter_mode: LootFilterMode = LootFilterMode.ALL
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
var operation_loot_ledger: Array[Dictionary] = []
var beacon_inventory: Array = []
var persistent_player_build: Dictionary = {}
var last_run_extracted_summary: Dictionary = {}
var last_run_failed_summary: Dictionary = {}
var operation_session: Dictionary = {
	"base_difficulty": 1,
	"operation_level": 1,
	"max_depth": DEFAULT_OPERATION_MAX_DEPTH,
	"operation_type": OperationType.NORMAL,
	"lives_max": DEFAULT_OPERATION_LIVES,
	"lives_left": DEFAULT_OPERATION_LIVES,
	"modifier_ids": PackedStringArray(),
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

const EQUIPMENT_SLOT_ORDER: Array[int] = [
	StatTypes.EquipmentSlot.MAIN_HAND,
	StatTypes.EquipmentSlot.OFF_HAND,
	StatTypes.EquipmentSlot.HELMET,
	StatTypes.EquipmentSlot.ARMOR,
	StatTypes.EquipmentSlot.GLOVES,
	StatTypes.EquipmentSlot.BOOTS,
	StatTypes.EquipmentSlot.BELT,
	StatTypes.EquipmentSlot.AMULET,
	StatTypes.EquipmentSlot.RING_1,
	StatTypes.EquipmentSlot.RING_2,
]
const LOOT_CATEGORY_EQUIPMENT := "equipment"
const LOOT_CATEGORY_SKILL_GEM := "skill_gem"
const LOOT_CATEGORY_SUPPORT_GEM := "support_gem"
const LOOT_CATEGORY_MODULE := "module"
const LOOT_ORIGIN_LOADOUT := "loadout"
const LOOT_ORIGIN_DISPLACED := "displaced"
const LOOT_STATE_INVENTORY := "inventory"
const LOOT_STATE_EQUIPPED := "equipped"
const LOOT_STATE_MISSING := "missing"


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
	EventBus.equipment_changed.connect(_on_equipment_changed)
	EventBus.skill_gem_changed.connect(_on_skill_gem_changed)
	EventBus.support_gem_changed.connect(_on_support_gem_changed)
	EventBus.module_changed.connect(_on_module_changed)


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		session_stats.time_played += delta
		_update_dps()


func start_game() -> void:
	current_state = GameState.PLAYING
	is_in_abyss = true
	_reset_session_stats()
	extraction_window_open = false
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
	current_floor += 1


func fail_floor() -> void:
	EventBus.floor_failed.emit(current_floor)
	session_stats.deaths += 1


func start_operation(
	base_difficulty: int = 1,
	operation_type: int = OperationType.NORMAL,
	lives: int = DEFAULT_OPERATION_LIVES,
	max_depth: int = DEFAULT_OPERATION_MAX_DEPTH,
	modifier_ids: PackedStringArray = PackedStringArray()
) -> void:
	operation_session = {
		"base_difficulty": maxi(1, base_difficulty),
		"operation_level": maxi(1, base_difficulty),
		"max_depth": maxi(1, max_depth),
		"operation_type": operation_type,
		"lives_max": maxi(1, lives),
		"lives_left": maxi(1, lives),
		"modifier_ids": modifier_ids.duplicate(),
		"danger": 0,
	}
	current_floor = 1
	clear_run_backpack_loot()
	clear_operation_loot_ledger()
	_emit_operation_session_changed()


func start_operation_from_beacon(
	beacon: Resource,
	operation_type: int = OperationType.NORMAL
) -> void:
	if beacon == null:
		start_operation(1, operation_type, DEFAULT_OPERATION_LIVES, DEFAULT_OPERATION_MAX_DEPTH)
		return
	var beacon_modifier_ids := PackedStringArray()
	var raw_modifier_ids: Variant = beacon.get("modifier_ids")
	if raw_modifier_ids is PackedStringArray:
		beacon_modifier_ids = raw_modifier_ids.duplicate()
	elif raw_modifier_ids is Array:
		for entry in raw_modifier_ids:
			beacon_modifier_ids.append(str(entry))
	start_operation(
		int(beacon.get("base_difficulty")),
		operation_type,
		int(beacon.get("lives_max")),
		int(beacon.get("max_depth")),
		beacon_modifier_ids
	)


func consume_beacon(index: int) -> Resource:
	if index < 0 or index >= beacon_inventory.size():
		return null
	var beacon: Variant = beacon_inventory[index]
	beacon_inventory.remove_at(index)
	_emit_beacon_inventory_changed()
	if beacon is Resource:
		return beacon
	return null


func activate_beacon(index: int, operation_type: int = OperationType.NORMAL) -> bool:
	var beacon := consume_beacon(index)
	if beacon == null:
		return false
	start_operation_from_beacon(beacon, operation_type)
	return true


func reset_operation() -> void:
	start_operation(1, OperationType.NORMAL, DEFAULT_OPERATION_LIVES, DEFAULT_OPERATION_MAX_DEPTH)


func get_base_difficulty() -> int:
	return int(operation_session.get("base_difficulty", operation_session.get("operation_level", 1)))


func get_operation_level() -> int:
	return get_base_difficulty()


func get_max_depth() -> int:
	return int(operation_session.get("max_depth", DEFAULT_OPERATION_MAX_DEPTH))


func get_operation_type() -> int:
	return int(operation_session.get("operation_type", OperationType.NORMAL))


func get_lives_max() -> int:
	return int(operation_session.get("lives_max", DEFAULT_OPERATION_LIVES))


func get_lives_left() -> int:
	return int(operation_session.get("lives_left", DEFAULT_OPERATION_LIVES))


func get_danger() -> int:
	return int(operation_session.get("danger", 0))


func get_modifier_ids() -> PackedStringArray:
	var value: Variant = operation_session.get("modifier_ids", PackedStringArray())
	if value is PackedStringArray:
		return value.duplicate()
	if value is Array:
		var ids := PackedStringArray()
		for entry in value:
			ids.append(str(entry))
		return ids
	return PackedStringArray()


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


func get_effective_drop_level(depth_index: int) -> int:
	var base_difficulty := get_base_difficulty()
	var depth := maxi(1, depth_index)
	return clampi(base_difficulty + depth - 1 + get_danger(), 1, 100)


func has_reached_max_depth(depth_index: int) -> bool:
	return maxi(1, depth_index) >= get_max_depth()


func get_operation_summary() -> Dictionary:
	var summary := operation_session.duplicate(true)
	summary["base_difficulty"] = get_base_difficulty()
	summary["operation_level"] = get_base_difficulty()
	summary["max_depth"] = get_max_depth()
	summary["modifier_ids"] = get_modifier_ids()
	return summary


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


func _create_beacon_from_config(config: Dictionary) -> Resource:
	var beacon: Resource = ABYSS_BEACON_DATA_SCRIPT.new()
	beacon.set("id", str(config.get("id", "")))
	beacon.set("display_name", str(config.get("display_name", "Abyss Beacon")))
	beacon.set("template_id", str(config.get("template_id", "balanced")))
	beacon.set("base_difficulty", maxi(1, int(config.get("base_difficulty", 1))))
	beacon.set("max_depth", maxi(1, int(config.get("max_depth", DEFAULT_OPERATION_MAX_DEPTH))))
	beacon.set("lives_max", maxi(1, int(config.get("lives_max", DEFAULT_OPERATION_LIVES))))
	var modifier_ids := PackedStringArray()
	var raw_modifier_ids: Variant = config.get("modifier_ids", PackedStringArray())
	if raw_modifier_ids is PackedStringArray:
		modifier_ids = raw_modifier_ids.duplicate()
	elif raw_modifier_ids is Array:
		for entry in raw_modifier_ids:
			modifier_ids.append(str(entry))
	beacon.set("modifier_ids", modifier_ids)
	return beacon


func get_beacon_inventory_count() -> int:
	return beacon_inventory.size()


func get_beacon_inventory_snapshot() -> Array:
	var snapshot: Array = []
	for beacon in beacon_inventory:
		if beacon is Resource:
			snapshot.append((beacon as Resource).duplicate(true))
	return snapshot


func get_beacon_snapshot(index: int) -> Resource:
	if index < 0 or index >= beacon_inventory.size():
		return null
	var beacon: Variant = beacon_inventory[index]
	if beacon is Resource:
		return (beacon as Resource).duplicate(true)
	return null


func update_beacon(index: int, beacon: Resource) -> bool:
	if beacon == null:
		return false
	if index < 0 or index >= beacon_inventory.size():
		return false
	beacon_inventory[index] = beacon.duplicate(true)
	_emit_beacon_inventory_changed()
	return true


func add_beacon(beacon: Resource) -> void:
	if beacon == null:
		return
	beacon_inventory.append(beacon.duplicate(true))
	_emit_beacon_inventory_changed()


func _emit_beacon_inventory_changed() -> void:
	EventBus.beacon_inventory_changed.emit(get_beacon_inventory_snapshot())


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
		_preserve_equipped_run_equipment(player)
		_strip_run_backpack_loot_from_player(player)
		var moved_loot := deposit_run_backpack_loot_to_stash()
		last_run_extracted_summary = {
			"floor": floor_number,
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
	_strip_run_backpack_loot_from_player(player)
	var lost_loot := lose_run_backpack_loot()
	var summary := {
		"kept": kept_total,
		"lost": 0,
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


func clear_operation_loot_ledger() -> void:
	operation_loot_ledger.clear()


func has_persistent_player_build() -> bool:
	return not persistent_player_build.is_empty()


func save_persistent_player_build_from_player(player: Player) -> void:
	if player == null:
		return
	if player.core_board == null or player.gem_link == null or player.stats == null:
		return
	persistent_player_build = _capture_player_build(player)


func apply_persistent_player_build_to_player(player: Player) -> void:
	if player == null:
		return
	if player.core_board == null or player.gem_link == null or player.stats == null:
		return
	if persistent_player_build.is_empty():
		return
	_apply_player_build_snapshot(player, persistent_player_build)


func get_persistent_player_build_snapshot() -> Dictionary:
	return persistent_player_build.duplicate(true)


func add_loot_to_run_backpack(item: Variant) -> void:
	if item is EquipmentData:
		run_backpack_loot.equipment.append(item)
	elif item is SkillGem:
		run_backpack_loot.skill_gems.append(item)
	elif item is SupportGem:
		run_backpack_loot.support_gems.append(item)
	elif item is Module:
		run_backpack_loot.modules.append(item)


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
		else:
			_track_operation_loot(eq, LOOT_CATEGORY_EQUIPMENT, LOOT_ORIGIN_LOADOUT, LOOT_STATE_INVENTORY)
	for item in operation_loadout.skill_gems:
		var gem: SkillGem = item
		if not player.add_skill_gem_to_inventory(gem):
			stash_loot.skill_gems.append(gem)
		else:
			_track_operation_loot(gem, LOOT_CATEGORY_SKILL_GEM, LOOT_ORIGIN_LOADOUT, LOOT_STATE_INVENTORY)
	for item in operation_loadout.support_gems:
		var support: SupportGem = item
		if not player.add_support_gem_to_inventory(support):
			stash_loot.support_gems.append(support)
		else:
			_track_operation_loot(support, LOOT_CATEGORY_SUPPORT_GEM, LOOT_ORIGIN_LOADOUT, LOOT_STATE_INVENTORY)
	for item in operation_loadout.modules:
		var mod: Module = item
		if not player.add_module_to_inventory(mod):
			stash_loot.modules.append(mod)
		else:
			_track_operation_loot(mod, LOOT_CATEGORY_MODULE, LOOT_ORIGIN_LOADOUT, LOOT_STATE_INVENTORY)
	clear_operation_loadout()


func _track_operation_loot(item: Variant, category: String, origin: String, state: String) -> void:
	if item == null:
		return
	var idx := _find_operation_loot_record(item, category)
	if idx >= 0:
		var existing: Dictionary = operation_loot_ledger[idx]
		existing["origin"] = origin
		existing["state"] = state
		operation_loot_ledger[idx] = existing
		return
	operation_loot_ledger.append({
		"item": item,
		"category": category,
		"origin": origin,
		"state": state,
	})


func _find_operation_loot_record(item: Variant, category: String) -> int:
	if item == null:
		return -1
	for i in range(operation_loot_ledger.size()):
		var rec: Dictionary = operation_loot_ledger[i]
		if str(rec.get("category", "")) == category and rec.get("item", null) == item:
			return i
	return -1


func _sync_operation_loot_states(player: Player) -> void:
	if player == null:
		return
	for i in range(operation_loot_ledger.size()):
		var rec: Dictionary = operation_loot_ledger[i]
		var item: Variant = rec.get("item", null)
		var category: String = str(rec.get("category", ""))
		if category == "":
			continue
		rec["state"] = _get_operation_loot_state(player, item, category)
		operation_loot_ledger[i] = rec


func _get_operation_loot_state(player: Player, item: Variant, category: String) -> String:
	if player == null or item == null:
		return LOOT_STATE_MISSING
	match category:
		LOOT_CATEGORY_EQUIPMENT:
			if item is EquipmentData:
				if _is_equipment_currently_equipped_by_player(player, item as EquipmentData):
					return LOOT_STATE_EQUIPPED
				if _is_equipment_in_player_inventory(player, item as EquipmentData):
					return LOOT_STATE_INVENTORY
		LOOT_CATEGORY_SKILL_GEM:
			if item is SkillGem:
				if _is_skill_gem_equipped_by_player(player, item as SkillGem):
					return LOOT_STATE_EQUIPPED
				if _is_skill_gem_in_player_inventory(player, item as SkillGem):
					return LOOT_STATE_INVENTORY
		LOOT_CATEGORY_SUPPORT_GEM:
			if item is SupportGem:
				if _is_support_gem_equipped_by_player(player, item as SupportGem):
					return LOOT_STATE_EQUIPPED
				if _is_support_gem_in_player_inventory(player, item as SupportGem):
					return LOOT_STATE_INVENTORY
		LOOT_CATEGORY_MODULE:
			if item is Module:
				if _is_module_equipped_by_player(player, item as Module):
					return LOOT_STATE_EQUIPPED
				if _is_module_in_player_inventory(player, item as Module):
					return LOOT_STATE_INVENTORY
	return LOOT_STATE_MISSING


func _is_equipment_in_player_inventory(player: Player, item: EquipmentData) -> bool:
	if player == null or item == null:
		return false
	for inv_item in player.inventory:
		if inv_item == item:
			return true
	return false


func _is_skill_gem_equipped_by_player(player: Player, item: SkillGem) -> bool:
	if player == null or item == null:
		return false
	return player.gem_link != null and player.gem_link.skill_gem == item


func _is_skill_gem_in_player_inventory(player: Player, item: SkillGem) -> bool:
	if player == null or item == null:
		return false
	for gem in player.skill_gem_inventory:
		if gem == item:
			return true
	return false


func _is_support_gem_equipped_by_player(player: Player, item: SupportGem) -> bool:
	if player == null or item == null:
		return false
	if player.gem_link == null:
		return false
	for gem in player.gem_link.support_gems:
		if gem == item:
			return true
	return false


func _is_support_gem_in_player_inventory(player: Player, item: SupportGem) -> bool:
	if player == null or item == null:
		return false
	for gem in player.support_gem_inventory:
		if gem == item:
			return true
	return false


func _is_module_equipped_by_player(player: Player, item: Module) -> bool:
	if player == null or item == null:
		return false
	if player.core_board == null:
		return false
	for mod in player.core_board.slots:
		if mod == item:
			return true
	return false


func _is_module_in_player_inventory(player: Player, item: Module) -> bool:
	if player == null or item == null:
		return false
	for mod in player.module_inventory:
		if mod == item:
			return true
	return false


func _is_run_backpack_loot(item: Variant, category: String) -> bool:
	if item == null:
		return false
	match category:
		LOOT_CATEGORY_EQUIPMENT:
			for eq in run_backpack_loot.equipment:
				if eq == item:
					return true
		LOOT_CATEGORY_SKILL_GEM:
			for gem in run_backpack_loot.skill_gems:
				if gem == item:
					return true
		LOOT_CATEGORY_SUPPORT_GEM:
			for gem in run_backpack_loot.support_gems:
				if gem == item:
					return true
		LOOT_CATEGORY_MODULE:
			for mod in run_backpack_loot.modules:
				if mod == item:
					return true
	return false


func _capture_player_build(player: Player) -> Dictionary:
	var equipped_map: Dictionary = {}
	for slot_key: Variant in player.equipment.keys():
		var slot_id: int = int(slot_key)
		var equipped_item: EquipmentData = player.equipment.get(slot_key) as EquipmentData
		if equipped_item != null:
			equipped_map[slot_id] = equipped_item.duplicate(true)

	var equipped_skill_gem: SkillGem = null
	if player.gem_link != null and player.gem_link.skill_gem != null:
		equipped_skill_gem = player.gem_link.skill_gem.duplicate(true)

	var equipped_supports: Array = []
	if player.gem_link != null:
		equipped_supports = _clone_resource_array(player.gem_link.support_gems)

	return {
		"equipment": equipped_map,
		"inventory": _clone_resource_array(player.inventory),
		"skill_gem_inventory": _clone_resource_array(player.skill_gem_inventory),
		"support_gem_inventory": _clone_resource_array(player.support_gem_inventory),
		"equipped_skill_gem": equipped_skill_gem,
		"equipped_support_gems": equipped_supports,
		"module_inventory": _clone_resource_array(player.module_inventory),
		"equipped_modules": _clone_resource_array(player.core_board.slots),
	}


func _apply_player_build_snapshot(player: Player, snapshot: Dictionary) -> void:
	_clear_player_build(player)

	var equipped_map: Dictionary = snapshot.get("equipment", {})
	for slot_id in EQUIPMENT_SLOT_ORDER:
		var item_data: Variant = equipped_map.get(slot_id, null)
		if item_data is EquipmentData:
			var equipped_item: EquipmentData = (item_data as EquipmentData).duplicate(true)
			equipped_item.slot = slot_id
			player.equip(equipped_item)

	var inventory_items: Array = snapshot.get("inventory", [])
	for item_data: Variant in inventory_items:
		if item_data is EquipmentData:
			player.add_to_inventory((item_data as EquipmentData).duplicate(true))

	var skill_inventory: Array = snapshot.get("skill_gem_inventory", [])
	for i in range(mini(skill_inventory.size(), Constants.MAX_SKILL_GEM_INVENTORY)):
		var skill_item: Variant = skill_inventory[i]
		if skill_item is SkillGem:
			player.set_skill_gem_in_inventory(i, (skill_item as SkillGem).duplicate(true))

	var support_inventory: Array = snapshot.get("support_gem_inventory", [])
	for i in range(mini(support_inventory.size(), Constants.MAX_SUPPORT_GEM_INVENTORY)):
		var support_item: Variant = support_inventory[i]
		if support_item is SupportGem:
			player.set_support_gem_in_inventory(i, (support_item as SupportGem).duplicate(true))

	var equipped_skill: Variant = snapshot.get("equipped_skill_gem", null)
	if equipped_skill is SkillGem and player.gem_link != null:
		player.gem_link.set_skill_gem((equipped_skill as SkillGem).duplicate(true))

	var equipped_supports: Array = snapshot.get("equipped_support_gems", [])
	if player.gem_link != null:
		for i in range(mini(equipped_supports.size(), Constants.MAX_SUPPORT_GEMS)):
			var support_data: Variant = equipped_supports[i]
			if support_data is SupportGem:
				player.gem_link.set_support_gem(i, (support_data as SupportGem).duplicate(true))

	var equipped_modules: Array = snapshot.get("equipped_modules", [])
	for module_data: Variant in equipped_modules:
		if module_data is Module:
			var mod: Module = (module_data as Module).duplicate_module()
			if not player.core_board.equip(mod, player.stats):
				player.add_module_to_inventory(mod)

	var module_inventory: Array = snapshot.get("module_inventory", [])
	for module_data: Variant in module_inventory:
		if module_data is Module:
			player.add_module_to_inventory((module_data as Module).duplicate_module())

	player.current_hp = player.stats.get_stat(StatTypes.Stat.HP)
	player.call("_emit_health_changed")


func _clear_player_build(player: Player) -> void:
	for slot_id in EQUIPMENT_SLOT_ORDER:
		player.unequip(slot_id)
	player.inventory.clear()
	player.skill_gem_inventory.clear()
	player.support_gem_inventory.clear()
	if player.gem_link != null:
		player.gem_link.set_skill_gem(null)
		player.gem_link.support_gems.clear()
	if player.core_board != null:
		while player.core_board.slots.size() > 0:
			player.core_board.unequip_at(0, player.stats)
	player.module_inventory.clear()


func _clone_resource_array(source: Array) -> Array:
	var cloned: Array = []
	for value: Variant in source:
		if value == null:
			cloned.append(null)
		elif value is Module:
			cloned.append((value as Module).duplicate_module())
		elif value is Resource:
			cloned.append((value as Resource).duplicate(true))
		else:
			cloned.append(value)
	return cloned


func deposit_run_backpack_loot_to_stash() -> Dictionary:
	var moved := get_run_backpack_loot_counts()
	for item in run_backpack_loot.equipment:
		if item is EquipmentData:
			stash_loot.equipment.append((item as EquipmentData).duplicate(true))
	for item in run_backpack_loot.skill_gems:
		if item is SkillGem:
			stash_loot.skill_gems.append((item as SkillGem).duplicate(true))
	for item in run_backpack_loot.support_gems:
		if item is SupportGem:
			stash_loot.support_gems.append((item as SupportGem).duplicate(true))
	for item in run_backpack_loot.modules:
		if item is Module:
			stash_loot.modules.append((item as Module).duplicate_module())
	clear_run_backpack_loot()
	return moved


func lose_run_backpack_loot() -> Dictionary:
	var lost := get_run_backpack_loot_counts()
	clear_run_backpack_loot()
	return lost


func resolve_operation_loadout_for_lobby(player: Player) -> void:
	if player == null:
		return
	_sync_operation_loot_states(player)

	for rec in operation_loot_ledger:
		var item: Variant = rec.get("item", null)
		var category: String = str(rec.get("category", ""))
		if category == "":
			continue
		var state: String = str(rec.get("state", LOOT_STATE_MISSING))
		if state != LOOT_STATE_INVENTORY:
			continue
		_remove_operation_loot_ref_from_player(player, item, category)
		_stash_operation_loot_copy(item, category)

	clear_operation_loot_ledger()

	if player.stats != null:
		player.current_hp = minf(player.current_hp, player.stats.get_stat(StatTypes.Stat.HP))
		player.call("_emit_health_changed")


func resolve_operation_equipment_for_lobby(player: Player) -> void:
	resolve_operation_loadout_for_lobby(player)


func _remove_operation_loot_ref_from_player(player: Player, item: Variant, category: String) -> void:
	match category:
		LOOT_CATEGORY_EQUIPMENT:
			if item is EquipmentData:
				_remove_equipment_ref_from_player(player, item as EquipmentData)
		LOOT_CATEGORY_SKILL_GEM:
			if item is SkillGem:
				_remove_skill_gem_ref_from_player(player, item as SkillGem)
		LOOT_CATEGORY_SUPPORT_GEM:
			if item is SupportGem:
				_remove_support_gem_ref_from_player(player, item as SupportGem)
		LOOT_CATEGORY_MODULE:
			if item is Module:
				_remove_module_ref_from_player(player, item as Module)


func _stash_operation_loot_copy(item: Variant, category: String) -> void:
	match category:
		LOOT_CATEGORY_EQUIPMENT:
			if item is EquipmentData:
				stash_loot.equipment.append((item as EquipmentData).duplicate(true))
		LOOT_CATEGORY_SKILL_GEM:
			if item is SkillGem:
				stash_loot.skill_gems.append((item as SkillGem).duplicate(true))
		LOOT_CATEGORY_SUPPORT_GEM:
			if item is SupportGem:
				stash_loot.support_gems.append((item as SupportGem).duplicate(true))
		LOOT_CATEGORY_MODULE:
			if item is Module:
				stash_loot.modules.append((item as Module).duplicate_module())


func _preserve_equipped_run_equipment(player: Player) -> void:
	if player == null:
		return
	for i in range(run_backpack_loot.equipment.size() - 1, -1, -1):
		var item: Variant = run_backpack_loot.equipment[i]
		if item is EquipmentData and _is_equipment_currently_equipped_by_player(player, item as EquipmentData):
			run_backpack_loot.equipment.remove_at(i)


func _is_equipment_currently_equipped_by_player(player: Player, item: EquipmentData) -> bool:
	if player == null or item == null:
		return false
	for slot_id in EQUIPMENT_SLOT_ORDER:
		if player.get_equipped(slot_id) == item:
			return true
	return false


func _strip_run_backpack_loot_from_player(player: Player) -> void:
	if player == null:
		return

	for item in run_backpack_loot.equipment:
		if item is EquipmentData:
			_remove_equipment_ref_from_player(player, item as EquipmentData)
	for item in run_backpack_loot.skill_gems:
		if item is SkillGem:
			_remove_skill_gem_ref_from_player(player, item as SkillGem)
	for item in run_backpack_loot.support_gems:
		if item is SupportGem:
			_remove_support_gem_ref_from_player(player, item as SupportGem)
	for item in run_backpack_loot.modules:
		if item is Module:
			_remove_module_ref_from_player(player, item as Module)

	if player.stats != null:
		player.current_hp = minf(player.current_hp, player.stats.get_stat(StatTypes.Stat.HP))
		player.call("_emit_health_changed")


func _remove_equipment_ref_from_player(player: Player, target: EquipmentData) -> void:
	if target == null:
		return
	for i in range(player.inventory.size() - 1, -1, -1):
		if player.inventory[i] == target:
			player.inventory.remove_at(i)
			return
	for slot_id in EQUIPMENT_SLOT_ORDER:
		if player.get_equipped(slot_id) == target:
			player.unequip(slot_id)
			return


func _remove_skill_gem_ref_from_player(player: Player, target: SkillGem) -> void:
	if target == null:
		return
	if player.gem_link != null and player.gem_link.skill_gem == target:
		player.gem_link.set_skill_gem(null)
		return
	for i in range(player.skill_gem_inventory.size() - 1, -1, -1):
		if player.get_skill_gem_in_inventory(i) == target:
			player.remove_skill_gem_from_inventory(i)
			return


func _remove_support_gem_ref_from_player(player: Player, target: SupportGem) -> void:
	if target == null:
		return
	if player.gem_link != null:
		for i in range(player.gem_link.support_gems.size()):
			if player.gem_link.support_gems[i] == target:
				player.gem_link.set_support_gem(i, null)
				return
	for i in range(player.support_gem_inventory.size() - 1, -1, -1):
		if player.get_support_gem_in_inventory(i) == target:
			player.remove_support_gem_from_inventory(i)
			return


func _remove_module_ref_from_player(player: Player, target: Module) -> void:
	if target == null:
		return
	for i in range(player.module_inventory.size() - 1, -1, -1):
		if player.module_inventory[i] == target:
			player.remove_module_from_inventory(i)
			return
	if player.core_board != null and player.stats != null:
		for i in range(player.core_board.slots.size() - 1, -1, -1):
			if player.core_board.slots[i] == target:
				player.core_board.unequip_at(i, player.stats)
				return


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
	get_tree().paused = false


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
	var enemy_base := _enemy as EnemyBase
	if enemy_base == null:
		return
	var gained_beacons: Array[Resource] = []
	var beacon := DropSystem.roll_beacon_drop_for_floor(current_floor, enemy_base)
	if beacon != null:
		gained_beacons.append(beacon)
	if enemy_base.is_boss:
		var summary := BEACON_MODIFIER_SYSTEM.summarize(get_modifier_ids())
		var extra_boss_beacons := maxi(0, int(summary.get("boss_bonus_beacons", 0)))
		for i in range(extra_boss_beacons):
			var extra_beacon := DropSystem.create_guaranteed_beacon_for_floor(current_floor, enemy_base)
			if extra_beacon != null:
				gained_beacons.append(extra_beacon)
	if gained_beacons.is_empty():
		return
	for gained in gained_beacons:
		add_beacon(gained)
	if gained_beacons.size() == 1:
		EventBus.notification_requested.emit("信標入庫：%s" % str(gained_beacons[0].get("display_name")), "beacon")
	else:
		EventBus.notification_requested.emit("信標入庫：%d" % gained_beacons.size(), "beacon")


func _on_player_died() -> void:
	fail_floor()


func _on_item_picked_up(_item_data) -> void:
	session_stats.items_picked += 1


func _on_equipment_changed(
	_slot: StatTypes.EquipmentSlot,
	old_item: EquipmentData,
	new_item: EquipmentData
) -> void:
	if not is_in_abyss:
		return
	_track_displaced_operation_loot(old_item, new_item, LOOT_CATEGORY_EQUIPMENT)


func _on_skill_gem_changed(old_gem: SkillGem, new_gem: SkillGem) -> void:
	if not is_in_abyss:
		return
	_track_displaced_operation_loot(old_gem, new_gem, LOOT_CATEGORY_SKILL_GEM)


func _on_support_gem_changed(_slot_index: int, old_gem: SupportGem, new_gem: SupportGem) -> void:
	if not is_in_abyss:
		return
	_track_displaced_operation_loot(old_gem, new_gem, LOOT_CATEGORY_SUPPORT_GEM)


func _on_module_changed(_slot_index: int, old_module: Module, new_module: Module) -> void:
	if not is_in_abyss:
		return
	_track_displaced_operation_loot(old_module, new_module, LOOT_CATEGORY_MODULE)


func _track_displaced_operation_loot(old_item: Variant, new_item: Variant, category: String) -> void:
	if old_item == null or new_item == null:
		return
	var new_is_tracked: bool = _find_operation_loot_record(new_item, category) >= 0
	var new_is_run_loot: bool = _is_run_backpack_loot(new_item, category)
	if not new_is_tracked and not new_is_run_loot:
		return
	if _find_operation_loot_record(old_item, category) >= 0:
		return
	if _is_run_backpack_loot(old_item, category):
		return
	_track_operation_loot(old_item, category, LOOT_ORIGIN_DISPLACED, LOOT_STATE_INVENTORY)


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
