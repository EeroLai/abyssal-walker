extends SceneTree

const PLAYING_STATE := 1
const PAUSED_STATE := 2


class FakeLobbyPrepService:
	extends LobbyPrepService

	var stash_items_by_category: Dictionary = {
		"equipment": [],
		"skill_gems": [],
		"support_gems": [],
		"modules": [],
	}
	var loadout_items_by_category: Dictionary = {
		"equipment": [],
		"skill_gems": [],
		"support_gems": [],
		"modules": [],
	}
	var beacon_entries_data: Array = []

	func get_stash_items(category: String) -> Array:
		return (stash_items_by_category.get(category, []) as Array).duplicate(true)

	func get_loadout_items(category: String) -> Array:
		return (loadout_items_by_category.get(category, []) as Array).duplicate(true)

	func get_stash_item(category: String, item_index: int) -> Variant:
		var items: Array = get_stash_items(category)
		if item_index < 0 or item_index >= items.size():
			return null
		return items[item_index]

	func get_loadout_item(category: String, item_index: int) -> Variant:
		var items: Array = get_loadout_items(category)
		if item_index < 0 or item_index >= items.size():
			return null
		return items[item_index]

	func get_beacon_inventory_count() -> int:
		return beacon_entries_data.size()

	func get_beacon_entries() -> Array:
		return beacon_entries_data.duplicate(true)

	func get_beacon_id(beacon: Variant) -> String:
		return str((beacon as Dictionary).get("id", ""))

	func build_selected_beacon_model(raw_beacon: Variant) -> Dictionary:
		var source: Dictionary = raw_beacon as Dictionary
		var beacon := AbyssBeaconData.new()
		beacon.id = str(source.get("id", ""))
		beacon.display_name = str(source.get("display_name", "Beacon"))
		beacon.template_id = str(source.get("template_id", "baseline"))
		beacon.base_difficulty = int(source.get("base_difficulty", 1))
		beacon.max_depth = int(source.get("max_depth", 1))
		beacon.lives_max = int(source.get("lives_max", 1))
		beacon.modifier_ids = source.get("modifier_ids", PackedStringArray())
		return {
			"beacon": beacon,
			"consumable": bool(source.get("consumable", true)),
			"inventory_index": int(source.get("inventory_index", -1)),
		}


func _initialize() -> void:
	var failures: Array[String] = []
	_run_test("runtime_state", Callable(self, "_test_runtime_state"), failures)
	_run_test("command_query_integration", Callable(self, "_test_command_query_integration"), failures)
	_run_test("lobby_state", Callable(self, "_test_lobby_state"), failures)

	if failures.is_empty():
		print("SMOKE PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	print("SMOKE FAIL")
	quit(1)


func _run_test(name: String, test_callable: Callable, failures: Array[String]) -> void:
	var error_text := ""
	if test_callable.is_valid():
		error_text = str(test_callable.call())
	if error_text != "":
		failures.append("%s: %s" % [name, error_text])
		return
	print("PASS %s" % name)


func _test_runtime_state() -> String:
	var runtime := RunRuntimeService.new(0)
	runtime.start_game(PLAYING_STATE)
	if runtime.current_state != PLAYING_STATE:
		return "start_game did not enter playing state"
	if not runtime.is_in_abyss:
		return "start_game did not flag abyss state"
	if not runtime.pause_game(PLAYING_STATE, PAUSED_STATE):
		return "pause_game returned false"
	if runtime.current_state != PAUSED_STATE:
		return "pause_game did not enter paused state"
	if not runtime.resume_game(PAUSED_STATE, PLAYING_STATE):
		return "resume_game returned false"
	runtime.enter_floor(4)
	if runtime.current_floor != 4:
		return "enter_floor did not update floor"
	if runtime.complete_floor() != 4 or runtime.current_floor != 5:
		return "complete_floor did not advance floor"
	if runtime.fail_floor() != 5:
		return "fail_floor did not report current floor"
	runtime.reset_for_operation()
	if runtime.current_floor != 1:
		return "reset_for_operation did not reset floor"
	return ""


func _test_command_query_integration() -> String:
	var session := RunSessionService.new(3, 25, 0)
	var flow := RunFlowService.new(3)
	var inventory := OperationInventoryService.new()
	var records := RunRecordsService.new()
	var telemetry := RunTelemetryService.new()
	var loot_filter := LootFilterService.new()
	var command := RunCommandService.new(session, flow, inventory, records, telemetry, 0, 3, 25)
	var query := RunQueryService.new(session, flow, inventory, records, telemetry, loot_filter)

	command.ensure_starter_stash({"alter": 2})
	if query.get_stash_material_count("alter") != 2:
		return "starter stash material count mismatch"

	command.start_operation(5, 0, 2, 7, PackedStringArray(["hazard"]))
	if query.get_base_difficulty() != 5:
		return "base difficulty mismatch after start_operation"
	if query.get_lives_left() != 2 or query.get_max_depth() != 7:
		return "session values mismatch after start_operation"
	if not command.add_danger(3) or query.get_danger() != 3:
		return "danger mutation/query mismatch"
	if command.consume_life() != 1:
		return "consume_life mismatch"
	command.restore_lives()
	if query.get_lives_left() != 2:
		return "restore_lives mismatch"

	var beacon := AbyssBeaconData.new()
	beacon.id = "smoke"
	beacon.base_difficulty = 8
	beacon.max_depth = 9
	beacon.lives_max = 4
	beacon.modifier_ids = PackedStringArray(["mod_a"])
	if not command.add_beacon(beacon):
		return "add_beacon returned false"
	if query.get_beacon_inventory_count() != 1:
		return "beacon inventory count mismatch"
	var consume_result: Dictionary = command.consume_beacon(0)
	if not bool(consume_result.get("had_entry", false)):
		return "consume_beacon did not report existing entry"
	var consumed_beacon := consume_result.get("beacon", null) as AbyssBeaconData
	if consumed_beacon == null or consumed_beacon.base_difficulty != 8:
		return "consume_beacon returned unexpected resource"
	command.start_operation_from_beacon(consumed_beacon, 0)
	if query.get_base_difficulty() != 8 or query.get_max_depth() != 9 or query.get_lives_max() != 4:
		return "start_operation_from_beacon did not apply beacon values"

	command.add_loot_to_run_backpack(EquipmentData.new())
	var extraction_summary := command.close_extraction_window(3, true, null)
	var moved: Dictionary = extraction_summary.get("loot_moved", {})
	if int(moved.get("equipment", 0)) != 1:
		return "extraction summary did not move run backpack loot"
	if int(query.get_last_run_extracted_summary().get("floor", 0)) != 3:
		return "extraction summary was not recorded"

	command.record_damage_dealt({"final_damage": 50.0})
	var dps := command.advance_telemetry(1.0)
	if dps < 49.9 or dps > 50.1:
		return "telemetry dps mismatch"
	if command.record_enemy_kill() != 1:
		return "enemy kill count mismatch"
	command.advance_telemetry(1.0)
	if query.get_kills_per_minute() <= 0.0:
		return "kills per minute was not updated"
	return ""


func _test_lobby_state() -> String:
	var prep := FakeLobbyPrepService.new()
	prep.stash_items_by_category["equipment"] = [EquipmentData.new(), EquipmentData.new()]
	prep.loadout_items_by_category["modules"] = [Module.new()]
	prep.beacon_entries_data = [
		{
			"id": "baseline",
			"display_name": "Baseline",
			"template_id": "baseline",
			"base_difficulty": 1,
			"max_depth": 5,
			"lives_max": 3,
			"modifier_ids": PackedStringArray(),
			"consumable": false,
			"inventory_index": -1,
		},
		{
			"id": "beacon_alpha",
			"display_name": "Alpha",
			"template_id": "balanced",
			"base_difficulty": 6,
			"max_depth": 7,
			"lives_max": 2,
			"modifier_ids": PackedStringArray(["x"]),
			"consumable": true,
			"inventory_index": 0,
		},
	]

	var state := LobbyStateService.new()
	var stash_items := state.refresh_stash_entries("equipment", prep)
	if stash_items.size() != 2 or state.stash_entries.size() != 2:
		return "stash entries refresh mismatch"
	state.select_stash_index(1)
	if not state.has_valid_stash_selection():
		return "stash selection not retained"
	if state.get_stash_item_at(1, prep) == null:
		return "stash item lookup failed"

	var loadout_items := state.refresh_loadout_entries("modules", prep)
	if loadout_items.size() != 1 or state.loadout_entries.size() != 1:
		return "loadout entries refresh mismatch"
	state.select_loadout_index(0)
	if not state.has_valid_loadout_selection():
		return "loadout selection not retained"
	if state.get_loadout_item_at(0, prep) == null:
		return "loadout item lookup failed"

	var beacon_model := state.refresh_beacon_inventory(prep)
	if not bool(beacon_model.get("has_entries", false)):
		return "beacon inventory refresh should have entries"
	if state.selected_beacon == null or state.selected_beacon.id != "baseline":
		return "initial beacon selection mismatch"
	state.apply_beacon_selection(1, prep)
	if state.selected_beacon == null or state.selected_beacon.id != "beacon_alpha":
		return "beacon selection change mismatch"
	if not state.selected_beacon_consumes or state.selected_beacon_inventory_index != 0:
		return "selected beacon metadata mismatch"
	return ""
