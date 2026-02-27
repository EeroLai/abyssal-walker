class_name Game
extends Node2D

@export var player_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var dropped_item_scene: PackedScene
@export var equipment_panel_scene: PackedScene
@export var skill_link_panel_scene: PackedScene
@export var crafting_panel_scene: PackedScene
@export var module_panel_scene: PackedScene
@export var debug_grant_all_skill_gems: bool = true
@export var debug_grant_all_support_gems: bool = true

const HIT_EFFECT_SCENE := preload("res://scenes/effects/hit_effect.tscn")
const LOBBY_SCENE_PATH := "res://scenes/main/lobby.tscn"

@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var ui_layer: CanvasLayer = $UILayer
@onready var hud: Control = $UILayer/HUD
@onready var background: ColorRect = $Background

var equipment_panel: EquipmentPanel = null
var skill_link_panel: SkillLinkPanel = null
var crafting_panel: CraftingPanel = null
var module_panel: ModulePanel = null

var player: Player = null
var current_floor: int = 1
var is_floor_active: bool = false
var awaiting_floor_choice: bool = false
var highest_unlocked_floor: int = 1
var preferred_farm_floor: int = 1
var pending_failed_floor: int = 0
var elite_kills_on_floor: int = 0
var boss_kills_on_floor: int = 0
var required_elite_kills: int = 0
var required_boss_kills: int = 0

enum ProgressionMode {
	PUSHING,
	FARMING,
	RETRYING,
}

var progression_mode: int = ProgressionMode.PUSHING

enum FloorObjectiveType {
	CLEAR_ALL,
	CLEAR_AND_ELITE,
	BOSS_KILL,
}

var floor_objective_type: int = FloorObjectiveType.CLEAR_ALL
var _camera_shake_tween: Tween = null
var _camera_base_offset: Vector2 = Vector2.ZERO
var _extraction_window_active: bool = false
var _extraction_selected: bool = false
var _extraction_decided: bool = false
var _run_fail_waiting_return: bool = false
var _run_fail_return_confirmed: bool = false

const GEM_DROP_CHANCE := 0.01
const MATERIAL_DROP_CHANCE := 0.12
const EXTRACTION_WINDOW_DURATION := 10.0
const RUN_SUMMARY_TIMEOUT_MS := 45000
const STARTER_BACKUP_WEAPON_IDS: Array[String] = [
	"iron_dagger",
	"short_bow",
	"apprentice_wand",
]

func _ready() -> void:
	_load_scenes()
	_connect_signals()
	_spawn_player()
	GameManager.start_game()
	highest_unlocked_floor = 1
	preferred_farm_floor = 1
	progression_mode = ProgressionMode.PUSHING
	_start_floor(1)


func _exit_tree() -> void:
	_save_persistent_build_if_possible()


func _load_scenes() -> void:
	if player_scene == null:
		player_scene = preload("res://scenes/entities/player/player.tscn")
	if damage_number_scene == null:
		damage_number_scene = preload("res://scenes/ui/damage_number.tscn")
	if dropped_item_scene == null:
		dropped_item_scene = preload("res://scenes/loot/dropped_item.tscn")
	if equipment_panel_scene == null:
		equipment_panel_scene = preload("res://scenes/ui/equipment_panel.tscn")
	if skill_link_panel_scene == null:
		skill_link_panel_scene = preload("res://scenes/ui/skill_link_panel.tscn")
	if crafting_panel_scene == null:
		crafting_panel_scene = preload("res://scenes/ui/crafting_panel.tscn")
	if module_panel_scene == null:
		module_panel_scene = preload("res://scenes/ui/module_panel.tscn")

	_setup_panels()


func _setup_panels() -> void:
	equipment_panel = _instantiate_panel(equipment_panel_scene) as EquipmentPanel
	skill_link_panel = _instantiate_panel(skill_link_panel_scene) as SkillLinkPanel
	crafting_panel = _instantiate_panel(crafting_panel_scene) as CraftingPanel
	module_panel = _instantiate_panel(module_panel_scene) as ModulePanel


func _instantiate_panel(scene: PackedScene) -> Control:
	if scene == null or ui_layer == null:
		return null
	var panel := scene.instantiate() as Control
	if panel == null:
		return null
	ui_layer.add_child(panel)
	if panel.has_signal("navigate_to"):
		panel.connect("navigate_to", Callable(self, "_on_panel_navigate"))
	return panel


func _connect_signals() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_died.connect(_on_enemy_died)
	if hud:
		if hud.has_signal("challenge_failed_floor_requested"):
			hud.challenge_failed_floor_requested.connect(_on_challenge_failed_floor_requested)
		if hud.has_signal("run_summary_confirmed"):
			hud.run_summary_confirmed.connect(_on_run_summary_confirmed)

	if enemy_spawner:
		enemy_spawner.all_enemies_dead.connect(_on_all_enemies_dead)


func _spawn_player() -> void:
	player = player_scene.instantiate()

	if player_spawn:
		player.global_position = player_spawn.global_position
	else:
		player.global_position = Vector2(640, 360)

	add_child(player)
	_configure_player_camera()
	_setup_initial_build()
	_sync_player_materials_from_stash()


func _sync_player_materials_from_stash() -> void:
	if player == null:
		return
	GameManager.sync_player_materials_from_stash(player)


func _configure_player_camera() -> void:
	if player == null:
		return
	var camera: Camera2D = player.get_node_or_null("Camera2D")
	if camera == null:
		return
	camera.enabled = true
	camera.make_current()
	if background == null:
		return

	var left := int(background.offset_left + background.position.x)
	var top := int(background.offset_top + background.position.y)
	var right := int(background.offset_right + background.position.x)
	var bottom := int(background.offset_bottom + background.position.y)

	camera.limit_left = left
	camera.limit_top = top
	camera.limit_right = right
	camera.limit_bottom = bottom
	_camera_base_offset = camera.offset


func _setup_initial_build() -> void:
	if GameManager.has_persistent_player_build():
		GameManager.apply_persistent_player_build_to_player(player)
		GameManager.apply_operation_loadout_to_player(player)
		_apply_debug_gem_grants()
		GameManager.save_persistent_player_build_from_player(player)
		return

	var weapon: EquipmentData = ItemGenerator.generate_equipment("iron_sword", StatTypes.Rarity.WHITE, 1)
	if weapon:
		player.equip(weapon)
	_grant_starter_backup_weapons()

	# Starter skill gems
	for id in DataManager.get_starter_skill_gem_ids():
		var gem := DataManager.create_skill_gem(id)
		if gem:
			player.add_skill_gem_to_inventory(gem)

	# Starter support gems
	for id in DataManager.get_starter_support_gem_ids():
		var support := DataManager.create_support_gem(id)
		if support:
			player.add_support_gem_to_inventory(support)
	_apply_debug_gem_grants()
	# Starter modules
	for id in DataManager.get_starter_module_ids():
		var mod := DataManager.create_module(id)
		if mod:
			player.add_module_to_inventory(mod)

	GameManager.apply_operation_loadout_to_player(player)
	GameManager.save_persistent_player_build_from_player(player)


func _apply_debug_gem_grants() -> void:
	if debug_grant_all_skill_gems:
		_grant_all_skill_gems_for_testing()
	if debug_grant_all_support_gems:
		_grant_all_support_gems_for_testing()

func _grant_starter_backup_weapons() -> void:
	for base_id in STARTER_BACKUP_WEAPON_IDS:
		var weapon := ItemGenerator.generate_equipment(base_id, StatTypes.Rarity.WHITE, 1)
		if weapon != null:
			player.add_to_inventory(weapon)


func _grant_all_skill_gems_for_testing() -> void:
	var all_ids := DataManager.get_all_skill_gem_ids()
	for id in all_ids:
		if _player_has_skill_gem_id(id):
			continue
		var gem := DataManager.create_skill_gem(id)
		if gem != null:
			player.add_skill_gem_to_inventory(gem)


func _grant_all_support_gems_for_testing() -> void:
	var all_ids := DataManager.get_all_support_gem_ids()
	for id in all_ids:
		if _player_has_support_gem_id(id):
			continue
		var gem := DataManager.create_support_gem(id)
		if gem != null:
			player.add_support_gem_to_inventory(gem)


func _player_has_skill_gem_id(id: String) -> bool:
	if player == null:
		return false
	if player.gem_link != null and player.gem_link.skill_gem != null:
		if player.gem_link.skill_gem.id == id:
			return true
	return _inventory_has_gem_id(id, Constants.MAX_SKILL_GEM_INVENTORY, Callable(player, "get_skill_gem_in_inventory"))


func _player_has_support_gem_id(id: String) -> bool:
	if player == null:
		return false
	return _inventory_has_gem_id(id, Constants.MAX_SUPPORT_GEM_INVENTORY, Callable(player, "get_support_gem_in_inventory"))


func _inventory_has_gem_id(id: String, max_count: int, getter: Callable) -> bool:
	for i in range(max_count):
		var gem = getter.call(i)
		if gem != null and gem.id == id:
			return true
	return false


func _start_floor(floor_number: int) -> void:
	current_floor = floor_number
	GameManager.enter_floor(floor_number)
	awaiting_floor_choice = false
	elite_kills_on_floor = 0
	boss_kills_on_floor = 0
	required_elite_kills = 0
	required_boss_kills = 0
	floor_objective_type = FloorObjectiveType.CLEAR_ALL

	var effective_level: int = GameManager.get_effective_drop_level(floor_number)
	var config: Dictionary = DataManager.get_floor_config(effective_level)
	if config.is_empty():
		config = DataManager.get_floor_config(1)
	config = config.duplicate(true)
	_configure_floor_objective(floor_number, config)

	enemy_spawner.setup(config, player)
	enemy_spawner.set_floor_number(floor_number)
	enemy_spawner.spawn_wave()

	is_floor_active = true

	_update_hud()
	if hud != null and hud.has_method("set_extraction_prompt"):
		hud.set_extraction_prompt(false, "")
	_update_progression_hud()


func _configure_floor_objective(floor_number: int, config: Dictionary) -> void:
	if floor_number % 10 == 0:
		floor_objective_type = FloorObjectiveType.BOSS_KILL
		required_boss_kills = 1
		if not config.has("boss"):
			config["boss"] = "abyss_watcher"


func _objective_text() -> String:
	match floor_objective_type:
		FloorObjectiveType.BOSS_KILL:
			return "Objective: Defeat Boss (%d/%d)" % [boss_kills_on_floor, required_boss_kills]
		FloorObjectiveType.CLEAR_AND_ELITE:
			return "Objective: Clear + Elite (%d/%d)" % [elite_kills_on_floor, required_elite_kills]
		_:
			return "Objective: Clear all enemies"


func _progression_mode_text() -> String:
	match progression_mode:
		ProgressionMode.FARMING:
			return "Mode: Farming"
		ProgressionMode.RETRYING:
			return "Mode: Retrying"
		_:
			return "Mode: Pushing"


func _update_progression_hud() -> void:
	if hud == null:
		return
	var deaths_left: int = maxi(0, GameManager.get_lives_left())
	var primary := "%s   Lives Left: %d" % [_objective_text(), deaths_left]
	var secondary := "Target Floor: %d" % preferred_farm_floor
	if pending_failed_floor > 0:
		secondary += "   Failed Floor: %d (N)" % pending_failed_floor
	if hud.has_method("set_progression_display"):
		hud.set_progression_display(_progression_mode_text(), primary, secondary)
	elif hud.has_method("set_progression_status"):
		hud.set_progression_status("%s | %s | %s" % [_progression_mode_text(), primary, secondary])
	if hud.has_method("set_floor_choice_visible"):
		hud.set_floor_choice_visible(false)


func _on_damage_dealt(source: Node, target: Node, damage_info: Dictionary) -> void:
	var fallback_pos := Vector2.ZERO
	if target is Node2D:
		fallback_pos = (target as Node2D).global_position + Vector2(0, -20)
	var pos: Vector2 = damage_info.get("position", fallback_pos)
	var element: StatTypes.Element = damage_info.get("element", StatTypes.Element.PHYSICAL)
	var final_damage: float = float(damage_info.get("final_damage", damage_info.get("damage", 0.0)))

	if damage_number_scene and target:
		var dmg_node: Node = damage_number_scene.instantiate()
		var dmg_num: DamageNumber = dmg_node as DamageNumber
		if dmg_num == null:
			return
		dmg_num.global_position = pos
		dmg_num.setup(final_damage, damage_info.get("is_crit", false), element)
		add_child(dmg_num)

	var effect: HitEffect = HIT_EFFECT_SCENE.instantiate()
	effect.global_position = pos
	effect.setup(StatTypes.ELEMENT_COLORS.get(element, Color.WHITE))
	add_child(effect)

	var is_crit: bool = bool(damage_info.get("is_crit", false))
	if is_crit and source == player and _is_player_melee_context():
		_play_crit_camera_shake()


func _play_crit_camera_shake() -> void:
	if player == null:
		return
	var camera: Camera2D = player.get_node_or_null("Camera2D")
	if camera == null:
		return
	if _camera_shake_tween != null and _camera_shake_tween.is_valid():
		_camera_shake_tween.kill()

	var p1 := _camera_base_offset + Vector2(randf_range(-3.0, 3.0), randf_range(-2.5, 2.5))
	var p2 := _camera_base_offset + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	_camera_shake_tween = create_tween()
	_camera_shake_tween.tween_property(camera, "offset", p1, 0.03)
	_camera_shake_tween.tween_property(camera, "offset", p2, 0.03)
	_camera_shake_tween.tween_property(camera, "offset", _camera_base_offset, 0.04)


func _is_player_melee_context() -> bool:
	if player == null:
		return false
	if player.gem_link != null and player.gem_link.skill_gem != null:
		return player.gem_link.skill_gem.has_tag(StatTypes.SkillTag.MELEE)
	var weapon_type := player.get_weapon_type()
	return weapon_type == StatTypes.WeaponType.SWORD or weapon_type == StatTypes.WeaponType.DAGGER


func _on_enemy_died(enemy: Node, drop_position: Vector2) -> void:
	var enemy_base: EnemyBase = enemy as EnemyBase
	if enemy_base != null:
		if enemy_base.is_boss:
			boss_kills_on_floor += 1
			GameManager.add_danger(2)
		elif enemy_base.is_elite:
			elite_kills_on_floor += 1
			GameManager.add_danger(1)

	if randf() < 0.14:  # 14% equipment drop chance
		_drop_item(drop_position)
	if randf() < GEM_DROP_CHANCE:  # 1.0% gem drop chance
		_drop_gem(drop_position)
	if randf() < MATERIAL_DROP_CHANCE:  # 12% material drop chance
		_drop_material(drop_position)
	if randf() < 0.012:  # 1.2% module drop chance
		_drop_module(drop_position)

	_update_progression_hud()
	if floor_objective_type == FloorObjectiveType.BOSS_KILL and boss_kills_on_floor >= required_boss_kills:
		await _on_floor_objective_completed()


func _drop_item(drop_position: Vector2) -> void:
	var slots: Array[StatTypes.EquipmentSlot] = [
		StatTypes.EquipmentSlot.MAIN_HAND,
		StatTypes.EquipmentSlot.MAIN_HAND,  # weapon weight x2
		StatTypes.EquipmentSlot.OFF_HAND,
		StatTypes.EquipmentSlot.HELMET,
		StatTypes.EquipmentSlot.ARMOR,
		StatTypes.EquipmentSlot.ARMOR,  # armor weight x2
		StatTypes.EquipmentSlot.GLOVES,
		StatTypes.EquipmentSlot.BOOTS,
		StatTypes.EquipmentSlot.BELT,
		StatTypes.EquipmentSlot.AMULET,
		StatTypes.EquipmentSlot.RING_1,
	]
	var slot: StatTypes.EquipmentSlot = slots[randi() % slots.size()]

	var drop_level: int = GameManager.get_effective_drop_level(current_floor)
	var equipment: EquipmentData = ItemGenerator.generate_random_equipment(slot, drop_level)
	if equipment:
		_spawn_dropped_item(equipment, drop_position)


func _drop_gem(drop_position: Vector2) -> void:
	var effective_level: int = GameManager.get_effective_drop_level(current_floor)
	var level: int = _roll_gem_drop_level(effective_level)
	var gem: Resource = _create_random_gem(level)
	if gem != null:
		_spawn_dropped_item(gem, drop_position)


func _create_random_gem(level: int) -> Resource:
	var drop_skill: bool = randf() < 0.5
	if drop_skill:
		var skill_ids: Array = DataManager.get_all_skill_gem_ids()
		if skill_ids.is_empty():
			return null
		var skill_id: String = skill_ids[randi() % skill_ids.size()]
		var skill: SkillGem = DataManager.create_skill_gem(skill_id)
		if skill != null:
			skill.level = level
			skill.experience = 0.0
		return skill
	var support_ids: Array = DataManager.get_all_support_gem_ids()
	if support_ids.is_empty():
		return null
	var support_id: String = support_ids[randi() % support_ids.size()]
	var support: SupportGem = DataManager.create_support_gem(support_id)
	if support != null:
		support.level = level
		support.experience = 0.0
	return support


func _roll_gem_drop_level(floor_number: int) -> int:
	var min_lv := 1
	var max_lv := 2
	if floor_number >= 100:
		min_lv = 15
		max_lv = 20
	elif floor_number >= 85:
		min_lv = 12
		max_lv = 16
	elif floor_number >= 70:
		min_lv = 9
		max_lv = 13
	elif floor_number >= 55:
		min_lv = 7
		max_lv = 10
	elif floor_number >= 40:
		min_lv = 5
		max_lv = 8
	elif floor_number >= 25:
		min_lv = 3
		max_lv = 6
	elif floor_number >= 10:
		min_lv = 2
		max_lv = 4
	return clampi(randi_range(min_lv, max_lv), 1, Constants.MAX_GEM_LEVEL)


func _drop_module(drop_position: Vector2) -> void:
	var effective_level: int = GameManager.get_effective_drop_level(current_floor)
	var module_id: String = _pick_module_id_for_level(effective_level)
	if module_id.is_empty():
		return
	var mod := DataManager.create_module(module_id)
	if mod:
		_spawn_dropped_item(mod, drop_position)


func _pick_module_id_for_level(effective_level: int) -> String:
	var ids := DataManager.get_all_module_ids()
	if ids.is_empty():
		return ""

	var target_load: float = _target_module_load(effective_level)
	var weighted_ids: Array[String] = []
	var weighted_scores: Array[float] = []
	var total_weight: float = 0.0

	for module_id in ids:
		var module_data: Dictionary = DataManager.get_module_data(module_id)
		if module_data.is_empty():
			continue

		var load_cost: int = int(module_data.get("load_cost", 0))
		var is_starter: bool = bool(module_data.get("is_starter", false))
		var dist := absf(float(load_cost) - target_load)
		var base_weight := 1.0 / (1.0 + dist * 0.25)
		if is_starter:
			base_weight *= 0.35
		if effective_level >= 70 and load_cost >= 15:
			base_weight *= 1.4
		elif effective_level <= 25 and load_cost <= 10:
			base_weight *= 1.25
		base_weight = maxf(base_weight, 0.01)

		weighted_ids.append(module_id)
		weighted_scores.append(base_weight)
		total_weight += base_weight

	if weighted_ids.is_empty():
		return ""
	if total_weight <= 0.0:
		return weighted_ids[randi() % weighted_ids.size()]

	var roll := randf() * total_weight
	var cursor := 0.0
	for i in range(weighted_ids.size()):
		cursor += weighted_scores[i]
		if roll <= cursor:
			return weighted_ids[i]
	return weighted_ids[weighted_ids.size() - 1]


func _target_module_load(effective_level: int) -> float:
	if effective_level >= 85:
		return 18.0
	if effective_level >= 70:
		return 15.0
	if effective_level >= 45:
		return 12.0
	if effective_level >= 20:
		return 10.0
	return 8.0


func _drop_material(drop_position: Vector2) -> void:
	var ids := DataManager.get_all_material_ids()
	if ids.is_empty():
		return
	var id: String = ids[randi() % ids.size()]
	var amount := 1
	_spawn_dropped_item({
		"material_id": id,
		"amount": amount,
	}, drop_position)


func _spawn_dropped_item(item: Variant, drop_position: Vector2) -> void:
	if dropped_item_scene == null:
		return

	var dropped: DroppedItem = dropped_item_scene.instantiate()
	dropped.global_position = drop_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	dropped.setup(item)
	add_child(dropped)

	if item is EquipmentData:
		EventBus.equipment_dropped.emit(item, drop_position)
	elif item is SkillGem or item is SupportGem:
		EventBus.gem_dropped.emit(item, drop_position)
	elif item is Module:
		EventBus.module_dropped.emit(item, drop_position)


func _on_all_enemies_dead() -> void:
	if not is_floor_active:
		return

	if floor_objective_type == FloorObjectiveType.BOSS_KILL:
		return
	if floor_objective_type == FloorObjectiveType.CLEAR_AND_ELITE and elite_kills_on_floor < required_elite_kills:
		return
	await _on_floor_objective_completed()


func _on_floor_objective_completed() -> void:
	if not is_floor_active:
		return
	is_floor_active = false
	enemy_spawner.clear_enemies()
	var cleared_floor: int = current_floor
	if GameManager.should_open_extraction_window(cleared_floor):
		var extracted: bool = await _run_extraction_window(cleared_floor)
		if extracted:
			_reset_after_extraction()
			return
	if _is_in_farm_recovery_phase():
		progression_mode = ProgressionMode.FARMING
		_update_progression_hud()
		_start_floor(preferred_farm_floor)
		return
	_go_to_next_floor()


func _go_to_next_floor() -> void:
	if player == null or player.is_dead:
		return
	if pending_failed_floor == current_floor:
		pending_failed_floor = 0
		progression_mode = ProgressionMode.PUSHING
	elif pending_failed_floor > 0:
		progression_mode = ProgressionMode.FARMING
	else:
		progression_mode = ProgressionMode.PUSHING
	awaiting_floor_choice = false
	_update_progression_hud()
	GameManager.complete_floor()
	var next_floor: int = current_floor + 1
	highest_unlocked_floor = maxi(highest_unlocked_floor, next_floor)
	if preferred_farm_floor > highest_unlocked_floor:
		preferred_farm_floor = highest_unlocked_floor
	_start_floor(next_floor)


func _on_player_died() -> void:
	is_floor_active = false
	awaiting_floor_choice = false
	_extraction_window_active = false
	_extraction_selected = false
	enemy_spawner.clear_enemies()
	var lives_left: int = GameManager.consume_life()
	print("Player died on floor %d (lives left: %d)" % [current_floor, lives_left])
	_update_progression_hud()
	if lives_left <= 0:
		var loss_summary := GameManager.apply_death_material_penalty(player)
		var lost_loot: Dictionary = loss_summary.get("loot_lost", {})
		var lost_equipment: int = int(lost_loot.get("equipment", 0))
		var lost_gems: int = int(lost_loot.get("total_gems", 0))
		var lost_modules: int = int(lost_loot.get("modules", 0))
		print("[RunFail] Loot lost: eq=%d gems=%d modules=%d" % [lost_equipment, lost_gems, lost_modules])
		GameManager.reset_operation()
		progression_mode = ProgressionMode.PUSHING
		pending_failed_floor = 0
		preferred_farm_floor = 1
		var fail_body := "Lost loot:\n- Equipment: %d\n- Gems: %d\n- Modules: %d" % [
			lost_equipment,
			lost_gems,
			lost_modules,
		]
		await _wait_for_run_summary("Run Failed", fail_body)
		_return_to_lobby()
		return

	await get_tree().create_timer(2.0).timeout
	_respawn_player()

func try_pickup_item(item_data: Variant) -> bool:
	if player == null:
		return false

	if item_data is EquipmentData:
		var equipment: EquipmentData = item_data
		if player.add_to_inventory(equipment):
			var rarity_name: String = StatTypes.RARITY_NAMES.get(equipment.rarity, "Unknown")
			print("Picked equipment: %s [%s]" % [equipment.display_name, rarity_name])
			GameManager.add_loot_to_run_backpack(equipment)
			EventBus.item_picked_up.emit(equipment)
			return true
		print("Inventory full: %s" % equipment.display_name)
		return false

	if item_data is SkillGem:
		var gem: SkillGem = item_data
		if player.add_skill_gem_to_inventory(gem):
			print("Picked skill gem: %s" % gem.display_name)
			GameManager.add_loot_to_run_backpack(gem)
			EventBus.item_picked_up.emit(gem)
			return true
		print("Skill Gem inventory full: %s" % gem.display_name)
		return false

	if item_data is SupportGem:
		var support: SupportGem = item_data
		if player.add_support_gem_to_inventory(support):
			print("Picked support gem: %s" % support.display_name)
			GameManager.add_loot_to_run_backpack(support)
			EventBus.item_picked_up.emit(support)
			return true
		print("Support Gem inventory full: %s" % support.display_name)
		return false

	if item_data is Module:
		var mod: Module = item_data
		if player.add_module_to_inventory(mod):
			print("Picked module: %s (load %d)" % [mod.display_name, mod.load_cost])
			GameManager.add_loot_to_run_backpack(mod)
			EventBus.item_picked_up.emit(mod)
			return true
		print("Module inventory full: %s" % mod.display_name)
		return false

	if item_data is Dictionary:
		var mat_id: String = str(item_data.get("material_id", ""))
		var amount: int = int(item_data.get("amount", 1))
		if mat_id != "":
			player.add_material(mat_id, amount)
			var mat_data: Dictionary = DataManager.get_crafting_material(mat_id)
			var name: String = mat_data.get("display_name", mat_id)
			print("Picked material: %s x%d" % [name, amount])
			EventBus.item_picked_up.emit({
				"material_id": mat_id,
				"amount": amount,
			})
			return true
		return false

	return false


func _respawn_player() -> void:
	if player:
		player.respawn()
		if player_spawn:
			player.global_position = player_spawn.global_position

	GameManager.resume_playing()
	_start_floor(current_floor)


func _challenge_pending_failed_floor() -> void:
	if pending_failed_floor <= 0:
		return
	if player == null or player.is_dead:
		return
	var target: int = pending_failed_floor
	if target > highest_unlocked_floor:
		return
	progression_mode = ProgressionMode.RETRYING
	awaiting_floor_choice = false
	_update_progression_hud()
	print("[Progression] Challenge failed floor %d" % target)
	_start_floor(target)


func _is_in_farm_recovery_phase() -> bool:
	return progression_mode == ProgressionMode.FARMING and pending_failed_floor > 0


func _on_challenge_failed_floor_requested() -> void:
	_challenge_pending_failed_floor()


func _update_hud() -> void:
	if hud and hud.has_method("update_floor"):
		hud.update_floor(current_floor)
	_update_progression_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _run_fail_waiting_return and (
			event.keycode == KEY_E
			or event.keycode == KEY_ENTER
			or event.keycode == KEY_ESCAPE
			or event.keycode == KEY_SPACE
		):
			_run_fail_return_confirmed = true
			get_viewport().set_input_as_handled()
			return
		if _extraction_window_active and event.keycode == KEY_E:
			_extraction_selected = true
			_extraction_decided = true
			get_viewport().set_input_as_handled()
			return
		if _extraction_window_active and event.keycode == KEY_F:
			_extraction_selected = false
			_extraction_decided = true
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_N:
			_challenge_pending_failed_floor()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_I:
			_toggle_equipment_panel()
		elif event.keycode == KEY_K:
			_toggle_skill_link_panel()
		elif event.keycode == KEY_C:
			_toggle_crafting_panel()
		elif event.keycode == KEY_M:
			_toggle_module_panel()
		elif event.keycode == KEY_Z:
			_pickup_all_items()

func _run_extraction_window(floor_number: int) -> bool:
	_extraction_window_active = true
	_extraction_selected = false
	_extraction_decided = false
	GameManager.open_extraction_window(floor_number, EXTRACTION_WINDOW_DURATION)

	var elapsed: float = 0.0
	while elapsed < EXTRACTION_WINDOW_DURATION and _extraction_decided == false:
		var remaining_sec: int = maxi(0, int(ceili(EXTRACTION_WINDOW_DURATION - elapsed)))
		if hud != null and hud.has_method("set_extraction_prompt"):
			hud.set_extraction_prompt(
				true,
				"Extraction window (%d sec left)\n[E] Extract now    [F] Continue\nNo choice: auto-continue" % remaining_sec
			)
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	_extraction_window_active = false
	if hud != null and hud.has_method("set_extraction_prompt"):
		hud.set_extraction_prompt(false, "")
	GameManager.close_extraction_window(floor_number, _extraction_selected, player)
	return _extraction_selected


func _reset_after_extraction() -> void:
	print("[Extracted] floor=%d" % current_floor)
	progression_mode = ProgressionMode.PUSHING
	pending_failed_floor = 0
	preferred_farm_floor = 1
	var summary: Dictionary = GameManager.get_last_run_extracted_summary()
	var moved: Dictionary = summary.get("loot_moved", {})
	var moved_equipment: int = int(moved.get("equipment", 0))
	var moved_gems: int = int(moved.get("total_gems", 0))
	var moved_modules: int = int(moved.get("modules", 0))
	var stash_total: int = int(summary.get("stash_total", 0))
	GameManager.restore_lives()
	var extraction_body := "Moved to stash:\n- Equipment: %d\n- Gems: %d\n- Modules: %d\n- Materials in stash: %d" % [
		moved_equipment,
		moved_gems,
		moved_modules,
		stash_total,
	]
	await _wait_for_run_summary("Extraction Success", extraction_body)
	_return_to_lobby()


func _on_run_summary_confirmed() -> void:
	if not _run_fail_waiting_return:
		return
	_run_fail_return_confirmed = true


func _wait_for_run_summary(title: String, body: String) -> void:
	_run_fail_waiting_return = true
	_run_fail_return_confirmed = false
	if hud != null and hud.has_method("show_run_summary"):
		hud.show_run_summary(title, body)
	var started_ms: int = Time.get_ticks_msec()
	while not _run_fail_return_confirmed:
		if Time.get_ticks_msec() - started_ms >= RUN_SUMMARY_TIMEOUT_MS:
			push_warning("Run summary confirm timeout, continue to lobby automatically.")
			_run_fail_return_confirmed = true
			break
		await get_tree().process_frame
	_run_fail_waiting_return = false
	if hud != null and hud.has_method("hide_run_summary"):
		hud.hide_run_summary()


func _return_to_lobby() -> void:
	_run_fail_waiting_return = false
	_run_fail_return_confirmed = false
	if player != null and is_instance_valid(player):
		GameManager.resolve_operation_loadout_for_lobby(player)
	_save_persistent_build_if_possible()
	get_tree().paused = false
	call_deferred("_change_scene_to_lobby_deferred")


func _save_persistent_build_if_possible() -> void:
	if player == null:
		return
	if not is_instance_valid(player):
		return
	GameManager.save_persistent_player_build_from_player(player)


func _change_scene_to_lobby_deferred() -> void:
	var err: Error = get_tree().change_scene_to_file(LOBBY_SCENE_PATH)
	if err != OK:
		push_error("Failed to change scene to lobby (%s), error=%d" % [LOBBY_SCENE_PATH, int(err)])


func _toggle_equipment_panel() -> void:
	_toggle_panel("equipment")


func _toggle_skill_link_panel() -> void:
	_toggle_panel("skill")


func _toggle_crafting_panel() -> void:
	_toggle_panel("crafting")


func _toggle_module_panel() -> void:
	_toggle_panel("module")


func _pickup_all_items() -> void:
	if player == null:
		return

	var dropped_items := get_tree().get_nodes_in_group("dropped_items")

	for item in dropped_items:
		if item is DroppedItem and item.can_auto_pickup():
			item.start_magnet(player)


func _on_panel_navigate(panel_id: String) -> void:
	_close_all_panels()
	_open_panel(panel_id)


func _close_all_panels() -> void:
	for panel in [equipment_panel, skill_link_panel, crafting_panel, module_panel]:
		if panel and panel.visible and panel.has_method("close"):
			panel.call("close")


func _toggle_panel(panel_id: String) -> void:
	var panel := _panel_by_id(panel_id)
	if panel == null:
		return
	if panel.visible:
		panel.call("close")
	else:
		_open_panel(panel_id)


func _open_panel(panel_id: String) -> void:
	match panel_id:
		"equipment":
			if equipment_panel:
				equipment_panel.open(player)
		"skill":
			if skill_link_panel:
				skill_link_panel.open(player)
		"crafting":
			if crafting_panel:
				crafting_panel.open(player, current_floor)
		"module":
			if module_panel:
				module_panel.open(player)


func _panel_by_id(panel_id: String) -> Control:
	match panel_id:
		"equipment":
			return equipment_panel
		"skill":
			return skill_link_panel
		"crafting":
			return crafting_panel
		"module":
			return module_panel
	return null
