class_name HUD
extends Control

signal challenge_failed_floor_requested
signal run_summary_confirmed

@onready var floor_label: Label = $FloorLabel
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_label: Label = $HPBar/HPLabel
@onready var dps_label: Label = $DPSLabel
@onready var kills_label: Label = $KillsLabel
@onready var enemy_count_label: Label = $EnemyCountLabel
@onready var inventory_label: Label = $InventoryLabel
@onready var status_icons: HBoxContainer = $StatusIcons

var kills: int = 0
var active_status_nodes: Dictionary = {}
var pickup_feed: VBoxContainer = null
var _pickup_entries: Array[Dictionary] = []
var _pickup_labels: Array[Label] = []
var loot_filter_label: Label = null
var operation_label: Label = null
var extraction_prompt_panel: PanelContainer = null
var extraction_prompt_label: Label = null
var run_summary_panel: PanelContainer = null
var run_summary_title: Label = null
var run_summary_body: RichTextLabel = null
var progression_mode_label: Label = null
var progression_primary_label: Label = null
var progression_secondary_label: Label = null
var progression_buttons: HBoxContainer = null
var progression_panel: PanelContainer = null
var damage_vignette: Panel = null
var _last_hp_value: float = -1.0
var _damage_vignette_tween: Tween = null

const PICKUP_FEED_MAX: int = 6
const PICKUP_SHOW_TIME: float = 2.6
const PICKUP_FADE_TIME: float = 0.35


func _ready() -> void:
	_create_pickup_feed()
	_create_loot_filter_label()
	_create_operation_label()
	_create_extraction_prompt_label()
	_create_run_summary_panel()
	_create_progression_labels()
	_create_damage_vignette()
	_refresh_loot_filter_label()
	_on_operation_session_changed(GameManager.get_operation_summary())
	_connect_signals()


func _process(_delta: float) -> void:
	_refresh_pickup_feed()


func _connect_signals() -> void:
	EventBus.player_health_changed.connect(_on_player_health_changed)
	EventBus.dps_updated.connect(_on_dps_updated)
	EventBus.kill_count_changed.connect(_on_kill_count_changed)
	EventBus.floor_entered.connect(_on_floor_entered)
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.status_applied.connect(_on_status_applied)
	EventBus.status_removed.connect(_on_status_removed)
	EventBus.loot_filter_changed.connect(_on_loot_filter_changed)
	EventBus.notification_requested.connect(_on_notification_requested)
	EventBus.operation_session_changed.connect(_on_operation_session_changed)
	EventBus.extraction_window_opened.connect(_on_extraction_window_opened)
	EventBus.extraction_window_closed.connect(_on_extraction_window_closed)
	EventBus.run_extracted.connect(_on_run_extracted)
	EventBus.run_failed.connect(_on_run_failed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if is_run_summary_visible() and key_event.keycode == KEY_E:
			run_summary_confirmed.emit()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_L:
			GameManager.cycle_loot_filter_mode()
			get_viewport().set_input_as_handled()


func _on_player_health_changed(current: float, max_hp: float) -> void:
	if _last_hp_value >= 0.0 and current < _last_hp_value and max_hp > 0.0:
		var ratio := clampf((_last_hp_value - current) / max_hp, 0.0, 1.0)
		_play_damage_vignette(ratio)
	_last_hp_value = current

	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current

	if hp_label:
		hp_label.text = "%d / %d" % [int(current), int(max_hp)]


func _on_dps_updated(dps: float) -> void:
	if dps_label:
		if dps >= 1000:
			dps_label.text = "DPS: %.1fK" % (dps / 1000.0)
		else:
			dps_label.text = "DPS: %.0f" % dps


func _on_kill_count_changed(count: int) -> void:
	kills = count
	if kills_label:
		kills_label.text = "擊殺: %d" % kills


func _on_floor_entered(floor_number: int) -> void:
	update_floor(floor_number)


func update_floor(floor_number: int) -> void:
	if floor_label:
		floor_label.text = "深淵 %d 層" % floor_number


func set_progression_status(text: String) -> void:
	if progression_primary_label == null:
		return
	progression_primary_label.text = text


func set_progression_display(mode_text: String, primary_text: String, secondary_text: String) -> void:
	if progression_mode_label:
		progression_mode_label.text = mode_text
	if progression_primary_label:
		progression_primary_label.text = primary_text
	if progression_secondary_label:
		progression_secondary_label.text = secondary_text


func set_floor_choice_visible(is_visible: bool) -> void:
	if progression_panel == null:
		return
	progression_panel.visible = is_visible


func update_enemy_count(count: int) -> void:
	if enemy_count_label:
		enemy_count_label.text = "敵人: %d" % count


func _on_item_picked_up(_item_data: Variant) -> void:
	var game := get_tree().current_scene
	if game and "player" in game and game.player:
		var player: Player = game.player
		update_inventory(player.get_inventory_size())

	_show_pickup_message(_item_data)


func update_inventory(count: int) -> void:
	if inventory_label:
		inventory_label.text = "背包: %d/60" % count


func _on_status_applied(target: Node, status_type: String, stacks: int) -> void:
	var game := get_tree().current_scene
	if game == null or not ("player" in game):
		return
	if target != game.player:
		return
	_add_status_icon(status_type, stacks)


func _on_status_removed(target: Node, status_type: String) -> void:
	var game := get_tree().current_scene
	if game == null or not ("player" in game):
		return
	if target != game.player:
		return
	_remove_status_icon(status_type)


func _add_status_icon(status_type: String, stacks: int) -> void:
	if status_icons == null:
		return

	if active_status_nodes.has(status_type):
		var existing: Control = active_status_nodes[status_type]
		var label: Label = existing.get_node("Label") if existing.has_node("Label") else null
		if label:
			label.text = _status_short_name(status_type)
		return

	var box: PanelContainer = PanelContainer.new()
	box.custom_minimum_size = Vector2(24, 24)

	var style := StyleBoxFlat.new()
	style.bg_color = _status_color(status_type)
	style.border_color = Color(0, 0, 0, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	box.add_theme_stylebox_override("panel", style)

	var label: Label = Label.new()
	label.name = "Label"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = _status_short_name(status_type)
	label.custom_minimum_size = Vector2(24, 24)
	box.add_child(label)

	status_icons.add_child(box)
	active_status_nodes[status_type] = box


func _remove_status_icon(status_type: String) -> void:
	if not active_status_nodes.has(status_type):
		return
	var node: Control = active_status_nodes[status_type]
	active_status_nodes.erase(status_type)
	node.queue_free()


func _status_short_name(status_type: String) -> String:
	match status_type:
		"burn": return "B"
		"freeze": return "F"
		"shock": return "S"
		"bleed": return "BL"
		_: return "-"


func _status_color(status_type: String) -> Color:
	match status_type:
		"burn": return Color(1.0, 0.4, 0.2, 0.9)
		"freeze": return Color(0.4, 0.8, 1.0, 0.9)
		"shock": return Color(0.9, 0.9, 0.2, 0.9)
		"bleed": return Color(0.8, 0.2, 0.2, 0.9)
		_: return Color(0.5, 0.5, 0.5, 0.9)


func _create_pickup_feed() -> void:
	pickup_feed = VBoxContainer.new()
	pickup_feed.name = "PickupFeed"
	pickup_feed.anchor_left = 1.0
	pickup_feed.anchor_top = 1.0
	pickup_feed.anchor_right = 1.0
	pickup_feed.anchor_bottom = 1.0
	pickup_feed.offset_left = -420.0
	pickup_feed.offset_top = -260.0
	pickup_feed.offset_right = -20.0
	pickup_feed.offset_bottom = -70.0
	pickup_feed.alignment = BoxContainer.ALIGNMENT_END
	pickup_feed.add_theme_constant_override("separation", 4)
	add_child(pickup_feed)

	_pickup_labels.clear()
	for i in range(PICKUP_FEED_MAX):
		var label := Label.new()
		label.visible = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		pickup_feed.add_child(label)
		_pickup_labels.append(label)


func _create_damage_vignette() -> void:
	damage_vignette = Panel.new()
	damage_vignette.name = "DamageVignette"
	damage_vignette.anchor_left = 0.0
	damage_vignette.anchor_top = 0.0
	damage_vignette.anchor_right = 1.0
	damage_vignette.anchor_bottom = 1.0
	damage_vignette.offset_left = 0.0
	damage_vignette.offset_top = 0.0
	damage_vignette.offset_right = 0.0
	damage_vignette.offset_bottom = 0.0
	damage_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_vignette.modulate = Color(1, 1, 1, 0.0)
	damage_vignette.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.45, 0.0, 0.0, 0.16)
	style.border_color = Color(1.0, 0.1, 0.1, 0.95)
	style.set_border_width_all(34)
	damage_vignette.add_theme_stylebox_override("panel", style)
	add_child(damage_vignette)


func _play_damage_vignette(ratio: float) -> void:
	if damage_vignette == null:
		return
	if _damage_vignette_tween != null and _damage_vignette_tween.is_valid():
		_damage_vignette_tween.kill()

	var peak := clampf(0.2 + ratio * 0.75, 0.2, 0.85)
	_damage_vignette_tween = create_tween()
	_damage_vignette_tween.tween_property(damage_vignette, "modulate:a", peak, 0.05)
	_damage_vignette_tween.tween_property(damage_vignette, "modulate:a", 0.0, 0.22)


func _create_loot_filter_label() -> void:
	loot_filter_label = Label.new()
	loot_filter_label.name = "LootFilterLabel"
	loot_filter_label.anchor_left = 1.0
	loot_filter_label.anchor_top = 0.0
	loot_filter_label.anchor_right = 1.0
	loot_filter_label.anchor_bottom = 0.0
	loot_filter_label.offset_left = -330.0
	loot_filter_label.offset_top = 36.0
	loot_filter_label.offset_right = -20.0
	loot_filter_label.offset_bottom = 58.0
	loot_filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	loot_filter_label.add_theme_font_size_override("font_size", 13)
	loot_filter_label.modulate = Color(0.9, 0.95, 1.0, 0.9)
	add_child(loot_filter_label)


func _create_operation_label() -> void:
	operation_label = Label.new()
	operation_label.name = "OperationLabel"
	operation_label.anchor_left = 1.0
	operation_label.anchor_top = 0.0
	operation_label.anchor_right = 1.0
	operation_label.anchor_bottom = 0.0
	operation_label.offset_left = -330.0
	operation_label.offset_top = 58.0
	operation_label.offset_right = -20.0
	operation_label.offset_bottom = 80.0
	operation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	operation_label.add_theme_font_size_override("font_size", 13)
	operation_label.modulate = Color(0.72, 0.95, 1.0, 0.95)
	add_child(operation_label)


func _create_extraction_prompt_label() -> void:
	extraction_prompt_panel = PanelContainer.new()
	extraction_prompt_panel.name = "ExtractionPromptPanel"
	extraction_prompt_panel.anchor_left = 0.5
	extraction_prompt_panel.anchor_top = 0.0
	extraction_prompt_panel.anchor_right = 0.5
	extraction_prompt_panel.anchor_bottom = 0.0
	extraction_prompt_panel.offset_left = -150.0
	extraction_prompt_panel.offset_top = 56.0
	extraction_prompt_panel.offset_right = 150.0
	extraction_prompt_panel.offset_bottom = 140.0
	extraction_prompt_panel.visible = false
	add_child(extraction_prompt_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.08, 0.06, 0.92)
	style.border_color = Color(1.0, 0.64, 0.3, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	extraction_prompt_panel.add_theme_stylebox_override("panel", style)

	extraction_prompt_label = Label.new()
	extraction_prompt_label.name = "ExtractionPromptLabel"
	extraction_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extraction_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	extraction_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	extraction_prompt_label.add_theme_font_size_override("font_size", 14)
	extraction_prompt_label.modulate = Color(1.0, 0.95, 0.82, 1.0)
	extraction_prompt_panel.add_child(extraction_prompt_label)


func _create_run_summary_panel() -> void:
	run_summary_panel = PanelContainer.new()
	run_summary_panel.name = "RunSummaryPanel"
	run_summary_panel.anchor_left = 0.5
	run_summary_panel.anchor_top = 0.5
	run_summary_panel.anchor_right = 0.5
	run_summary_panel.anchor_bottom = 0.5
	run_summary_panel.offset_left = -240.0
	run_summary_panel.offset_top = -140.0
	run_summary_panel.offset_right = 240.0
	run_summary_panel.offset_bottom = 140.0
	run_summary_panel.visible = false
	run_summary_panel.z_index = 120
	add_child(run_summary_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.border_color = Color(0.92, 0.64, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	run_summary_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	run_summary_panel.add_child(vbox)

	run_summary_title = Label.new()
	run_summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	run_summary_title.add_theme_font_size_override("font_size", 18)
	run_summary_title.text = "Run Summary"
	vbox.add_child(run_summary_title)

	run_summary_body = RichTextLabel.new()
	run_summary_body.fit_content = false
	run_summary_body.scroll_active = true
	run_summary_body.custom_minimum_size = Vector2(0, 170)
	run_summary_body.bbcode_enabled = false
	run_summary_body.text = ""
	vbox.add_child(run_summary_body)

	var footer := Label.new()
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.modulate = Color(0.95, 0.85, 0.65, 1.0)
	footer.text = "Press [E] to return to Lobby"
	vbox.add_child(footer)


func _create_progression_labels() -> void:
	progression_panel = PanelContainer.new()
	progression_panel.name = "ProgressionPanel"
	progression_panel.anchor_left = 1.0
	progression_panel.anchor_top = 0.0
	progression_panel.anchor_right = 1.0
	progression_panel.anchor_bottom = 0.0
	progression_panel.offset_left = -266.0
	progression_panel.offset_top = 104.0
	progression_panel.offset_right = -16.0
	progression_panel.offset_bottom = 170.0
	add_child(progression_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.12, 0.72)
	style.border_color = Color(0.28, 0.36, 0.5, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	progression_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	progression_panel.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)

	progression_mode_label = Label.new()
	progression_mode_label.name = "ProgressionModeLabel"
	progression_mode_label.text = "模式: 推進"
	progression_mode_label.add_theme_font_size_override("font_size", 12)
	progression_mode_label.modulate = Color(0.9, 0.84, 0.58, 0.98)
	top_row.add_child(progression_mode_label)

	progression_primary_label = Label.new()
	progression_primary_label.name = "ProgressionPrimaryLabel"
	progression_primary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	progression_primary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progression_primary_label.add_theme_font_size_override("font_size", 12)
	progression_primary_label.modulate = Color(0.94, 0.97, 1.0, 0.96)
	vbox.add_child(progression_primary_label)

	progression_secondary_label = Label.new()
	progression_secondary_label.name = "ProgressionSecondaryLabel"
	progression_secondary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	progression_secondary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progression_secondary_label.add_theme_font_size_override("font_size", 11)
	progression_secondary_label.modulate = Color(0.7, 0.8, 0.92, 0.9)
	vbox.add_child(progression_secondary_label)

	progression_buttons = HBoxContainer.new()
	progression_buttons.name = "ProgressionButtons"
	progression_buttons.alignment = BoxContainer.ALIGNMENT_END
	progression_buttons.add_theme_constant_override("separation", 6)
	vbox.add_child(progression_buttons)

	var btn_retry := Button.new()
	btn_retry.text = "挑戰失敗層"
	btn_retry.custom_minimum_size = Vector2(108, 22)
	btn_retry.pressed.connect(func() -> void: challenge_failed_floor_requested.emit())
	progression_buttons.add_child(btn_retry)


func _on_loot_filter_changed(_mode: int) -> void:
	_refresh_loot_filter_label()


func _on_operation_session_changed(summary: Dictionary) -> void:
	if operation_label == null:
		return
	var base_difficulty: int = int(summary.get("base_difficulty", summary.get("operation_level", 1)))
	var max_depth: int = int(summary.get("max_depth", 0))
	var danger: int = int(summary.get("danger", 0))
	var lives_left: int = int(summary.get("lives_left", 0))
	var lives_max: int = int(summary.get("lives_max", 0))
	operation_label.text = "Base Lv %d  Cap %d  Danger %d  Lives %d/%d" % [
		base_difficulty,
		max_depth,
		danger,
		lives_left,
		lives_max,
	]


func _on_extraction_window_opened(_floor_number: int, timeout_sec: float) -> void:
	set_extraction_prompt(true, "[E] 撤離   [F] 繼續\n剩餘 %d 秒" % int(timeout_sec))


func _on_extraction_window_closed(_floor_number: int, _extracted: bool) -> void:
	set_extraction_prompt(false, "")


func _on_run_extracted(summary: Dictionary) -> void:
	var floor: int = int(summary.get("floor", 0))
	var stash_total: int = int(summary.get("stash_total", 0))
	var moved: Dictionary = summary.get("loot_moved", {})
	var moved_equipment: int = int(moved.get("equipment", 0))
	var moved_gems: int = int(moved.get("total_gems", 0))
	var moved_modules: int = int(moved.get("modules", 0))
	_add_feed_entry(
		"run_extracted",
		"成功撤離：深淵 %d 層，入庫 裝%d/寶石%d/模組%d，材料倉庫 %d" % [
			floor,
			moved_equipment,
			moved_gems,
			moved_modules,
			stash_total,
		],
		1,
		Color(0.7, 1.0, 0.72)
	)


func _on_run_failed(summary: Dictionary) -> void:
	var lost: int = int(summary.get("lost", 0))
	var kept: int = int(summary.get("kept", 0))
	var lost_loot: Dictionary = summary.get("loot_lost", {})
	var lost_equipment: int = int(lost_loot.get("equipment", 0))
	var lost_gems: int = int(lost_loot.get("total_gems", 0))
	var lost_modules: int = int(lost_loot.get("modules", 0))
	_add_feed_entry(
		"run_failed",
		"行動失敗：失去戰利品 裝%d/寶石%d/模組%d（材料保留 %d）" % [
			lost_equipment,
			lost_gems,
			lost_modules,
			kept,
		],
		1,
		Color(1.0, 0.56, 0.56)
	)


func set_extraction_prompt(is_visible: bool, text: String) -> void:
	if extraction_prompt_label == null or extraction_prompt_panel == null:
		return
	extraction_prompt_panel.visible = is_visible
	extraction_prompt_label.text = text


func show_run_summary(title: String, body_text: String) -> void:
	if run_summary_panel == null:
		return
	run_summary_title.text = title
	run_summary_body.text = body_text
	run_summary_panel.visible = true


func hide_run_summary() -> void:
	if run_summary_panel == null:
		return
	run_summary_panel.visible = false


func is_run_summary_visible() -> bool:
	return run_summary_panel != null and run_summary_panel.visible


func _refresh_loot_filter_label() -> void:
	if loot_filter_label == null:
		return
	loot_filter_label.text = "[L] 掉落過濾: %s" % GameManager.get_loot_filter_name()


func _on_notification_requested(message: String, type: String) -> void:
	if message.is_empty():
		return
	var color := Color(0.82, 0.9, 1.0)
	match type:
		"beacon":
			color = Color(0.52, 0.92, 1.0)
		"warning":
			color = Color(1.0, 0.78, 0.42)
		"error":
			color = Color(1.0, 0.48, 0.48)
	_add_feed_entry("notice:%s:%s" % [type, message], message, 1, color)


func _show_pickup_message(item_data: Variant) -> void:
	if pickup_feed == null:
		return

	var text := _pickup_text(item_data)
	if text.is_empty():
		return

	_add_feed_entry(_pickup_key(item_data), text, _pickup_increment(item_data), _pickup_color(item_data))


func _add_feed_entry(key: String, text: String, increment: int, color: Color) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var found_index := -1
	for i in range(_pickup_entries.size()):
		if _pickup_entries[i].get("key", "") == key:
			found_index = i
			break

	if found_index >= 0:
		var entry := _pickup_entries[found_index]
		entry.count = int(entry.get("count", 1)) + maxi(1, increment)
		entry.expires_at = now + PICKUP_SHOW_TIME
		entry.base_text = text
		entry.color = color
		_pickup_entries.remove_at(found_index)
		_pickup_entries.insert(0, entry)
	else:
		_pickup_entries.insert(0, {
			"key": key,
			"base_text": text,
			"count": maxi(1, increment),
			"color": color,
			"expires_at": now + PICKUP_SHOW_TIME,
		})

	if _pickup_entries.size() > 24:
		_pickup_entries.resize(24)

	_refresh_pickup_feed()


func _pickup_text(item_data: Variant) -> String:
	if item_data is EquipmentData:
		var eq := item_data as EquipmentData
		return "拾取裝備：%s" % eq.display_name
	if item_data is SkillGem:
		var gem := item_data as SkillGem
		return "拾取技能寶石：%s" % gem.display_name
	if item_data is SupportGem:
		var support := item_data as SupportGem
		return "拾取輔助寶石：%s" % support.display_name
	if item_data is Module:
		var mod := item_data as Module
		return "拾取模組：%s" % mod.display_name
	if item_data is Dictionary:
		var mat_id: String = str(item_data.get("material_id", ""))
		if mat_id != "":
			var mat_data: Dictionary = DataManager.get_crafting_material(mat_id)
			var mat_name: String = str(mat_data.get("display_name", mat_id))
			return "拾取材料：%s" % mat_name
	return ""


func _pickup_color(item_data: Variant) -> Color:
	if item_data is EquipmentData:
		var eq := item_data as EquipmentData
		return StatTypes.RARITY_COLORS.get(eq.rarity, Color.WHITE)
	if item_data is SkillGem:
		return Color(0.35, 0.95, 0.45)
	if item_data is SupportGem:
		return Color(0.35, 0.75, 1.0)
	if item_data is Module:
		var mod := item_data as Module
		return mod.get_type_color()
	if item_data is Dictionary:
		return Color(1.0, 0.95, 0.6)
	return Color.WHITE


func _pickup_key(item_data: Variant) -> String:
	if item_data is EquipmentData:
		var eq := item_data as EquipmentData
		return "eq:%s:%d" % [eq.id, eq.rarity]
	if item_data is SkillGem:
		var gem := item_data as SkillGem
		return "skill:%s" % gem.id
	if item_data is SupportGem:
		var support := item_data as SupportGem
		return "support:%s" % support.id
	if item_data is Module:
		var mod := item_data as Module
		return "module:%s" % mod.id
	if item_data is Dictionary:
		var mat_id: String = str(item_data.get("material_id", ""))
		return "mat:%s" % mat_id
	return "other"


func _pickup_increment(item_data: Variant) -> int:
	if item_data is Dictionary:
		return maxi(1, int(item_data.get("amount", 1)))
	return 1


func _refresh_pickup_feed() -> void:
	if pickup_feed == null:
		return

	var now := Time.get_ticks_msec() / 1000.0
	var filtered: Array[Dictionary] = []
	for entry in _pickup_entries:
		if float(entry.get("expires_at", 0.0)) > now:
			filtered.append(entry)
	_pickup_entries = filtered

	for i in range(PICKUP_FEED_MAX):
		var label := _pickup_labels[i]
		if i >= _pickup_entries.size():
			label.visible = false
			continue

		var entry := _pickup_entries[i]
		var count: int = int(entry.get("count", 1))
		var base_text: String = str(entry.get("base_text", ""))
		label.text = "%s x%d" % [base_text, count] if count > 1 else base_text
		var color: Color = entry.get("color", Color.WHITE)
		var remaining := float(entry.get("expires_at", now)) - now
		color.a = clampf(remaining / PICKUP_FADE_TIME, 0.0, 1.0) if remaining < PICKUP_FADE_TIME else 1.0
		label.modulate = color
		label.visible = true
