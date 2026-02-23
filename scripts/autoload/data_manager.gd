extends Node

# 資料快取
var affix_data: Dictionary = {}        # id -> Affix 定義
var equipment_bases: Dictionary = {}   # id -> 基底裝備定義
var skill_gems: Dictionary = {}        # id -> SkillGem 定義
var support_gems: Dictionary = {}      # id -> SupportGem 定義
var enemy_data: Dictionary = {}        # id -> 敵人定義
var floor_data: Dictionary = {}        # floor_number -> 層數配置
var crafting_materials: Dictionary = {}  # id -> Crafting Material 定義
var modules: Dictionary = {}            # id -> Module 定義

var _is_loaded: bool = false


func _ready() -> void:
	load_all_data()


func load_all_data() -> void:
	if _is_loaded:
		return

	_load_affixes()
	_load_equipment_bases()
	_load_skill_gems()
	_load_support_gems()
	_load_crafting_materials()
	_load_modules()
	_load_enemy_data()
	_load_floor_data()

	_is_loaded = true
	print("[DataManager] All data loaded.")


func _load_affixes() -> void:
	var prefix_path := "res://data/affixes/prefixes.json"
	var suffix_path := "res://data/affixes/suffixes.json"

	var prefixes := _load_json(prefix_path)
	var suffixes := _load_json(suffix_path)

	for id in prefixes.keys():
		affix_data[id] = _parse_affix_data(id, prefixes[id], StatTypes.AffixType.PREFIX)

	for id in suffixes.keys():
		affix_data[id] = _parse_affix_data(id, suffixes[id], StatTypes.AffixType.SUFFIX)


func _load_equipment_bases() -> void:
	var weapons_path := "res://data/equipment/weapons.json"
	var armor_path := "res://data/equipment/armor.json"
	var accessories_path := "res://data/equipment/accessories.json"

	var weapons := _load_json(weapons_path)
	var armor := _load_json(armor_path)
	var accessories := _load_json(accessories_path)

	for id in weapons.keys():
		equipment_bases[id] = weapons[id]
	for id in armor.keys():
		equipment_bases[id] = armor[id]
	for id in accessories.keys():
		equipment_bases[id] = accessories[id]


func _load_skill_gems() -> void:
	var path := "res://data/gems/skill_gems.json"
	skill_gems = _load_json(path)


func _load_support_gems() -> void:
	var path := "res://data/gems/support_gems.json"
	support_gems = _load_json(path)


func _load_enemy_data() -> void:
	var path := "res://data/enemies/enemies.json"
	enemy_data = _load_json(path)


func _load_floor_data() -> void:
	var path := "res://data/abyss/floors.json"
	floor_data = _load_json(path)


func _load_crafting_materials() -> void:
	var path := "res://data/crafting/materials.json"
	crafting_materials = _load_json(path)


func _load_modules() -> void:
	var path := "res://data/modules/modules.json"
	modules = _load_json(path)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[DataManager] File not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DataManager] Failed to open: %s" % path)
		return {}

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("[DataManager] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	return json.data


func _parse_affix_data(id: String, data: Dictionary, affix_type: StatTypes.AffixType) -> Dictionary:
	return {
		"id": id,
		"display_name": data.get("display_name", id),
		"weight": float(data.get("weight", 100.0)),
		"group": data.get("group", ""),
		"affix_type": affix_type,
		"allowed_slots": data.get("allowed_slots", []),
		"tiers": data.get("tiers", []),
	}


# ===== 查詢方法 =====

func get_affix(id: String) -> Dictionary:
	return affix_data.get(id, {})


func get_affixes_for_slot(slot: StatTypes.EquipmentSlot, affix_type: StatTypes.AffixType) -> Array:
	var result: Array = []
	var slot_name := _slot_to_string(slot)

	for id in affix_data.keys():
		var affix: Dictionary = affix_data[id]
		if affix.affix_type != affix_type:
			continue

		var allowed: Array = affix.allowed_slots
		if allowed.is_empty() or slot_name in allowed:
			result.append(affix)

	return result


func get_equipment_base(id: String) -> Dictionary:
	return equipment_bases.get(id, {})


func get_skill_gem_data(id: String) -> Dictionary:
	return skill_gems.get(id, {})


func get_support_gem_data(id: String) -> Dictionary:
	return support_gems.get(id, {})


func get_starter_skill_gem_ids() -> Array[String]:
	var result: Array[String] = []
	for id in skill_gems.keys():
		var data: Dictionary = skill_gems[id]
		if data.get("is_starter", false):
			result.append(id)
	return result


func get_starter_support_gem_ids() -> Array[String]:
	var result: Array[String] = []
	for id in support_gems.keys():
		var data: Dictionary = support_gems[id]
		if data.get("is_starter", false):
			result.append(id)
	return result


func get_all_skill_gem_ids() -> Array[String]:
	var result: Array[String] = []
	for id in skill_gems.keys():
		result.append(id)
	return result


func get_all_support_gem_ids() -> Array[String]:
	var result: Array[String] = []
	for id in support_gems.keys():
		result.append(id)
	return result


func create_skill_gem(id: String) -> SkillGem:
	var data: Dictionary = get_skill_gem_data(id)
	if data.is_empty():
		return null

	var gem := SkillGem.new()
	gem.id = id
	gem.display_name = data.get("display_name", id)
	gem.description = data.get("description", "")
	gem.base_damage_multiplier = float(data.get("base_damage_multiplier", 1.0))
	gem.base_range = float(data.get("base_range", 50.0))
	gem.base_cooldown = float(data.get("base_cooldown", 0.0))
	gem.projectile_speed = float(data.get("projectile_speed", 450.0))
	gem.explosion_radius = float(data.get("explosion_radius", 0.0))
	gem.pierce_count = int(data.get("pierce_count", 0))
	gem.chain_count = int(data.get("chain_count", 0))
	gem.hit_count = maxi(1, int(data.get("hit_count", 1)))
	gem.arrow_count = maxi(1, int(data.get("arrow_count", 1)))
	gem.conversion_element = _element_from_string(str(data.get("conversion_element", "physical")))
	gem.conversion_ratio = clampf(float(data.get("conversion_ratio", 0.0)), 0.0, 1.0)
	gem.element_status_chance_bonus = maxf(float(data.get("element_status_chance_bonus", 0.0)), 0.0)
	gem.weapon_restrictions = _parse_weapon_restrictions(data.get("weapon_restrictions", []))
	gem.tags = _parse_skill_tags(data.get("tags", []))
	return gem


func create_support_gem(id: String) -> SupportGem:
	var data: Dictionary = get_support_gem_data(id)
	if data.is_empty():
		return null

	var gem := SupportGem.new()
	gem.id = id
	gem.display_name = data.get("display_name", id)
	gem.description = data.get("description", "")
	gem.tag_restrictions = _parse_skill_tags(data.get("tag_restrictions", []))
	gem.modifiers = data.get("modifiers", {})
	return gem


func _parse_weapon_restrictions(list: Array) -> Array[StatTypes.WeaponType]:
	var result: Array[StatTypes.WeaponType] = []
	for value in list:
		var weapon: int = _weapon_type_from_string(str(value))
		if weapon != -1:
			result.append(weapon)
	return result


func _parse_skill_tags(list: Array) -> Array[StatTypes.SkillTag]:
	var result: Array[StatTypes.SkillTag] = []
	for value in list:
		var tag: int = _skill_tag_from_string(str(value))
		if tag != -1:
			result.append(tag)
	return result


func _weapon_type_from_string(value: String) -> int:
	match value:
		"sword": return StatTypes.WeaponType.SWORD
		"dagger": return StatTypes.WeaponType.DAGGER
		"bow": return StatTypes.WeaponType.BOW
		"wand": return StatTypes.WeaponType.WAND
		_: return -1


func _skill_tag_from_string(value: String) -> int:
	match value:
		"melee": return StatTypes.SkillTag.MELEE
		"ranged": return StatTypes.SkillTag.RANGED
		"projectile": return StatTypes.SkillTag.PROJECTILE
		"aoe": return StatTypes.SkillTag.AOE
		"fast": return StatTypes.SkillTag.FAST
		"heavy": return StatTypes.SkillTag.HEAVY
		"tracking": return StatTypes.SkillTag.TRACKING
		_: return -1


func _element_from_string(value: String) -> StatTypes.Element:
	match value.to_lower():
		"physical": return StatTypes.Element.PHYSICAL
		"fire": return StatTypes.Element.FIRE
		"ice": return StatTypes.Element.ICE
		"lightning": return StatTypes.Element.LIGHTNING
		_: return StatTypes.Element.PHYSICAL


func get_enemy(id: String) -> Dictionary:
	return enemy_data.get(id, {})


func get_floor_config(floor_number: int) -> Dictionary:
	var target_floor := maxi(1, floor_number)
	var default_cfg: Dictionary = floor_data.get("default", {})
	var result: Dictionary = default_cfg.duplicate(true)

	# 找到不大於目標樓層的最近錨點設定（1/5/10/15...）
	var anchor_floor := 0
	var anchor_cfg: Dictionary = {}
	for key in floor_data.keys():
		var key_str := str(key)
		if key_str == "default" or not key_str.is_valid_int():
			continue
		var n := int(key_str)
		if n <= target_floor and n >= anchor_floor:
			anchor_floor = n
			anchor_cfg = floor_data[key_str]

	# 先套用錨點設定（覆蓋 default）
	for k in anchor_cfg.keys():
		result[k] = anchor_cfg[k]

	# 錨點之間的每層成長
	var delta := maxi(0, target_floor - anchor_floor)
	if delta > 0:
		var hp_mult := float(result.get("enemy_hp_multiplier", 1.0))
		var atk_mult := float(result.get("enemy_atk_multiplier", 1.0))
		var exp_mult := float(result.get("experience_multiplier", 1.0))
		var drop_mult := float(result.get("drop_rate_multiplier", 1.0))
		var enemy_count := int(result.get("enemy_count", 10))

		# 難度主軸：血量、攻擊與怪數都會逐層上升
		hp_mult = minf(hp_mult * pow(1.045, delta), 30.0)
		atk_mult = minf(atk_mult * pow(1.03, delta), 20.0)
		enemy_count = clampi(enemy_count + int(delta / 2), 6, 48)

		# 配套倍率（避免後期收益過低）
		exp_mult = minf(exp_mult * pow(1.02, delta), 10.0)
		drop_mult = minf(drop_mult * pow(1.01, delta), 3.0)

		result["enemy_hp_multiplier"] = hp_mult
		result["enemy_atk_multiplier"] = atk_mult
		result["enemy_count"] = enemy_count
		result["experience_multiplier"] = exp_mult
		result["drop_rate_multiplier"] = drop_mult

	# boss 只在明確定義的樓層出現，避免錨點外溢
	if str(target_floor) != str(anchor_floor):
		result.erase("boss")

	return result


func get_crafting_material(id: String) -> Dictionary:
	return crafting_materials.get(id, {})


func get_all_material_ids() -> Array[String]:
	var result: Array[String] = []
	for id in crafting_materials.keys():
		result.append(id)
	return result


func get_module_data(id: String) -> Dictionary:
	return modules.get(id, {})


func get_all_module_ids() -> Array[String]:
	var result: Array[String] = []
	for id in modules.keys():
		result.append(id)
	return result


func get_starter_module_ids() -> Array[String]:
	var result: Array[String] = []
	for id in modules.keys():
		if modules[id].get("is_starter", false):
			result.append(id)
	return result


func create_module(id: String) -> Module:
	var data: Dictionary = get_module_data(id)
	if data.is_empty():
		return null

	var mod := Module.new()
	mod.id = id
	mod.display_name = data.get("display_name", id)
	mod.description = data.get("description", "")
	mod.load_cost = int(data.get("load_cost", 0))
	mod.is_starter = bool(data.get("is_starter", false))
	mod.module_type = _parse_module_type(str(data.get("module_type", "attack")))

	var stats_list: Array = data.get("stats", [])
	for entry in stats_list:
		var stat_mod := StatModifier.new()
		stat_mod.stat = _stat_from_string(str(entry.get("stat", "")))
		stat_mod.modifier_type = _modifier_type_from_string(str(entry.get("type", "flat")))
		stat_mod.value = float(entry.get("value", 0.0))
		mod.modifiers.append(stat_mod)

	return mod


func _parse_module_type(value: String) -> Module.ModuleType:
	match value:
		"attack":  return Module.ModuleType.ATTACK
		"defense": return Module.ModuleType.DEFENSE
		"utility": return Module.ModuleType.UTILITY
		"special": return Module.ModuleType.SPECIAL
	return Module.ModuleType.ATTACK


func _stat_from_string(value: String) -> StatTypes.Stat:
	match value:
		"hp":                    return StatTypes.Stat.HP
		"atk":                   return StatTypes.Stat.ATK
		"atk_speed":             return StatTypes.Stat.ATK_SPEED
		"move_speed":            return StatTypes.Stat.MOVE_SPEED
		"def":                   return StatTypes.Stat.DEF
		"crit_rate":             return StatTypes.Stat.CRIT_RATE
		"crit_dmg":              return StatTypes.Stat.CRIT_DMG
		"final_dmg":             return StatTypes.Stat.FINAL_DMG
		"phys_pen":              return StatTypes.Stat.PHYS_PEN
		"elemental_pen":         return StatTypes.Stat.ELEMENTAL_PEN
		"armor_shred":           return StatTypes.Stat.ARMOR_SHRED
		"res_shred":             return StatTypes.Stat.RES_SHRED
		"life_steal":            return StatTypes.Stat.LIFE_STEAL
		"life_regen":            return StatTypes.Stat.LIFE_REGEN
		"dodge":                 return StatTypes.Stat.DODGE
		"block_rate":            return StatTypes.Stat.BLOCK_RATE
		"block_reduction":       return StatTypes.Stat.BLOCK_REDUCTION
		"physical_dmg":          return StatTypes.Stat.PHYSICAL_DMG
		"fire_dmg":              return StatTypes.Stat.FIRE_DMG
		"ice_dmg":               return StatTypes.Stat.ICE_DMG
		"lightning_dmg":         return StatTypes.Stat.LIGHTNING_DMG
		"fire_res":              return StatTypes.Stat.FIRE_RES
		"ice_res":               return StatTypes.Stat.ICE_RES
		"lightning_res":         return StatTypes.Stat.LIGHTNING_RES
		"all_res":               return StatTypes.Stat.ALL_RES
		"burn_chance":           return StatTypes.Stat.BURN_CHANCE
		"freeze_chance":         return StatTypes.Stat.FREEZE_CHANCE
		"shock_chance":          return StatTypes.Stat.SHOCK_CHANCE
		"bleed_chance":          return StatTypes.Stat.BLEED_CHANCE
		"burn_dmg":              return StatTypes.Stat.BURN_DMG_BONUS
		"freeze_duration":       return StatTypes.Stat.FREEZE_DURATION_BONUS
		"shock_effect":          return StatTypes.Stat.SHOCK_EFFECT_BONUS
		"bleed_dmg":             return StatTypes.Stat.BLEED_DMG_BONUS
		"drop_rate":             return StatTypes.Stat.DROP_RATE
		"drop_quality":          return StatTypes.Stat.DROP_QUALITY
		"pickup_range":          return StatTypes.Stat.PICKUP_RANGE
	push_warning("[DataManager] Unknown stat string: %s" % value)
	return StatTypes.Stat.HP


func _modifier_type_from_string(value: String) -> StatModifier.ModifierType:
	match value:
		"flat":    return StatModifier.ModifierType.FLAT
		"percent": return StatModifier.ModifierType.PERCENT
	return StatModifier.ModifierType.FLAT


func _slot_to_string(slot: StatTypes.EquipmentSlot) -> String:
	match slot:
		StatTypes.EquipmentSlot.MAIN_HAND: return "main_hand"
		StatTypes.EquipmentSlot.OFF_HAND: return "off_hand"
		StatTypes.EquipmentSlot.HELMET: return "helmet"
		StatTypes.EquipmentSlot.ARMOR: return "armor"
		StatTypes.EquipmentSlot.GLOVES: return "gloves"
		StatTypes.EquipmentSlot.BOOTS: return "boots"
		StatTypes.EquipmentSlot.BELT: return "belt"
		StatTypes.EquipmentSlot.AMULET: return "amulet"
		StatTypes.EquipmentSlot.RING_1: return "ring_1"
		StatTypes.EquipmentSlot.RING_2: return "ring_2"
		_: return "unknown"
