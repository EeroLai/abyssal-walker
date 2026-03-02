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

const DEFAULT_OPERATION_LIVES: int = 3
const DEFAULT_OPERATION_MAX_DEPTH: int = 25
const BEACON_DROP_SERVICE := preload("res://scripts/core/run/beacon_drop_service.gd")
const LOOT_FILTER_SERVICE := preload("res://scripts/core/run/loot_filter_service.gd")
const OPERATION_INVENTORY_SERVICE := preload("res://scripts/core/run/operation_inventory_service.gd")
const RUN_COMMAND_SERVICE := preload("res://scripts/core/run/run_command_service.gd")
const RUN_QUERY_SERVICE := preload("res://scripts/core/run/run_query_service.gd")
const RUN_RUNTIME_SERVICE := preload("res://scripts/core/run/run_runtime_service.gd")
const RUN_FLOW_SERVICE := preload("res://scripts/core/run/run_flow_service.gd")
const RUN_RECORDS_SERVICE := preload("res://scripts/core/run/run_records_service.gd")
const RUN_SESSION_SERVICE := preload("res://scripts/core/run/run_session_service.gd")
const RUN_TELEMETRY_SERVICE := preload("res://scripts/core/run/run_telemetry_service.gd")
const STARTER_STASH_MATERIALS: Dictionary = {
	"alter": 40,
	"augment": 30,
	"refine": 20,
}

var _beacon_drop_service = BEACON_DROP_SERVICE.new()
var _loot_filter_service = LOOT_FILTER_SERVICE.new()
var _run_flow_service = RUN_FLOW_SERVICE.new(3)
var _inventory_service = OPERATION_INVENTORY_SERVICE.new()
var _run_records_service = RUN_RECORDS_SERVICE.new()
var _run_session_service = RUN_SESSION_SERVICE.new(
	DEFAULT_OPERATION_LIVES,
	DEFAULT_OPERATION_MAX_DEPTH,
	OperationType.NORMAL
)
var _telemetry_service = RUN_TELEMETRY_SERVICE.new()
var _runtime_service = RUN_RUNTIME_SERVICE.new(GameState.MENU)
var _command_service = RUN_COMMAND_SERVICE.new(
	_run_session_service,
	_run_flow_service,
	_inventory_service,
	_run_records_service,
	_telemetry_service,
	OperationType.NORMAL,
	DEFAULT_OPERATION_LIVES,
	DEFAULT_OPERATION_MAX_DEPTH
)
var _query_service = RUN_QUERY_SERVICE.new(
	_run_session_service,
	_run_flow_service,
	_inventory_service,
	_run_records_service,
	_telemetry_service,
	_loot_filter_service
)

const LOOT_CATEGORY_EQUIPMENT := "equipment"
const LOOT_CATEGORY_SKILL_GEM := "skill_gem"
const LOOT_CATEGORY_SUPPORT_GEM := "support_gem"
const LOOT_CATEGORY_MODULE := "module"


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
	if _runtime_service.current_state == GameState.PLAYING:
		EventBus.dps_updated.emit(_command_service.advance_telemetry(delta))


func start_game() -> void:
	_runtime_service.start_game(GameState.PLAYING)
	_command_service.reset_telemetry()
	_command_service.reset_run_flow()
	if get_lives_left() <= 0:
		reset_operation()


func pause_game() -> void:
	if not _runtime_service.pause_game(GameState.PLAYING, GameState.PAUSED):
		return
	get_tree().paused = true
	EventBus.game_paused.emit()


func resume_game() -> void:
	if not _runtime_service.resume_game(GameState.PAUSED, GameState.PLAYING):
		return
	get_tree().paused = false
	EventBus.game_resumed.emit()


func toggle_pause() -> void:
	if _runtime_service.current_state == GameState.PLAYING:
		pause_game()
	elif _runtime_service.current_state == GameState.PAUSED:
		resume_game()


func enter_floor(floor_number: int) -> void:
	_runtime_service.enter_floor(floor_number)
	EventBus.floor_entered.emit(floor_number)


func complete_floor() -> void:
	var cleared_floor: int = _runtime_service.complete_floor()
	EventBus.floor_cleared.emit(cleared_floor)
	add_danger(1)


func fail_floor() -> void:
	EventBus.floor_failed.emit(_runtime_service.fail_floor())
	_command_service.record_death()


func start_operation(
	base_difficulty: int = 1,
	operation_type: int = OperationType.NORMAL,
	lives: int = DEFAULT_OPERATION_LIVES,
	max_depth: int = DEFAULT_OPERATION_MAX_DEPTH,
	modifier_ids: PackedStringArray = PackedStringArray()
) -> void:
	_command_service.start_operation(
		base_difficulty,
		operation_type,
		lives,
		max_depth,
		modifier_ids
	)
	_runtime_service.reset_for_operation()
	_emit_operation_session_changed()


func start_operation_from_beacon(
	beacon: Resource,
	operation_type: int = OperationType.NORMAL
) -> void:
	_command_service.start_operation_from_beacon(beacon, operation_type)
	_runtime_service.reset_for_operation()
	_emit_operation_session_changed()


func consume_beacon(index: int) -> Resource:
	var result: Dictionary = _command_service.consume_beacon(index)
	if bool(result.get("had_entry", false)):
		_emit_beacon_inventory_changed()
	return result.get("beacon", null) as Resource


func activate_beacon(index: int, operation_type: int = OperationType.NORMAL) -> bool:
	var beacon := consume_beacon(index)
	if beacon == null:
		return false
	start_operation_from_beacon(beacon, operation_type)
	return true


func reset_operation() -> void:
	_command_service.reset_operation()
	_runtime_service.reset_for_operation()
	_emit_operation_session_changed()


func get_base_difficulty() -> int:
	return _query_service.get_base_difficulty()


func get_operation_level() -> int:
	return _query_service.get_operation_level()


func get_max_depth() -> int:
	return _query_service.get_max_depth()


func get_operation_type() -> int:
	return _query_service.get_operation_type()


func get_lives_max() -> int:
	return _query_service.get_lives_max()


func get_lives_left() -> int:
	return _query_service.get_lives_left()


func get_danger() -> int:
	return _query_service.get_danger()


func get_modifier_ids() -> PackedStringArray:
	return _query_service.get_modifier_ids()


func add_danger(amount: int) -> void:
	if not _command_service.add_danger(amount):
		return
	_emit_operation_session_changed()


func consume_life() -> int:
	var left: int = _command_service.consume_life()
	_emit_operation_session_changed()
	return left


func restore_lives() -> void:
	_command_service.restore_lives()
	_emit_operation_session_changed()


func get_effective_drop_level(depth_index: int) -> int:
	return _query_service.get_effective_drop_level(depth_index)


func has_reached_max_depth(depth_index: int) -> bool:
	return _query_service.has_reached_max_depth(depth_index)


func get_operation_summary() -> Dictionary:
	return _query_service.get_operation_summary()


func _emit_operation_session_changed() -> void:
	EventBus.operation_session_changed.emit(get_operation_summary())


func _ensure_starter_stash() -> void:
	_command_service.ensure_starter_stash(STARTER_STASH_MATERIALS)

func get_beacon_inventory_count() -> int:
	return _query_service.get_beacon_inventory_count()


func get_beacon_inventory_snapshot() -> Array:
	return _query_service.get_beacon_inventory_snapshot()


func get_beacon_snapshot(index: int) -> Resource:
	return _query_service.get_beacon_snapshot(index)


func update_beacon(index: int, beacon: Resource) -> bool:
	if not _command_service.update_beacon(index, beacon):
		return false
	_emit_beacon_inventory_changed()
	return true


func add_beacon(beacon: Resource) -> void:
	if not _command_service.add_beacon(beacon):
		return
	_emit_beacon_inventory_changed()


func _emit_beacon_inventory_changed() -> void:
	EventBus.beacon_inventory_changed.emit(get_beacon_inventory_snapshot())


func should_open_extraction_window(floor_number: int) -> bool:
	return _query_service.should_open_extraction_window(floor_number)


func open_extraction_window(floor_number: int, timeout_sec: float) -> void:
	_command_service.open_extraction_window()
	EventBus.extraction_window_opened.emit(floor_number, timeout_sec)


func close_extraction_window(floor_number: int, extracted: bool, player: Player = null) -> void:
	var summary: Dictionary = _command_service.close_extraction_window(floor_number, extracted, player)
	EventBus.extraction_window_closed.emit(floor_number, extracted)
	if not summary.is_empty():
		EventBus.run_extracted.emit(summary)


func apply_death_material_penalty(player: Player) -> Dictionary:
	var summary: Dictionary = _command_service.apply_death_material_penalty(player)
	EventBus.run_failed.emit(summary)
	return summary


func clear_run_backpack_loot() -> void:
	_command_service.clear_run_backpack_loot()


func clear_operation_loadout() -> void:
	_command_service.clear_operation_loadout()


func clear_operation_loot_ledger() -> void:
	_command_service.clear_operation_loot_ledger()


func has_persistent_player_build() -> bool:
	return _query_service.has_persistent_player_build()


func save_persistent_player_build_from_player(player: Player) -> void:
	_command_service.save_persistent_player_build_from_player(player)


func save_persistent_player_build_snapshot(snapshot: Dictionary) -> void:
	_command_service.save_persistent_player_build_snapshot(snapshot)


func apply_persistent_player_build_to_player(player: Player) -> void:
	_command_service.apply_persistent_player_build_to_player(player)


func get_persistent_player_build_snapshot() -> Dictionary:
	return _query_service.get_persistent_player_build_snapshot()


func get_persistent_player_state() -> PlayerState:
	return _query_service.get_persistent_player_state()


func add_loot_to_run_backpack(item: Variant) -> void:
	_command_service.add_loot_to_run_backpack(item)


func get_run_backpack_loot_counts() -> Dictionary:
	return _query_service.get_run_backpack_loot_counts()


func get_stash_loot_counts() -> Dictionary:
	return _query_service.get_stash_loot_counts()


func get_operation_loadout_counts() -> Dictionary:
	return _query_service.get_operation_loadout_counts()


func get_stash_loot_snapshot() -> Dictionary:
	return _query_service.get_stash_loot_snapshot()


func get_operation_loadout_snapshot() -> Dictionary:
	return _query_service.get_operation_loadout_snapshot()


func move_stash_loot_to_loadout(category: String, index: int) -> bool:
	return _command_service.move_stash_loot_to_loadout(category, index)


func move_loadout_loot_to_stash(category: String, index: int) -> bool:
	return _command_service.move_loadout_loot_to_stash(category, index)


func take_stash_loot_item(category: String, index: int) -> Variant:
	return _command_service.take_stash_loot_item(category, index)


func add_loot_to_stash(item: Variant) -> bool:
	return _command_service.add_loot_to_stash(item)


func apply_operation_loadout_to_player(player: Player) -> void:
	_command_service.apply_operation_loadout_to_player(player)


func deposit_run_backpack_loot_to_stash() -> Dictionary:
	return _command_service.deposit_run_backpack_loot_to_stash()


func lose_run_backpack_loot() -> Dictionary:
	return _command_service.lose_run_backpack_loot()


func resolve_operation_loadout_for_lobby(player: Player) -> void:
	_command_service.resolve_operation_loadout_for_lobby(player)


func resolve_operation_equipment_for_lobby(player: Player) -> void:
	_command_service.resolve_operation_loadout_for_lobby(player)


func get_last_run_extracted_summary() -> Dictionary:
	return _query_service.get_last_run_extracted_summary()


func get_last_run_failed_summary() -> Dictionary:
	return _query_service.get_last_run_failed_summary()


func sync_player_materials_from_stash(player: Player) -> void:
	_command_service.sync_player_materials_from_stash(player)


func set_stash_material_count(id: String, count: int) -> void:
	_command_service.set_stash_material_count(id, count)


func get_stash_material_count(id: String) -> int:
	return _query_service.get_stash_material_count(id)


func get_stash_materials_copy() -> Dictionary:
	return _query_service.get_stash_materials_copy()


func get_stash_material_total() -> int:
	return _query_service.get_stash_material_total()


func resume_playing() -> void:
	_runtime_service.resume_playing(GameState.PLAYING)
	get_tree().paused = false


func get_current_dps() -> float:
	return _query_service.get_current_dps()


func get_kills_per_minute() -> float:
	return _query_service.get_kills_per_minute()


func set_loot_filter_mode(mode: int) -> void:
	var applied_mode: int = _loot_filter_service.set_mode(mode)
	EventBus.loot_filter_changed.emit(applied_mode)


func cycle_loot_filter_mode() -> int:
	var applied_mode: int = _loot_filter_service.cycle_mode()
	EventBus.loot_filter_changed.emit(applied_mode)
	return applied_mode


func get_loot_filter_name() -> String:
	return _query_service.get_loot_filter_name()


func should_show_loot(item: Variant) -> bool:
	return _query_service.should_show_loot(item)


func _on_damage_dealt(_source: Node, _target: Node, damage_info: Dictionary) -> void:
	_command_service.record_damage_dealt(damage_info)


func _on_enemy_died(_enemy: Node, _position: Vector2) -> void:
	var kills: int = _command_service.record_enemy_kill()
	EventBus.kill_count_changed.emit(kills)
	var enemy_base := _enemy as EnemyBase
	if enemy_base == null:
		return
	var gained_beacons: Array[Resource] = _beacon_drop_service.collect_beacon_drops(
		_runtime_service.current_floor,
		enemy_base,
		get_modifier_ids()
	)
	if gained_beacons.is_empty():
		return
	for gained in gained_beacons:
		add_beacon(gained)
	var notification: String = _beacon_drop_service.build_inventory_notification(gained_beacons)
	if not notification.is_empty():
		EventBus.notification_requested.emit(notification, "beacon")


func _on_player_died() -> void:
	fail_floor()


func _on_item_picked_up(_item_data) -> void:
	_command_service.record_item_picked_up()


func _on_equipment_changed(
	_slot: StatTypes.EquipmentSlot,
	old_item: EquipmentData,
	new_item: EquipmentData
) -> void:
	if not _runtime_service.is_in_abyss:
		return
	_track_displaced_operation_loot(old_item, new_item, LOOT_CATEGORY_EQUIPMENT)


func _on_skill_gem_changed(old_gem: SkillGem, new_gem: SkillGem) -> void:
	if not _runtime_service.is_in_abyss:
		return
	_track_displaced_operation_loot(old_gem, new_gem, LOOT_CATEGORY_SKILL_GEM)


func _on_support_gem_changed(_slot_index: int, old_gem: SupportGem, new_gem: SupportGem) -> void:
	if not _runtime_service.is_in_abyss:
		return
	_track_displaced_operation_loot(old_gem, new_gem, LOOT_CATEGORY_SUPPORT_GEM)


func _on_module_changed(_slot_index: int, old_module: Module, new_module: Module) -> void:
	if not _runtime_service.is_in_abyss:
		return
	_track_displaced_operation_loot(old_module, new_module, LOOT_CATEGORY_MODULE)


func _track_displaced_operation_loot(old_item: Variant, new_item: Variant, category: String) -> void:
	_command_service.track_displaced_operation_loot(old_item, new_item, category)
