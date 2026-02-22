extends Node

const SAVE_DIR := "user://saves/"
const SAVE_FILE := "save_%d.json"
const MAX_SAVE_SLOTS := 3

var current_slot: int = 0


func _ready() -> void:
	_ensure_save_directory()


func _ensure_save_directory() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("saves"):
		dir.make_dir("saves")


func save_game(slot: int = -1) -> bool:
	if slot < 0:
		slot = current_slot

	var save_data := _collect_save_data()
	var json_string := JSON.stringify(save_data, "\t")

	var path := SAVE_DIR + SAVE_FILE % slot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Failed to create save file: %s" % path)
		return false

	file.store_string(json_string)
	file.close()

	EventBus.game_saved.emit()
	print("[SaveManager] Game saved to slot %d" % slot)
	return true


func load_game(slot: int = -1) -> bool:
	if slot < 0:
		slot = current_slot

	var path := SAVE_DIR + SAVE_FILE % slot
	if not FileAccess.file_exists(path):
		push_warning("[SaveManager] Save file not found: %s" % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveManager] Failed to open save file: %s" % path)
		return false

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("[SaveManager] Failed to parse save file: %s" % json.get_error_message())
		return false

	var save_data: Dictionary = json.data
	_apply_save_data(save_data)

	current_slot = slot
	EventBus.game_loaded.emit()
	print("[SaveManager] Game loaded from slot %d" % slot)
	return true


func has_save(slot: int) -> bool:
	var path := SAVE_DIR + SAVE_FILE % slot
	return FileAccess.file_exists(path)


func delete_save(slot: int) -> bool:
	var path := SAVE_DIR + SAVE_FILE % slot
	if not FileAccess.file_exists(path):
		return false

	var dir := DirAccess.open(SAVE_DIR)
	if dir:
		dir.remove(SAVE_FILE % slot)
		return true
	return false


func get_save_info(slot: int) -> Dictionary:
	var path := SAVE_DIR + SAVE_FILE % slot
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		return {}

	var data: Dictionary = json.data
	return {
		"floor": data.get("current_floor", 1),
		"playtime": data.get("total_playtime", 0.0),
		"timestamp": data.get("save_timestamp", ""),
	}


func _collect_save_data() -> Dictionary:
	var data: Dictionary = {
		"version": 1,
		"save_timestamp": Time.get_datetime_string_from_system(),
		"current_floor": GameManager.current_floor,
		"total_playtime": GameManager.session_stats.time_played,
		"session_stats": GameManager.session_stats.duplicate(),
		# TODO: 裝備、寶石、模組、材料等資料
		"equipment": {},
		"gem_link": {},
		"inventory": [],
		"materials": {},
	}
	return data


func _apply_save_data(data: Dictionary) -> void:
	var version: int = data.get("version", 1)

	GameManager.current_floor = data.get("current_floor", 1)
	GameManager.session_stats = data.get("session_stats", {})

	# TODO: 還原裝備、寶石、模組、材料等
	pass
