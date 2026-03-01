class_name LobbyViewBinder
extends RefCounted


func apply_summary(
	stash_total_label: Label,
	stash_material_list: RichTextLabel,
	stash_loot_total_label: Label,
	loadout_total_label: Label,
	model: Dictionary
) -> void:
	if stash_total_label != null:
		stash_total_label.text = "Crafting Materials: %d" % int(model.get("stash_material_total", 0))
	if stash_material_list != null:
		stash_material_list.text = "\n".join(model.get("material_lines", []))

	var stash_counts: Dictionary = model.get("stash_counts", {})
	var loadout_counts: Dictionary = model.get("loadout_counts", {})
	if stash_loot_total_label != null:
		stash_loot_total_label.text = "Stash Loot: Eq %d | Skill %d | Support %d | Module %d" % [
			int(stash_counts.get("equipment", 0)),
			int(stash_counts.get("skill_gems", 0)),
			int(stash_counts.get("support_gems", 0)),
			int(stash_counts.get("modules", 0)),
		]
	if loadout_total_label != null:
		loadout_total_label.text = "Loadout: Eq %d | Skill %d | Support %d | Module %d" % [
			int(loadout_counts.get("equipment", 0)),
			int(loadout_counts.get("skill_gems", 0)),
			int(loadout_counts.get("support_gems", 0)),
			int(loadout_counts.get("modules", 0)),
		]


func apply_beacon_inventory_count(label: Label, inventory_count: int) -> void:
	if label == null:
		return
	label.text = "Owned Beacons: %d" % inventory_count
	if inventory_count == 0:
		label.text += "  |  Baseline Ready"


func apply_beacon_preview(label: Label, preview_text: String) -> void:
	if label != null:
		label.text = preview_text


func apply_start_button(button: Button, has_selected_beacon: bool, beacon_consumes: bool) -> void:
	if button == null:
		return
	button.disabled = not has_selected_beacon
	button.text = "Activate Beacon" if beacon_consumes else "Start Baseline Dive"
