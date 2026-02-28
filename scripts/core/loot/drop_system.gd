class_name DropSystem
extends RefCounted

const EQUIPMENT_DROP_CHANCE := 0.14
const GEM_DROP_CHANCE := 0.01
const MATERIAL_DROP_CHANCE := 0.12
const MODULE_DROP_CHANCE := 0.012
const BEACON_DROP_CHANCE_NORMAL := 0.003
const BEACON_DROP_CHANCE_ELITE := 0.03
const ABYSS_BEACON_DATA_SCRIPT := preload("res://scripts/abyss/abyss_beacon_data.gd")
const BEACON_MODIFIER_SYSTEM := preload("res://scripts/abyss/beacon_modifier_system.gd")


static func build_enemy_drop_context(floor_number: int, enemy: EnemyBase = null) -> Dictionary:
	return {
		"depth_index": maxi(1, floor_number),
		"floor": maxi(1, floor_number),
		"base_difficulty": GameManager.get_base_difficulty(),
		"max_depth": GameManager.get_max_depth(),
		"modifier_ids": GameManager.get_modifier_ids(),
		"danger": GameManager.get_danger(),
		"effective_level": GameManager.get_effective_drop_level(floor_number),
		"enemy_is_elite": enemy != null and enemy.is_elite,
		"enemy_is_boss": enemy != null and enemy.is_boss,
	}


static func roll_enemy_drops_for_floor(floor_number: int, enemy: EnemyBase = null) -> Array:
	return roll_enemy_drops(build_enemy_drop_context(floor_number, enemy))


static func roll_enemy_drops(context: Dictionary) -> Array:
	var drops: Array = []

	var equipment: EquipmentData = _roll_equipment_drop(context)
	if equipment != null:
		drops.append(equipment)

	var gem: Resource = _roll_gem_drop(context)
	if gem != null:
		drops.append(gem)

	var material: Dictionary = _roll_material_drop(context)
	if not material.is_empty():
		drops.append(material)

	var module: Module = _roll_module_drop(context)
	if module != null:
		drops.append(module)

	return drops


static func roll_beacon_drop_for_floor(floor_number: int, enemy: EnemyBase = null) -> Resource:
	return roll_beacon_drop(build_enemy_drop_context(floor_number, enemy))


static func create_guaranteed_beacon_for_floor(floor_number: int, enemy: EnemyBase = null) -> Resource:
	return create_guaranteed_beacon(build_enemy_drop_context(floor_number, enemy))


static func roll_beacon_drop(context: Dictionary) -> Resource:
	var is_boss: bool = bool(context.get("enemy_is_boss", false))
	var is_elite: bool = bool(context.get("enemy_is_elite", false))
	var summary := _beacon_modifier_summary_from_context(context)
	var chance_bonus := float(summary.get("beacon_drop_chance_bonus", 0.0))
	if not is_boss and not is_elite:
		if randf() >= clampf(BEACON_DROP_CHANCE_NORMAL + chance_bonus, 0.0, 1.0):
			return null
	elif not is_boss:
		if randf() >= clampf(BEACON_DROP_CHANCE_ELITE + chance_bonus, 0.0, 1.0):
			return null

	return create_guaranteed_beacon(context)


static func create_guaranteed_beacon(context: Dictionary) -> Resource:
	var drop_level := _beacon_drop_level_from_context(context)
	var template_id := _roll_beacon_template(context)
	return _create_beacon_from_template(template_id, drop_level, context)


static func get_drop_chance(drop_kind: String, _context: Dictionary = {}) -> float:
	match drop_kind:
		"equipment":
			return EQUIPMENT_DROP_CHANCE
		"gem":
			return GEM_DROP_CHANCE
		"material":
			return MATERIAL_DROP_CHANCE
		"module":
			return MODULE_DROP_CHANCE
		_:
			return 0.0


static func _roll_equipment_drop(context: Dictionary) -> EquipmentData:
	if randf() >= get_drop_chance("equipment", context):
		return null

	var slot_weights: Array[StatTypes.EquipmentSlot] = [
		StatTypes.EquipmentSlot.MAIN_HAND,
		StatTypes.EquipmentSlot.MAIN_HAND,
		StatTypes.EquipmentSlot.OFF_HAND,
		StatTypes.EquipmentSlot.HELMET,
		StatTypes.EquipmentSlot.ARMOR,
		StatTypes.EquipmentSlot.ARMOR,
		StatTypes.EquipmentSlot.GLOVES,
		StatTypes.EquipmentSlot.BOOTS,
		StatTypes.EquipmentSlot.BELT,
		StatTypes.EquipmentSlot.AMULET,
		StatTypes.EquipmentSlot.RING_1,
	]
	var slot: StatTypes.EquipmentSlot = slot_weights[randi() % slot_weights.size()]
	var effective_level := _effective_level_from_context(context)
	return ItemGenerator.generate_random_equipment(slot, effective_level)


static func _roll_gem_drop(context: Dictionary) -> Resource:
	if randf() >= get_drop_chance("gem", context):
		return null

	var effective_level := _effective_level_from_context(context)
	var level: int = _roll_gem_drop_level(effective_level)
	return _create_random_gem(level)


static func _roll_material_drop(context: Dictionary) -> Dictionary:
	if randf() >= get_drop_chance("material", context):
		return {}

	var ids := DataManager.get_all_material_ids()
	if ids.is_empty():
		return {}

	var id: String = ids[randi() % ids.size()]
	return {
		"material_id": id,
		"amount": 1,
	}


static func _roll_module_drop(context: Dictionary) -> Module:
	if randf() >= get_drop_chance("module", context):
		return null

	var effective_level := _effective_level_from_context(context)
	var module_id: String = _pick_module_id_for_level(effective_level)
	if module_id.is_empty():
		return null
	return DataManager.create_module(module_id)


static func _create_random_gem(level: int) -> Resource:
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


static func _roll_gem_drop_level(effective_level: int) -> int:
	var min_lv := 1
	var max_lv := 2
	if effective_level >= 100:
		min_lv = 15
		max_lv = 20
	elif effective_level >= 85:
		min_lv = 12
		max_lv = 16
	elif effective_level >= 70:
		min_lv = 9
		max_lv = 13
	elif effective_level >= 55:
		min_lv = 7
		max_lv = 10
	elif effective_level >= 40:
		min_lv = 5
		max_lv = 8
	elif effective_level >= 25:
		min_lv = 3
		max_lv = 6
	elif effective_level >= 10:
		min_lv = 2
		max_lv = 4
	return clampi(randi_range(min_lv, max_lv), 1, Constants.MAX_GEM_LEVEL)


static func _pick_module_id_for_level(effective_level: int) -> String:
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


static func _target_module_load(effective_level: int) -> float:
	if effective_level >= 85:
		return 18.0
	if effective_level >= 70:
		return 15.0
	if effective_level >= 45:
		return 12.0
	if effective_level >= 20:
		return 10.0
	return 8.0


static func _effective_level_from_context(context: Dictionary) -> int:
	return clampi(int(context.get("effective_level", 1)), 1, 100)


static func _beacon_drop_level_from_context(context: Dictionary) -> int:
	var base_difficulty := clampi(int(context.get("base_difficulty", 1)), 1, 100)
	var depth := maxi(1, int(context.get("depth_index", context.get("floor", 1))))
	var danger := maxi(0, int(context.get("danger", 0)))
	var summary := _beacon_modifier_summary_from_context(context)
	var level_bonus := int(summary.get("beacon_drop_level_bonus", 0))
	return clampi(base_difficulty + depth - 1 + int(floor(float(danger) * 0.5)) + level_bonus, 1, 100)


static func _roll_beacon_template(context: Dictionary) -> String:
	var is_boss: bool = bool(context.get("enemy_is_boss", false))
	var is_elite: bool = bool(context.get("enemy_is_elite", false))
	var weighted_templates: Array[Dictionary] = []
	if is_boss:
		weighted_templates = [
			{"id": "balanced", "weight": 35},
			{"id": "deep", "weight": 40},
			{"id": "pressure", "weight": 25},
		]
	elif is_elite:
		weighted_templates = [
			{"id": "balanced", "weight": 50},
			{"id": "deep", "weight": 30},
			{"id": "pressure", "weight": 20},
		]
	else:
		weighted_templates = [
			{"id": "safe", "weight": 50},
			{"id": "balanced", "weight": 40},
			{"id": "deep", "weight": 10},
		]
	return _roll_weighted_template_id(weighted_templates)


static func _roll_weighted_template_id(weighted_templates: Array[Dictionary]) -> String:
	if weighted_templates.is_empty():
		return "balanced"

	var total_weight := 0
	for entry in weighted_templates:
		total_weight += maxi(0, int(entry.get("weight", 0)))
	if total_weight <= 0:
		return str(weighted_templates[0].get("id", "balanced"))

	var roll := randi_range(1, total_weight)
	var cursor := 0
	for entry in weighted_templates:
		cursor += maxi(0, int(entry.get("weight", 0)))
		if roll <= cursor:
			return str(entry.get("id", "balanced"))
	return str(weighted_templates[weighted_templates.size() - 1].get("id", "balanced"))


static func _create_beacon_from_template(template_id: String, drop_level: int, context: Dictionary) -> Resource:
	var beacon: Resource = ABYSS_BEACON_DATA_SCRIPT.new()
	var safe_level := clampi(drop_level, 1, 100)
	var is_boss: bool = bool(context.get("enemy_is_boss", false))
	var display_name := "Abyss Beacon"
	var base_difficulty := safe_level
	var max_depth := 8
	var lives_max := 3
	var modifier_ids := PackedStringArray()

	match template_id:
		"safe":
			display_name = "Survey Beacon"
			base_difficulty = clampi(safe_level + randi_range(-2, 0), 1, 100)
			max_depth = clampi(randi_range(5, 8), 1, 100)
			lives_max = 3
		"deep":
			display_name = "Deep Range Beacon"
			base_difficulty = clampi(safe_level + randi_range(-2, 0), 1, 100)
			max_depth = clampi(_roll_deep_beacon_depth(is_boss), 1, 100)
			lives_max = 2
			if randf() < 0.35:
				modifier_ids.append("deep_range")
		"pressure":
			display_name = "Pressure Beacon"
			base_difficulty = clampi(safe_level + randi_range(1, 3), 1, 100)
			max_depth = clampi(_roll_pressure_beacon_depth(is_boss), 1, 100)
			lives_max = randi_range(1, 2)
			modifier_ids.append(_roll_pressure_modifier_id())
		_:
			display_name = "Balanced Beacon"
			base_difficulty = clampi(safe_level + randi_range(-1, 1), 1, 100)
			max_depth = clampi(_roll_balanced_beacon_depth(is_boss), 1, 100)
			lives_max = randi_range(2, 3)
			if randf() < 0.2:
				modifier_ids.append("survey")

	if max_depth >= 12:
		lives_max = mini(lives_max, 2)
	if base_difficulty >= safe_level + 2:
		max_depth = mini(max_depth, 10)

	var unique_id := "beacon_%d_%04d" % [Time.get_ticks_usec(), randi() % 10000]
	beacon.set("id", unique_id)
	beacon.set("display_name", display_name)
	beacon.set("base_difficulty", base_difficulty)
	beacon.set("max_depth", max_depth)
	beacon.set("lives_max", lives_max)
	beacon.set("modifier_ids", modifier_ids)
	return beacon


static func _roll_pressure_modifier_id() -> String:
	var ids := [
		"pressure",
		"boss_reward",
		"deep_range",
	]
	return str(ids[randi() % ids.size()])


static func _roll_balanced_beacon_depth(is_boss: bool) -> int:
	if is_boss:
		return randi_range(12, 24)
	return randi_range(8, 14)


static func _roll_deep_beacon_depth(is_boss: bool) -> int:
	if is_boss:
		return randi_range(20, 50)
	return randi_range(14, 20)


static func _roll_pressure_beacon_depth(is_boss: bool) -> int:
	if is_boss:
		return randi_range(10, 18)
	return randi_range(6, 12)


static func _beacon_modifier_summary_from_context(context: Dictionary) -> Dictionary:
	var modifier_ids := PackedStringArray()
	var raw_modifier_ids: Variant = context.get("modifier_ids", PackedStringArray())
	if raw_modifier_ids is PackedStringArray:
		modifier_ids = raw_modifier_ids
	elif raw_modifier_ids is Array:
		for entry in raw_modifier_ids:
			modifier_ids.append(str(entry))
	return BEACON_MODIFIER_SYSTEM.summarize(modifier_ids)
