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
var floor_death_count: int = 0
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

const GEM_DROP_CHANCE := 0.01
const MATERIAL_DROP_CHANCE := 0.12
const MAX_DEATHS_PER_FLOOR := 3
const EXTRACTION_WINDOW_DURATION := 10.0
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

	# Setup UI panels
	_setup_equipment_panel()
	_setup_skill_link_panel()
	_setup_crafting_panel()
	_setup_module_panel()


func _setup_equipment_panel() -> void:
	equipment_panel = equipment_panel_scene.instantiate()
	ui_layer.add_child(equipment_panel)
	equipment_panel.closed.connect(_on_equipment_panel_closed)
	equipment_panel.navigate_to.connect(_on_panel_navigate)


func _setup_skill_link_panel() -> void:
	skill_link_panel = skill_link_panel_scene.instantiate()
	ui_layer.add_child(skill_link_panel)
	skill_link_panel.closed.connect(_on_skill_link_panel_closed)
	skill_link_panel.navigate_to.connect(_on_panel_navigate)


func _setup_crafting_panel() -> void:
	crafting_panel = crafting_panel_scene.instantiate()
	ui_layer.add_child(crafting_panel)
	crafting_panel.closed.connect(_on_crafting_panel_closed)
	crafting_panel.navigate_to.connect(_on_panel_navigate)


func _setup_module_panel() -> void:
	module_panel = module_panel_scene.instantiate()
	ui_layer.add_child(module_panel)
	module_panel.closed.connect(_on_module_panel_closed)
	module_panel.navigate_to.connect(_on_panel_navigate)


func _connect_signals() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.player_died.connect(_on_player_died)
	EventBus.enemy_died.connect(_on_enemy_died)
	if hud:
		if hud.has_signal("decrease_farm_floor_requested"):
			hud.decrease_farm_floor_requested.connect(_on_decrease_farm_floor_requested)
		if hud.has_signal("increase_farm_floor_requested"):
			hud.increase_farm_floor_requested.connect(_on_increase_farm_floor_requested)
		if hud.has_signal("challenge_failed_floor_requested"):
			hud.challenge_failed_floor_requested.connect(_on_challenge_failed_floor_requested)

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
	var weapon: EquipmentData = ItemGenerator.generate_equipment("iron_sword", StatTypes.Rarity.WHITE, 1)
	if weapon:
		player.equip(weapon)
	_grant_starter_backup_weapons()

	# Starter skill gems
	for id in DataManager.get_starter_skill_gem_ids():
		var gem := DataManager.create_skill_gem(id)
		if gem:
			player.add_skill_gem_to_inventory(gem)
	if debug_grant_all_skill_gems:
		_grant_all_skill_gems_for_testing()

	# Starter support gems
	for id in DataManager.get_starter_support_gem_ids():
		var support := DataManager.create_support_gem(id)
		if support:
			player.add_support_gem_to_inventory(support)
	if debug_grant_all_support_gems:
		_grant_all_support_gems_for_testing()

	# Starter modules
	for id in DataManager.get_starter_module_ids():
		var mod := DataManager.create_module(id)
		if mod:
			player.add_module_to_inventory(mod)

	# Starter crafting materials
	player.add_material("alter", 5)
	player.add_material("augment", 5)
	player.add_material("refine", 5)


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
	for i in range(Constants.MAX_SKILL_GEM_INVENTORY):
		var gem := player.get_skill_gem_in_inventory(i)
		if gem != null and gem.id == id:
			return true
	return false


func _player_has_support_gem_id(id: String) -> bool:
	if player == null:
		return false
	for i in range(Constants.MAX_SUPPORT_GEM_INVENTORY):
		var gem := player.get_support_gem_in_inventory(i)
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

	var config: Dictionary = DataManager.get_floor_config(floor_number)
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
			return "目標：擊殺 Boss（%d/%d）" % [boss_kills_on_floor, required_boss_kills]
		FloorObjectiveType.CLEAR_AND_ELITE:
			return "目標：清場並擊殺菁英（%d/%d）" % [elite_kills_on_floor, required_elite_kills]
		_:
			return "目標：清除所有敵人"


func _progression_mode_text() -> String:
	match progression_mode:
		ProgressionMode.FARMING:
			return "模式：農層"
		ProgressionMode.RETRYING:
			return "模式：重試"
		_:
			return "模式：推進"


func _update_progression_hud() -> void:
	if hud == null:
		return
	var deaths_left: int = maxi(0, MAX_DEATHS_PER_FLOOR - floor_death_count)
	var primary := "%s   剩餘命數：%d" % [_objective_text(), deaths_left]
	var secondary := "農層目標：%d（- / =）" % preferred_farm_floor
	if pending_failed_floor > 0:
		secondary += "   待重試樓層：%d（N）" % pending_failed_floor
	if hud.has_method("set_progression_display"):
		hud.set_progression_display(_progression_mode_text(), primary, secondary)
	elif hud.has_method("set_progression_status"):
		hud.set_progression_status("%s | %s | %s" % [_progression_mode_text(), primary, secondary])
	if hud.has_method("set_floor_choice_visible"):
		hud.set_floor_choice_visible(false)


func _on_damage_dealt(source: Node, target: Node, damage_info: Dictionary) -> void:
	var pos: Vector2 = damage_info.get("position", target.global_position + Vector2(0, -20))
	var element: StatTypes.Element = damage_info.get("element", StatTypes.Element.PHYSICAL)
	var final_damage: float = float(damage_info.get("final_damage", damage_info.get("damage", 0.0)))

	if damage_number_scene and target:
		var dmg_node: Node = damage_number_scene.instantiate()
		var dmg_num: DamageNumber = dmg_node as DamageNumber
		if dmg_num == null:
			return
		dmg_num.global_position = pos
		dmg_num.setup(
			damage_info.get("damage", damage_info.get("final_damage", 0)),
			damage_info.get("is_crit", false),
			element
		)
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


func _on_enemy_died(enemy: Node, position: Vector2) -> void:
	var enemy_base: EnemyBase = enemy as EnemyBase
	if enemy_base != null:
		if enemy_base.is_boss:
			boss_kills_on_floor += 1
			GameManager.add_boss_kill_risk()
		elif enemy_base.is_elite:
			elite_kills_on_floor += 1
			GameManager.add_elite_kill_risk()

	if randf() < 0.14:  # 14% equipment drop chance
		_drop_item(position)
	if randf() < GEM_DROP_CHANCE:  # 1.0% gem drop chance
		_drop_gem(position)
	if randf() < MATERIAL_DROP_CHANCE:  # 12% material drop chance
		_drop_material(position)
	if randf() < 0.012:  # 1.2% module drop chance
		_drop_module(position)

	_update_progression_hud()
	if floor_objective_type == FloorObjectiveType.BOSS_KILL and boss_kills_on_floor >= required_boss_kills:
		await _on_floor_objective_completed()


func _drop_item(position: Vector2) -> void:
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

	var equipment: EquipmentData = ItemGenerator.generate_random_equipment(slot, current_floor)
	if equipment:
		_spawn_dropped_item(equipment, position)


func _drop_gem(position: Vector2) -> void:
	var level: int = _roll_gem_drop_level(current_floor)
	var gem: Resource = _create_random_gem(level)
	if gem != null:
		_spawn_dropped_item(gem, position)


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


func _drop_module(position: Vector2) -> void:
	var ids := DataManager.get_all_module_ids()
	if ids.is_empty():
		return
	var id: String = ids[randi() % ids.size()]
	var mod := DataManager.create_module(id)
	if mod:
		_spawn_dropped_item(mod, position)


func _drop_material(position: Vector2) -> void:
	var ids := DataManager.get_all_material_ids()
	if ids.is_empty():
		return
	var id: String = ids[randi() % ids.size()]
	var amount := 1
	_spawn_dropped_item({
		"material_id": id,
		"amount": amount,
	}, position)


func _spawn_dropped_item(item: Variant, position: Vector2) -> void:
	if dropped_item_scene == null:
		return

	var dropped: DroppedItem = dropped_item_scene.instantiate()
	dropped.global_position = position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	dropped.setup(item)
	add_child(dropped)

	if item is EquipmentData:
		EventBus.equipment_dropped.emit(item, position)
	elif item is SkillGem or item is SupportGem:
		EventBus.gem_dropped.emit(item, position)
	elif item is Module:
		EventBus.module_dropped.emit(item, position)


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
	GameManager.add_floor_clear_risk()
	var cleared_floor: int = current_floor
	if GameManager.should_open_extraction_window(cleared_floor):
		var extracted: bool = await _run_extraction_window(cleared_floor)
		if extracted:
			_reset_after_extraction()
			return
	if _is_in_farm_recovery_phase():
		progression_mode = ProgressionMode.FARMING
		floor_death_count = 0
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
	floor_death_count = 0
	_update_progression_hud()
	GameManager.complete_floor()
	var next_floor: int = current_floor + 1
	highest_unlocked_floor = maxi(highest_unlocked_floor, next_floor)
	if preferred_farm_floor > highest_unlocked_floor:
		preferred_farm_floor = highest_unlocked_floor
	_start_floor(next_floor)


func _replay_current_floor() -> void:
	if player == null or player.is_dead:
		return
	awaiting_floor_choice = false
	floor_death_count = 0
	_update_progression_hud()
	_start_floor(current_floor)


func _on_player_died() -> void:
	is_floor_active = false
	awaiting_floor_choice = false
	_extraction_window_active = false
	_extraction_selected = false
	enemy_spawner.clear_enemies()
	floor_death_count += 1

	var deaths_left: int = maxi(0, MAX_DEATHS_PER_FLOOR - floor_death_count)
	print("Player died on floor %d (deaths left: %d)" % [current_floor, deaths_left])
	var loss_summary := GameManager.apply_death_material_penalty(player)
	if int(loss_summary.get("lost", 0)) > 0:
		print("[RunFail] Material loss=%d keep=%d" % [int(loss_summary.get("lost", 0)), int(loss_summary.get("kept", 0))])
	_update_progression_hud()
	var restart_floor: int = current_floor
	if floor_death_count >= MAX_DEATHS_PER_FLOOR:
		if progression_mode == ProgressionMode.FARMING:
			restart_floor = preferred_farm_floor
			floor_death_count = 0
			print("[FloorFail] Farming floor failed, restart farm floor %d" % restart_floor)
		else:
			pending_failed_floor = current_floor
			progression_mode = ProgressionMode.FARMING
			var max_allowed_after_fail: int = maxi(1, current_floor - 1)
			var max_selectable: int = mini(highest_unlocked_floor, max_allowed_after_fail)
			preferred_farm_floor = clampi(preferred_farm_floor, 1, max_selectable)
			restart_floor = preferred_farm_floor
			print("[FloorFail] Trial failed on floor %d, fallback to selected floor %d" % [current_floor, restart_floor])

	await get_tree().create_timer(2.0).timeout
	_respawn_player(restart_floor)


func try_pickup_item(item_data: Variant) -> bool:
	if player == null:
		return false

	if item_data is EquipmentData:
		var equipment: EquipmentData = item_data
		if player.add_to_inventory(equipment):
			var rarity_name: String = StatTypes.RARITY_NAMES.get(equipment.rarity, "Unknown")
			print("撿到裝備：%s [%s]" % [equipment.display_name, rarity_name])
			EventBus.item_picked_up.emit(equipment)
			return true
		print("Inventory full: %s" % equipment.display_name)
		return false

	if item_data is SkillGem:
		var gem: SkillGem = item_data
		if player.add_skill_gem_to_inventory(gem):
			print("撿到技能寶石：%s" % gem.display_name)
			EventBus.item_picked_up.emit(gem)
			return true
		print("Skill Gem inventory full: %s" % gem.display_name)
		return false

	if item_data is SupportGem:
		var support: SupportGem = item_data
		if player.add_support_gem_to_inventory(support):
			print("撿到輔助寶石：%s" % support.display_name)
			EventBus.item_picked_up.emit(support)
			return true
		print("Support Gem inventory full: %s" % support.display_name)
		return false

	if item_data is Module:
		var mod: Module = item_data
		if player.add_module_to_inventory(mod):
			print("撿到模組：%s（負載 %d）" % [mod.display_name, mod.load_cost])
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
			print("撿到材料：%s x%d" % [name, amount])
			EventBus.item_picked_up.emit({
				"material_id": mat_id,
				"amount": amount,
			})
			return true

	return false


func _respawn_player(target_floor: int = -1) -> void:
	if player:
		player.respawn()
		if player_spawn:
			player.global_position = player_spawn.global_position

	GameManager.resume_playing()
	var floor_to_start: int = current_floor if target_floor < 1 else target_floor
	if floor_to_start != current_floor:
		floor_death_count = 0
	_start_floor(floor_to_start)


func _challenge_pending_failed_floor() -> void:
	if pending_failed_floor <= 0:
		return
	if player == null or player.is_dead:
		return
	var target: int = pending_failed_floor
	if target > highest_unlocked_floor:
		return
	progression_mode = ProgressionMode.RETRYING
	floor_death_count = 0
	awaiting_floor_choice = false
	_update_progression_hud()
	print("[Progression] Challenge failed floor %d" % target)
	_start_floor(target)


func _is_in_farm_recovery_phase() -> bool:
	return progression_mode == ProgressionMode.FARMING and pending_failed_floor > 0


func _on_decrease_farm_floor_requested() -> void:
	var target_floor: int = clampi(current_floor - 1, 1, highest_unlocked_floor)
	_jump_to_floor_immediately(target_floor)


func _on_increase_farm_floor_requested() -> void:
	var target_floor: int = clampi(current_floor + 1, 1, highest_unlocked_floor)
	_jump_to_floor_immediately(target_floor)


func _on_challenge_failed_floor_requested() -> void:
	_challenge_pending_failed_floor()


func _jump_to_floor_immediately(target_floor: int) -> void:
	if player == null or player.is_dead:
		return
	var clamped_target: int = clampi(target_floor, 1, highest_unlocked_floor)
	preferred_farm_floor = clamped_target
	if clamped_target == current_floor:
		_update_progression_hud()
		return
	if pending_failed_floor > 0:
		progression_mode = ProgressionMode.RETRYING if clamped_target == pending_failed_floor else ProgressionMode.FARMING
	else:
		progression_mode = ProgressionMode.PUSHING
	floor_death_count = 0
	awaiting_floor_choice = false
	_update_progression_hud()
	_start_floor(clamped_target)


func _update_hud() -> void:
	if hud and hud.has_method("update_floor"):
		hud.update_floor(current_floor)
	_update_progression_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
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
		if event.keycode == KEY_MINUS:
			_on_decrease_farm_floor_requested()
			print("[Progression] Jump floor: %d" % preferred_farm_floor)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_EQUAL:
			_on_increase_farm_floor_requested()
			print("[Progression] Jump floor: %d" % preferred_farm_floor)
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
				"撤離窗口（剩餘 %d 秒）\n[E] 立即撤離    [F] 直接繼續\n未選擇：時間到自動繼續" % remaining_sec
			)
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	_extraction_window_active = false
	if hud != null and hud.has_method("set_extraction_prompt"):
		hud.set_extraction_prompt(false, "")
	GameManager.close_extraction_window(floor_number, _extraction_selected, player)
	return _extraction_selected


func _reset_after_extraction() -> void:
	print("[撤離成功] 樓層=%d 風險=%d" % [current_floor, GameManager.risk_score])
	progression_mode = ProgressionMode.PUSHING
	floor_death_count = 0
	pending_failed_floor = 0
	preferred_farm_floor = 1
	GameManager.reset_risk()
	_update_progression_hud()
	_start_floor(1)


func _toggle_equipment_panel() -> void:
	if equipment_panel == null:
		return

	if equipment_panel.visible:
		equipment_panel.close()
	else:
		equipment_panel.open(player)


func _on_equipment_panel_closed() -> void:
	pass


func _toggle_skill_link_panel() -> void:
	if skill_link_panel == null:
		return

	if skill_link_panel.visible:
		skill_link_panel.close()
	else:
		skill_link_panel.open(player)


func _on_skill_link_panel_closed() -> void:
	pass


func _toggle_crafting_panel() -> void:
	if crafting_panel == null:
		return

	if crafting_panel.visible:
		crafting_panel.close()
	else:
		crafting_panel.open(player, current_floor)


func _on_crafting_panel_closed() -> void:
	pass


func _toggle_module_panel() -> void:
	if module_panel == null:
		return

	if module_panel.visible:
		module_panel.close()
	else:
		module_panel.open(player)


func _on_module_panel_closed() -> void:
	pass


func _pickup_all_items() -> void:
	if player == null:
		return

	var dropped_items := get_tree().get_nodes_in_group("dropped_items")

	for item in dropped_items:
		if item is DroppedItem and item.can_auto_pickup():
			item.start_magnet(player)


func _on_panel_navigate(panel_id: String) -> void:
	_close_all_panels()
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


func _close_all_panels() -> void:
	if equipment_panel and equipment_panel.visible:
		equipment_panel.close()
	if skill_link_panel and skill_link_panel.visible:
		skill_link_panel.close()
	if crafting_panel and crafting_panel.visible:
		crafting_panel.close()
	if module_panel and module_panel.visible:
		module_panel.close()
