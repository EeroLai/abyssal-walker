class_name RunRecordsService
extends RefCounted

var persistent_player_state: PlayerState = PlayerState.new()
var last_run_extracted_summary: Dictionary = {}
var last_run_failed_summary: Dictionary = {}


func has_persistent_player_build() -> bool:
	return not persistent_player_state.is_empty()


func save_persistent_player_build_from_player(player: Player) -> void:
	if player == null:
		return
	if not player.can_snapshot_build():
		return
	persistent_player_state.capture_from_player(player)


func save_persistent_player_build_snapshot(snapshot: Dictionary) -> void:
	persistent_player_state.load_snapshot(snapshot)


func apply_persistent_player_build_to_player(player: Player) -> void:
	if player == null:
		return
	if not player.can_snapshot_build():
		return
	if persistent_player_state.is_empty():
		return
	persistent_player_state.apply_to_player(player)


func get_persistent_player_build_snapshot() -> Dictionary:
	return persistent_player_state.to_snapshot()


func get_persistent_player_state() -> PlayerState:
	return persistent_player_state.duplicate_state()


func record_extracted_summary(summary: Dictionary) -> void:
	last_run_extracted_summary = summary.duplicate(true)


func get_last_run_extracted_summary() -> Dictionary:
	return last_run_extracted_summary.duplicate(true)


func record_failed_summary(summary: Dictionary) -> void:
	last_run_failed_summary = summary.duplicate(true)


func get_last_run_failed_summary() -> Dictionary:
	return last_run_failed_summary.duplicate(true)
