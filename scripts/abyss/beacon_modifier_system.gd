extends RefCounted

const UNKNOWN_MODIFIER_NAME := "Unknown Modifier"


static func summarize(modifier_ids: PackedStringArray) -> Dictionary:
	var summary := {
		"enemy_hp_mult": 1.0,
		"enemy_atk_mult": 1.0,
		"enemy_count_bonus": 0,
		"elite_chance_bonus": 0.0,
		"beacon_drop_chance_bonus": 0.0,
		"beacon_drop_level_bonus": 0,
		"boss_bonus_beacons": 0,
	}

	for modifier_id in modifier_ids:
		var id := str(modifier_id)
		var def: Dictionary = _get_modifier_data(id)
		if def.is_empty():
			continue
		summary["enemy_hp_mult"] = float(summary["enemy_hp_mult"]) * float(def.get("enemy_hp_mult", 1.0))
		summary["enemy_atk_mult"] = float(summary["enemy_atk_mult"]) * float(def.get("enemy_atk_mult", 1.0))
		summary["enemy_count_bonus"] = int(summary["enemy_count_bonus"]) + int(def.get("enemy_count_bonus", 0))
		summary["elite_chance_bonus"] = float(summary["elite_chance_bonus"]) + float(def.get("elite_chance_bonus", 0.0))
		summary["beacon_drop_chance_bonus"] = float(summary["beacon_drop_chance_bonus"]) + float(def.get("beacon_drop_chance_bonus", 0.0))
		summary["beacon_drop_level_bonus"] = int(summary["beacon_drop_level_bonus"]) + int(def.get("beacon_drop_level_bonus", 0))
		summary["boss_bonus_beacons"] = int(summary["boss_bonus_beacons"]) + int(def.get("boss_bonus_beacons", 0))

	return summary


static func apply_floor_config_modifiers(config: Dictionary, modifier_ids: PackedStringArray) -> Dictionary:
	var result := config.duplicate(true)
	var summary := summarize(modifier_ids)
	result["enemy_hp_multiplier"] = float(result.get("enemy_hp_multiplier", 1.0)) * float(summary["enemy_hp_mult"])
	result["enemy_atk_multiplier"] = float(result.get("enemy_atk_multiplier", 1.0)) * float(summary["enemy_atk_mult"])
	result["enemy_count"] = maxi(1, int(result.get("enemy_count", 10)) + int(summary["enemy_count_bonus"]))
	result["elite_chance_bonus"] = float(result.get("elite_chance_bonus", 0.0)) + float(summary["elite_chance_bonus"])
	return result


static func get_modifier_name(modifier_id: String) -> String:
	var def: Dictionary = _get_modifier_data(modifier_id)
	if def.is_empty():
		return UNKNOWN_MODIFIER_NAME
	return str(def.get("name", modifier_id))


static func get_modifier_summary(modifier_id: String) -> String:
	var def: Dictionary = _get_modifier_data(modifier_id)
	if def.is_empty():
		return ""
	return str(def.get("summary", ""))


static func get_modifier_display_lines(modifier_ids: PackedStringArray) -> Array[String]:
	var lines: Array[String] = []
	for modifier_id in modifier_ids:
		var id := str(modifier_id)
		var name := get_modifier_name(id)
		var summary := get_modifier_summary(id)
		if summary.is_empty():
			lines.append(name)
		else:
			lines.append("%s: %s" % [name, summary])
	return lines


static func has_modifier(modifier_id: String) -> bool:
	return not _get_modifier_data(modifier_id).is_empty()


static func _get_modifier_data(modifier_id: String) -> Dictionary:
	if modifier_id.is_empty():
		return {}
	return DataManager.get_beacon_modifier_data(modifier_id)
