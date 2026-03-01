class_name RunRecordsService
extends RefCounted

var persistent_player_build: Dictionary = {}
var last_run_extracted_summary: Dictionary = {}
var last_run_failed_summary: Dictionary = {}


func has_persistent_player_build() -> bool:
	return not persistent_player_build.is_empty()


func save_persistent_player_build_from_player(player: Player) -> void:
	if player == null:
		return
	if not player.can_snapshot_build():
		return
	persistent_player_build = player.capture_build_snapshot()


func save_persistent_player_build_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		persistent_player_build = {}
		return
	persistent_player_build = snapshot.duplicate(true)


func apply_persistent_player_build_to_player(player: Player) -> void:
	if player == null:
		return
	if not player.can_snapshot_build():
		return
	if persistent_player_build.is_empty():
		return
	player.apply_build_snapshot(persistent_player_build)


func get_persistent_player_build_snapshot() -> Dictionary:
	return persistent_player_build.duplicate(true)


func record_extracted_summary(summary: Dictionary) -> void:
	last_run_extracted_summary = summary.duplicate(true)


func get_last_run_extracted_summary() -> Dictionary:
	return last_run_extracted_summary.duplicate(true)


func record_failed_summary(summary: Dictionary) -> void:
	last_run_failed_summary = summary.duplicate(true)


func get_last_run_failed_summary() -> Dictionary:
	return last_run_failed_summary.duplicate(true)
