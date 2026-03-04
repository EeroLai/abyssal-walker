extends RefCounted

const UNKNOWN_MODIFIER_NAME := "Unknown Modifier"
static var _data_manager_override: Variant = null


static func summarize(modifier_ids: PackedStringArray) -> Dictionary:
	var summary := {
		"enemy_hp_mult": 1.0,
		"enemy_atk_mult": 1.0,
		"enemy_count_bonus": 0,
		"forced_elites_bonus": 0,
		"elite_chance_bonus": 0.0,
		"beacon_drop_chance_bonus": 0.0,
		"beacon_drop_level_bonus": 0,
		"boss_bonus_beacons": 0,
		"enemy_additions": [],
		"enemy_removals": [],
	}

	for modifier_id in modifier_ids:
		var id := str(modifier_id)
		var def: Dictionary = _get_modifier_data(id)
		if def.is_empty():
			continue
		summary["enemy_hp_mult"] = float(summary["enemy_hp_mult"]) * float(def.get("enemy_hp_mult", 1.0))
		summary["enemy_atk_mult"] = float(summary["enemy_atk_mult"]) * float(def.get("enemy_atk_mult", 1.0))
		summary["enemy_count_bonus"] = int(summary["enemy_count_bonus"]) + int(def.get("enemy_count_bonus", 0))
		summary["forced_elites_bonus"] = int(summary["forced_elites_bonus"]) + int(def.get("forced_elites_bonus", 0))
		summary["elite_chance_bonus"] = float(summary["elite_chance_bonus"]) + float(def.get("elite_chance_bonus", 0.0))
		summary["beacon_drop_chance_bonus"] = float(summary["beacon_drop_chance_bonus"]) + float(def.get("beacon_drop_chance_bonus", 0.0))
		summary["beacon_drop_level_bonus"] = int(summary["beacon_drop_level_bonus"]) + int(def.get("beacon_drop_level_bonus", 0))
		summary["boss_bonus_beacons"] = int(summary["boss_bonus_beacons"]) + int(def.get("boss_bonus_beacons", 0))
		_merge_unique_ids(summary["enemy_additions"], _to_string_array(def.get("enemy_additions", [])))
		_merge_unique_ids(summary["enemy_removals"], _to_string_array(def.get("enemy_removals", [])))

	return summary


static func apply_floor_config_modifiers(config: Dictionary, modifier_ids: PackedStringArray) -> Dictionary:
	var result := config.duplicate(true)
	var summary := summarize(modifier_ids)
	result["enemy_hp_multiplier"] = float(result.get("enemy_hp_multiplier", 1.0)) * float(summary["enemy_hp_mult"])
	result["enemy_atk_multiplier"] = float(result.get("enemy_atk_multiplier", 1.0)) * float(summary["enemy_atk_mult"])
	result["enemy_count"] = maxi(1, int(result.get("enemy_count", 10)) + int(summary["enemy_count_bonus"]))
	result["forced_elites"] = maxi(0, int(result.get("forced_elites", 0)) + int(summary["forced_elites_bonus"]))
	result["elite_chance_bonus"] = float(result.get("elite_chance_bonus", 0.0)) + float(summary["elite_chance_bonus"])
	result["enemies"] = _apply_enemy_pool_changes(
		result.get("enemies", []),
		summary["enemy_additions"],
		summary["enemy_removals"]
	)
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
	var data_manager: Variant = _get_data_manager()
	if data_manager == null:
		return {}
	return data_manager.get_beacon_modifier_data(modifier_id)


static func set_data_manager(data_manager: Variant) -> void:
	_data_manager_override = data_manager


static func _get_data_manager() -> Variant:
	if _data_manager_override != null:
		return _data_manager_override
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(^"/root/DataManager")


static func _to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is PackedStringArray:
		for entry in value:
			var id: String = str(entry)
			if not id.is_empty():
				result.append(id)
	elif value is Array:
		for entry in value:
			var id: String = str(entry)
			if not id.is_empty():
				result.append(id)
	return result


static func _merge_unique_ids(target_value: Variant, ids: Array[String]) -> void:
	if not (target_value is Array):
		return
	var target: Array = target_value as Array
	for id in ids:
		if not target.has(id):
			target.append(id)


static func _apply_enemy_pool_changes(base_value: Variant, additions_value: Variant, removals_value: Variant) -> Array[String]:
	var result: Array[String] = _to_string_array(base_value)
	var additions: Array[String] = _to_string_array(additions_value)
	var removals: Array[String] = _to_string_array(removals_value)

	for enemy_id in removals:
		result.erase(enemy_id)
	for enemy_id in additions:
		if not result.has(enemy_id):
			result.append(enemy_id)

	if result.is_empty():
		result.append("slime")
	return result
