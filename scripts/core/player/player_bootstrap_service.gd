class_name PlayerBootstrapService
extends RefCounted

const STARTER_BACKUP_WEAPON_IDS: Array[String] = [
	"iron_dagger",
	"short_bow",
	"apprentice_wand",
]


func setup_initial_build(
	player: Player,
	debug_grant_all_skill_gems: bool,
	debug_grant_all_support_gems: bool
) -> void:
	if player == null:
		return

	if GameManager.has_persistent_player_build():
		GameManager.apply_persistent_player_build_to_player(player)
		GameManager.apply_operation_loadout_to_player(player)
		_apply_debug_gem_grants(player, debug_grant_all_skill_gems, debug_grant_all_support_gems)
		GameManager.save_persistent_player_build_from_player(player)
		return

	var weapon: EquipmentData = ItemGenerator.generate_equipment("iron_sword", StatTypes.Rarity.WHITE, 1)
	if weapon != null:
		player.equip(weapon)
	_grant_starter_backup_weapons(player)

	for id in DataManager.get_starter_skill_gem_ids():
		var gem: SkillGem = DataManager.create_skill_gem(id)
		if gem != null:
			player.add_skill_gem_to_inventory(gem)

	for id in DataManager.get_starter_support_gem_ids():
		var support: SupportGem = DataManager.create_support_gem(id)
		if support != null:
			player.add_support_gem_to_inventory(support)

	_apply_debug_gem_grants(player, debug_grant_all_skill_gems, debug_grant_all_support_gems)

	for id in DataManager.get_starter_module_ids():
		var mod: Module = DataManager.create_module(id)
		if mod != null:
			player.add_module_to_inventory(mod)

	GameManager.apply_operation_loadout_to_player(player)
	GameManager.save_persistent_player_build_from_player(player)


func _apply_debug_gem_grants(
	player: Player,
	debug_grant_all_skill_gems: bool,
	debug_grant_all_support_gems: bool
) -> void:
	if debug_grant_all_skill_gems:
		_grant_all_skill_gems_for_testing(player)
	if debug_grant_all_support_gems:
		_grant_all_support_gems_for_testing(player)


func _grant_starter_backup_weapons(player: Player) -> void:
	for base_id in STARTER_BACKUP_WEAPON_IDS:
		var weapon: EquipmentData = ItemGenerator.generate_equipment(base_id, StatTypes.Rarity.WHITE, 1)
		if weapon != null:
			player.add_to_inventory(weapon)


func _grant_all_skill_gems_for_testing(player: Player) -> void:
	for id in DataManager.get_all_skill_gem_ids():
		if player.has_skill_gem_with_id(id):
			continue
		var gem: SkillGem = DataManager.create_skill_gem(id)
		if gem != null:
			player.add_skill_gem_to_inventory(gem)


func _grant_all_support_gems_for_testing(player: Player) -> void:
	for id in DataManager.get_all_support_gem_ids():
		if player.has_support_gem_with_id(id):
			continue
		var gem: SupportGem = DataManager.create_support_gem(id)
		if gem != null:
			player.add_support_gem_to_inventory(gem)
