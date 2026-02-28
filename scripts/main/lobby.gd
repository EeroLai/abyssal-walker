extends Control

const GAME_SCENE := "res://scenes/main/game.tscn"
const SLOT_SIZE := Vector2(48, 48)
const GRID_COLUMNS := 7
const MIN_GRID_SLOTS := 63
const BEACON_GRID_COLUMNS := 3
const BEACON_CARD_SIZE := Vector2(190, 96)
const MIN_BEACON_SLOTS := 6
const BEACON_MODIFIER_SYSTEM := preload("res://scripts/abyss/beacon_modifier_system.gd")

const LOOT_CATEGORIES: Array[Dictionary] = [
	{"key": "equipment", "label": "Equipment"},
	{"key": "skill_gems", "label": "Skill Gems"},
	{"key": "support_gems", "label": "Support Gems"},
	{"key": "modules", "label": "Modules"},
]

@onready var stash_total_label: Label = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryLeft/SummaryLeftBody/StashTotalLabel
@onready var stash_material_list: RichTextLabel = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryLeft/SummaryLeftBody/StashMaterialList
@onready var stash_loot_total_label: Label = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryRight/SummaryRightBody/StashLootTotalLabel
@onready var loadout_total_label: Label = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryRight/SummaryRightBody/LoadoutTotalLabel
@onready var config_row: HBoxContainer = $RootPanel/Content/ConfigRow
@onready var beacon_count_label: Label = $RootPanel/Content/BeaconCard/BeaconCardBody/BeaconCount
@onready var beacon_grid: GridContainer = $RootPanel/Content/BeaconCard/BeaconCardBody/BeaconScroll/BeaconGrid
@onready var beacon_summary_label: Label = $RootPanel/Content/BeaconCard/BeaconCardBody/BeaconSummary
@onready var stash_category: OptionButton = $PrepOverlay/PrepPanel/PrepContent/LootRow/StashSide/StashBody/StashCategory
@onready var loadout_category: OptionButton = $PrepOverlay/PrepPanel/PrepContent/LootRow/LoadoutSide/LoadoutBody/LoadoutCategory
@onready var stash_grid: GridContainer = $PrepOverlay/PrepPanel/PrepContent/LootRow/StashSide/StashBody/StashScroll/StashGrid
@onready var loadout_grid: GridContainer = $PrepOverlay/PrepPanel/PrepContent/LootRow/LoadoutSide/LoadoutBody/LoadoutScroll/LoadoutGrid
@onready var add_button: Button = $PrepOverlay/PrepPanel/PrepContent/LootRow/ActionSide/ActionBody/AddButton
@onready var remove_button: Button = $PrepOverlay/PrepPanel/PrepContent/LootRow/ActionSide/ActionBody/RemoveButton
@onready var clear_loadout_button: Button = $PrepOverlay/PrepPanel/PrepContent/LootRow/ActionSide/ActionBody/ClearLoadoutButton
@onready var start_button: Button = $RootPanel/Content/ButtonsRow/StartButton
@onready var quit_button: Button = $RootPanel/Content/ButtonsRow/QuitButton
@onready var prep_toggle_button: Button = $RootPanel/Content/PrepToggleRow/PrepToggleButton
@onready var prep_overlay: Control = $PrepOverlay
@onready var prep_close_button: Button = $PrepOverlay/PrepPanel/PrepContent/PrepHeader/PrepCloseButton

var _stash_entries: Array[Dictionary] = []
var _loadout_entries: Array[Dictionary] = []
var _stash_slot_buttons: Array[Button] = []
var _loadout_slot_buttons: Array[Button] = []
var _beacon_slot_buttons: Array[Button] = []
var _selected_stash_index: int = -1
var _selected_loadout_index: int = -1
var _item_tooltip: PanelContainer = null
var _tooltip_label: RichTextLabel = null
var _beacon_entries: Array = []
var _selected_beacon_index: int = -1
var _selected_beacon: AbyssBeaconData = null
var _selected_beacon_consumes: bool = true
var _selected_beacon_inventory_index: int = -1


func _ready() -> void:
	_setup_controls()
	_bind_actions()
	_create_tooltip()
	_refresh_beacon_inventory()
	_refresh_all()


func _process(_delta: float) -> void:
	if _item_tooltip != null and _item_tooltip.visible:
		_position_tooltip()


func _setup_controls() -> void:
	config_row.visible = false
	beacon_grid.columns = BEACON_GRID_COLUMNS
	beacon_grid.add_theme_constant_override("h_separation", 8)
	beacon_grid.add_theme_constant_override("v_separation", 8)

	_setup_category_options(stash_category)
	_setup_category_options(loadout_category)

	stash_grid.columns = GRID_COLUMNS
	stash_grid.add_theme_constant_override("h_separation", 6)
	stash_grid.add_theme_constant_override("v_separation", 6)
	loadout_grid.columns = GRID_COLUMNS
	loadout_grid.add_theme_constant_override("h_separation", 6)
	loadout_grid.add_theme_constant_override("v_separation", 6)
	prep_overlay.visible = false
	prep_toggle_button.text = "Open Loadout Prep"


func _setup_category_options(option: OptionButton) -> void:
	option.clear()
	for entry in LOOT_CATEGORIES:
		option.add_item(str(entry["label"]))
		option.set_item_metadata(option.item_count - 1, str(entry["key"]))
	option.select(0)


func _bind_actions() -> void:
	stash_category.item_selected.connect(_on_stash_category_selected)
	loadout_category.item_selected.connect(_on_loadout_category_selected)
	add_button.pressed.connect(_on_add_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	clear_loadout_button.pressed.connect(_on_clear_loadout_pressed)
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	prep_toggle_button.pressed.connect(_on_prep_toggle_pressed)
	prep_close_button.pressed.connect(_on_prep_close_pressed)
	EventBus.beacon_inventory_changed.connect(_on_beacon_inventory_changed)


func _on_prep_toggle_pressed() -> void:
	prep_overlay.visible = true
	_refresh_all()


func _on_prep_close_pressed() -> void:
	prep_overlay.visible = false
	_hide_tooltip()


func _on_stash_category_selected(_index: int) -> void:
	_selected_stash_index = -1
	_refresh_stash_list()


func _on_loadout_category_selected(_index: int) -> void:
	_selected_loadout_index = -1
	_refresh_loadout_list()


func _refresh_all() -> void:
	_refresh_beacon_preview()
	_refresh_summary()
	_refresh_stash_list()
	_refresh_loadout_list()
	_refresh_transfer_buttons()


func _refresh_beacon_inventory() -> void:
	var inventory_snapshot: Array = GameManager.get_beacon_inventory_snapshot()
	_beacon_entries = [_build_baseline_beacon_entry()]
	for i in range(inventory_snapshot.size()):
		var beacon: Variant = inventory_snapshot[i]
		_beacon_entries.append(_wrap_inventory_beacon_entry(beacon, i))
	_clear_grid(beacon_grid, _beacon_slot_buttons)
	if beacon_count_label != null:
		beacon_count_label.text = "Owned Beacons: %d  |  Baseline Ready" % inventory_snapshot.size()
	if _beacon_entries.is_empty():
		_selected_beacon_index = -1
		_selected_beacon = null
		_selected_beacon_consumes = true
		_selected_beacon_inventory_index = -1
		start_button.disabled = true
		_rebuild_beacon_grid(0)
		_refresh_beacon_preview()
		return

	var previous_id := _selected_beacon.id if _selected_beacon != null else ""
	var target_index := -1
	for i in range(_beacon_entries.size()):
		var beacon: Variant = _beacon_entries[i]
		if target_index == -1 and str(_beacon_value(beacon, "id", "")) == previous_id:
			target_index = i
	if target_index == -1:
		target_index = clampi(_selected_beacon_index, 0, _beacon_entries.size() - 1)
	if target_index < 0:
		target_index = 0
	_rebuild_beacon_grid(target_index)
	_apply_selected_beacon(target_index)


func _apply_selected_beacon(index: int) -> void:
	if index < 0 or index >= _beacon_entries.size():
		_selected_beacon_index = -1
		_selected_beacon = null
		_selected_beacon_consumes = true
		_selected_beacon_inventory_index = -1
		start_button.disabled = true
		_refresh_start_button_label()
		_refresh_beacon_grid_selection()
		_refresh_beacon_preview()
		return
	var raw_beacon: Variant = _beacon_entries[index]
	_selected_beacon = AbyssBeaconData.new()
	_selected_beacon.id = str(_beacon_value(raw_beacon, "id", ""))
	_selected_beacon.display_name = str(_beacon_value(raw_beacon, "display_name", "Abyss Beacon"))
	_selected_beacon.base_difficulty = int(_beacon_value(raw_beacon, "base_difficulty", 1))
	_selected_beacon.max_depth = int(_beacon_value(raw_beacon, "max_depth", 1))
	_selected_beacon.lives_max = int(_beacon_value(raw_beacon, "lives_max", 1))
	_selected_beacon.modifier_ids = _beacon_modifier_ids(raw_beacon)
	_selected_beacon_consumes = bool(_beacon_value(raw_beacon, "consumable", true))
	_selected_beacon_inventory_index = int(_beacon_value(raw_beacon, "inventory_index", -1))
	_selected_beacon_index = index
	start_button.disabled = false
	_refresh_start_button_label()
	_refresh_beacon_grid_selection()
	_refresh_beacon_preview()


func _beacon_value(beacon: Variant, key: String, default_value: Variant) -> Variant:
	if beacon is Resource:
		var value: Variant = beacon.get(key)
		return default_value if value == null else value
	if beacon is Dictionary:
		return (beacon as Dictionary).get(key, default_value)
	return default_value


func _refresh_summary() -> void:
	stash_total_label.text = "Crafting Materials: %d" % GameManager.get_stash_material_total()

	var lines: Array[String] = []
	for material_id in DataManager.get_all_material_ids():
		var amount: int = GameManager.get_stash_material_count(material_id)
		if amount <= 0:
			continue
		var mat_data: Dictionary = DataManager.get_crafting_material(material_id)
		lines.append("- %s x%d" % [str(mat_data.get("display_name", material_id)), amount])
	if lines.is_empty():
		lines.append("- Empty")
	stash_material_list.text = "\n".join(lines)

	var stash_counts: Dictionary = GameManager.get_stash_loot_counts()
	var loadout_counts: Dictionary = GameManager.get_operation_loadout_counts()
	stash_loot_total_label.text = "Stash Loot: Eq %d | Skill %d | Support %d | Module %d" % [
		int(stash_counts.get("equipment", 0)),
		int(stash_counts.get("skill_gems", 0)),
		int(stash_counts.get("support_gems", 0)),
		int(stash_counts.get("modules", 0)),
	]
	loadout_total_label.text = "Loadout: Eq %d | Skill %d | Support %d | Module %d" % [
		int(loadout_counts.get("equipment", 0)),
		int(loadout_counts.get("skill_gems", 0)),
		int(loadout_counts.get("support_gems", 0)),
		int(loadout_counts.get("modules", 0)),
	]


func _refresh_stash_list() -> void:
	_stash_entries.clear()
	var category: String = _selected_category_key(stash_category)
	var snapshot: Dictionary = GameManager.get_stash_loot_snapshot()
	var items: Array = snapshot.get(category, [])
	for i in range(items.size()):
		_stash_entries.append({"category": category, "index": i})
	_rebuild_stash_grid(items)


func _refresh_loadout_list() -> void:
	_loadout_entries.clear()
	var category: String = _selected_category_key(loadout_category)
	var snapshot: Dictionary = GameManager.get_operation_loadout_snapshot()
	var items: Array = snapshot.get(category, [])
	for i in range(items.size()):
		_loadout_entries.append({"category": category, "index": i})
	_rebuild_loadout_grid(items)


func _rebuild_stash_grid(items: Array) -> void:
	_clear_grid(stash_grid, _stash_slot_buttons)
	if _selected_stash_index >= items.size():
		_selected_stash_index = -1
	var slot_count := _aligned_slot_count(items.size())
	for i in range(slot_count):
		var btn := _create_loot_slot_button(i, true)
		stash_grid.add_child(btn)
		_stash_slot_buttons.append(btn)
		if i < items.size():
			_configure_filled_slot(btn, items[i], i == _selected_stash_index)
		else:
			_configure_empty_slot(btn, i == _selected_stash_index)


func _rebuild_loadout_grid(items: Array) -> void:
	_clear_grid(loadout_grid, _loadout_slot_buttons)
	if _selected_loadout_index >= items.size():
		_selected_loadout_index = -1
	var slot_count := _aligned_slot_count(items.size())
	for i in range(slot_count):
		var btn := _create_loot_slot_button(i, false)
		loadout_grid.add_child(btn)
		_loadout_slot_buttons.append(btn)
		if i < items.size():
			_configure_filled_slot(btn, items[i], i == _selected_loadout_index)
		else:
			_configure_empty_slot(btn, i == _selected_loadout_index)


func _clear_grid(grid: GridContainer, buttons: Array[Button]) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	buttons.clear()


func _aligned_slot_count(item_count: int) -> int:
	var base_count := maxi(item_count, MIN_GRID_SLOTS)
	var remainder := base_count % GRID_COLUMNS
	if remainder == 0:
		return base_count
	return base_count + (GRID_COLUMNS - remainder)


func _create_loot_slot_button(index: int, is_stash: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	btn.clip_text = true
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 12)
	if is_stash:
		btn.pressed.connect(_on_stash_slot_pressed.bind(index))
		btn.mouse_entered.connect(_on_stash_slot_hovered.bind(index))
	else:
		btn.pressed.connect(_on_loadout_slot_pressed.bind(index))
		btn.mouse_entered.connect(_on_loadout_slot_hovered.bind(index))
	btn.mouse_exited.connect(_hide_tooltip)
	return btn


func _configure_filled_slot(btn: Button, item: Variant, selected: bool) -> void:
	btn.text = _loot_slot_short_text(item)
	btn.add_theme_color_override("font_color", _loot_font_color(item))
	_apply_slot_style(btn, selected)


func _configure_empty_slot(btn: Button, selected: bool) -> void:
	btn.text = ""
	btn.remove_theme_color_override("font_color")
	_apply_slot_style(btn, selected)


func _loot_slot_short_text(item: Variant) -> String:
	if item is EquipmentData:
		var eq: EquipmentData = item
		var name := eq.display_name
		return name.substr(0, mini(2, name.length()))
	if item is SkillGem:
		var sg: SkillGem = item
		return "%s\nLv%d" % [_short_name(sg.display_name, 3), sg.level]
	if item is SupportGem:
		var sp: SupportGem = item
		return "%s\nLv%d" % [_short_name(sp.display_name, 3), sp.level]
	if item is Module:
		var mod: Module = item
		return _short_name(mod.display_name, 2)
	return "?"


func _loot_font_color(item: Variant) -> Color:
	if item is EquipmentData:
		var eq: EquipmentData = item
		return StatTypes.RARITY_COLORS.get(eq.rarity, Color.WHITE)
	if item is SkillGem:
		return Color(0.62, 0.86, 1.0)
	if item is SupportGem:
		return Color(0.58, 0.96, 0.7)
	if item is Module:
		var mod: Module = item
		return mod.get_type_color()
	return Color(0.9, 0.9, 0.9)


func _apply_slot_style(btn: Button, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.08, 0.13, 1)
	normal.border_color = Color(0.58, 0.82, 1.0, 1) if selected else Color(0.21, 0.32, 0.45, 0.95)
	normal.set_border_width_all(2 if selected else 1)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	if hover != null:
		if selected:
			hover.border_color = Color(0.67, 0.88, 1.0, 1)
		else:
			hover.border_color = Color(0.42, 0.59, 0.79, 0.95)
		btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)


func _on_stash_slot_pressed(index: int) -> void:
	if index < 0 or index >= _stash_entries.size():
		_selected_stash_index = -1
	else:
		_selected_stash_index = index
	_refresh_stash_list()
	_refresh_transfer_buttons()


func _on_loadout_slot_pressed(index: int) -> void:
	if index < 0 or index >= _loadout_entries.size():
		_selected_loadout_index = -1
	else:
		_selected_loadout_index = index
	_refresh_loadout_list()
	_refresh_transfer_buttons()


func _on_stash_slot_hovered(index: int) -> void:
	var item: Variant = _get_stash_item_at(index)
	if item == null:
		_hide_tooltip()
		return
	_show_tooltip(item)


func _on_loadout_slot_hovered(index: int) -> void:
	var item: Variant = _get_loadout_item_at(index)
	if item == null:
		_hide_tooltip()
		return
	_show_tooltip(item)


func _get_stash_item_at(index: int) -> Variant:
	if index < 0 or index >= _stash_entries.size():
		return null
	var entry: Dictionary = _stash_entries[index]
	var category: String = str(entry.get("category", ""))
	var item_index: int = int(entry.get("index", -1))
	var snapshot: Dictionary = GameManager.get_stash_loot_snapshot()
	var items: Array = snapshot.get(category, [])
	if item_index < 0 or item_index >= items.size():
		return null
	return items[item_index]


func _get_loadout_item_at(index: int) -> Variant:
	if index < 0 or index >= _loadout_entries.size():
		return null
	var entry: Dictionary = _loadout_entries[index]
	var category: String = str(entry.get("category", ""))
	var item_index: int = int(entry.get("index", -1))
	var snapshot: Dictionary = GameManager.get_operation_loadout_snapshot()
	var items: Array = snapshot.get(category, [])
	if item_index < 0 or item_index >= items.size():
		return null
	return items[item_index]


func _refresh_transfer_buttons() -> void:
	add_button.disabled = _selected_stash_index < 0 or _selected_stash_index >= _stash_entries.size()
	remove_button.disabled = _selected_loadout_index < 0 or _selected_loadout_index >= _loadout_entries.size()


func _selected_category_key(option: OptionButton) -> String:
	if option.item_count <= 0:
		return "equipment"
	var idx := option.selected
	if idx < 0:
		idx = 0
	return str(option.get_item_metadata(idx))


func _loot_label(item: Variant) -> String:
	if item is EquipmentData:
		return (item as EquipmentData).get_tooltip()
	if item is SkillGem:
		return (item as SkillGem).get_tooltip()
	if item is SupportGem:
		return (item as SupportGem).get_tooltip()
	if item is Module:
		var mod: Module = item
		var lines: Array[String] = []
		lines.append("[color=#%s][b]%s[/b][/color]" % [mod.get_type_color().to_html(false), mod.display_name])
		lines.append("[color=gray]%s | Load %d[/color]" % [mod.get_type_name(), mod.load_cost])
		if mod.description != "":
			lines.append("")
			lines.append(mod.description)
		if not mod.modifiers.is_empty():
			lines.append("")
			lines.append("Modifiers:")
			for stat_mod in mod.modifiers:
				if stat_mod is StatModifier:
					lines.append("- %s" % (stat_mod as StatModifier).get_description())
		return "\n".join(lines)
	return "Unknown Item"

func _short_name(name: String, max_len: int = 3) -> String:
	if name == "":
		return "?"
	return name.substr(0, mini(max_len, name.length()))

func _create_tooltip() -> void:
	_item_tooltip = PanelContainer.new()
	_item_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_tooltip.top_level = true
	_item_tooltip.visible = false
	_item_tooltip.z_index = 100

	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	tip_style.border_color = Color(0.5, 0.5, 0.7)
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(4)
	_item_tooltip.add_theme_stylebox_override("panel", tip_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_item_tooltip.add_child(margin)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.custom_minimum_size = Vector2(260, 0)
	margin.add_child(_tooltip_label)

	add_child(_item_tooltip)


func _show_tooltip(item: Variant) -> void:
	if _item_tooltip == null or _tooltip_label == null:
		return
	_tooltip_label.text = _loot_label(item)
	_item_tooltip.visible = true
	call_deferred("_position_tooltip")


func _hide_tooltip() -> void:
	if _item_tooltip != null:
		_item_tooltip.visible = false


func _position_tooltip() -> void:
	if _item_tooltip == null:
		return
	var tip_size := _item_tooltip.get_combined_minimum_size()
	var mouse_pos := get_global_mouse_position()
	var screen_size := get_viewport_rect().size

	var pos := mouse_pos + Vector2(16, 16)
	if pos.x + tip_size.x > screen_size.x:
		pos.x = mouse_pos.x - tip_size.x - 16
	if pos.y + tip_size.y > screen_size.y:
		pos.y = mouse_pos.y - tip_size.y - 16
	_item_tooltip.global_position = pos


func _on_add_pressed() -> void:
	if _selected_stash_index < 0 or _selected_stash_index >= _stash_entries.size():
		return
	var entry: Dictionary = _stash_entries[_selected_stash_index]
	if GameManager.move_stash_loot_to_loadout(str(entry["category"]), int(entry["index"])):
		_selected_loadout_index = -1
		_refresh_all()


func _on_remove_pressed() -> void:
	if _selected_loadout_index < 0 or _selected_loadout_index >= _loadout_entries.size():
		return
	var entry: Dictionary = _loadout_entries[_selected_loadout_index]
	if GameManager.move_loadout_loot_to_stash(str(entry["category"]), int(entry["index"])):
		_selected_stash_index = -1
		_refresh_all()


func _on_clear_loadout_pressed() -> void:
	_selected_loadout_index = -1
	var snapshot: Dictionary = GameManager.get_operation_loadout_snapshot()
	for category_entry in LOOT_CATEGORIES:
		var category: String = str(category_entry["key"])
		var items: Array = snapshot.get(category, [])
		for i in range(items.size() - 1, -1, -1):
			GameManager.move_loadout_loot_to_stash(category, i)
	_refresh_all()


func _on_beacon_selected(index: int) -> void:
	_apply_selected_beacon(index)


func _on_beacon_inventory_changed(_snapshot: Array) -> void:
	_refresh_beacon_inventory()


func _on_start_pressed() -> void:
	if _selected_beacon == null:
		return
	if _selected_beacon_consumes:
		if not GameManager.activate_beacon(_selected_beacon_inventory_index, GameManager.OperationType.NORMAL):
			return
	else:
		GameManager.start_operation_from_beacon(_selected_beacon, GameManager.OperationType.NORMAL)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _refresh_beacon_preview() -> void:
	if beacon_summary_label == null:
		return
	if _selected_beacon == null:
		beacon_summary_label.text = "No beacon selected.\n\nChoose a beacon from the grid to begin the next dive."
		return
	var start_level := _selected_beacon.get_effective_level_at_depth(1, 0)
	var end_level := _selected_beacon.get_effective_level_at_depth(_selected_beacon.max_depth, 0)
	var modifier_lines := BEACON_MODIFIER_SYSTEM.get_modifier_display_lines(_selected_beacon.modifier_ids)
	var modifier_text := "Modifiers: None"
	if not modifier_lines.is_empty():
		modifier_text = "Modifiers:\n- %s" % "\n- ".join(modifier_lines)
	var cost_text := "Cost: Consumes 1 Beacon" if _selected_beacon_consumes else "Cost: None"
	beacon_summary_label.text = "%s\nStart Lv %d  End Lv %d  Depth %d  Lives %d\n%s\n%s" % [
		_selected_beacon.display_name,
		start_level,
		end_level,
		_selected_beacon.max_depth,
		_selected_beacon.lives_max,
		cost_text,
		modifier_text,
	]


func _refresh_start_button_label() -> void:
	if start_button == null:
		return
	start_button.text = "Activate Beacon" if _selected_beacon_consumes else "Start Baseline Dive"


func _build_baseline_beacon_entry() -> Dictionary:
	return {
		"id": "baseline_loop",
		"display_name": "Baseline Dive",
		"base_difficulty": 1,
		"max_depth": 5,
		"lives_max": 3,
		"modifier_ids": PackedStringArray(),
		"consumable": false,
		"inventory_index": -1,
	}


func _wrap_inventory_beacon_entry(beacon: Variant, inventory_index: int) -> Dictionary:
	return {
		"id": str(_beacon_value(beacon, "id", "")),
		"display_name": str(_beacon_value(beacon, "display_name", "Abyss Beacon")),
		"base_difficulty": int(_beacon_value(beacon, "base_difficulty", 1)),
		"max_depth": int(_beacon_value(beacon, "max_depth", 1)),
		"lives_max": int(_beacon_value(beacon, "lives_max", 1)),
		"modifier_ids": _beacon_modifier_ids(beacon),
		"consumable": true,
		"inventory_index": inventory_index,
	}


func _rebuild_beacon_grid(selected_index: int) -> void:
	var slot_count := _aligned_beacon_slot_count(_beacon_entries.size())
	for i in range(slot_count):
		var card := _create_beacon_card_button(i)
		beacon_grid.add_child(card)
		_beacon_slot_buttons.append(card)
		if i < _beacon_entries.size():
			_configure_beacon_card(card, _beacon_entries[i], i == selected_index)
		else:
			_configure_empty_beacon_card(card)


func _aligned_beacon_slot_count(item_count: int) -> int:
	var base_count := maxi(item_count, MIN_BEACON_SLOTS)
	var remainder := base_count % BEACON_GRID_COLUMNS
	if remainder == 0:
		return base_count
	return base_count + (BEACON_GRID_COLUMNS - remainder)


func _create_beacon_card_button(index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = BEACON_CARD_SIZE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_text = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(_on_beacon_selected.bind(index))
	return btn


func _configure_beacon_card(btn: Button, beacon: Variant, selected: bool) -> void:
	var display_name := str(_beacon_value(beacon, "display_name", "Abyss Beacon"))
	var level := int(_beacon_value(beacon, "base_difficulty", 1))
	var depth := int(_beacon_value(beacon, "max_depth", 1))
	var lives := int(_beacon_value(beacon, "lives_max", 1))
	var modifier_summary := _beacon_card_modifier_summary(beacon)
	btn.disabled = false
	btn.text = "%s\nLv %d  Depth %d  Lives %d\n%s" % [
		display_name,
		level,
		depth,
		lives,
		modifier_summary,
	]
	_apply_beacon_card_style(btn, selected, _beacon_card_accent(beacon))


func _configure_empty_beacon_card(btn: Button) -> void:
	btn.disabled = true
	btn.text = ""
	_apply_beacon_card_style(btn, false, Color(0.18, 0.24, 0.31, 1.0), true)


func _refresh_beacon_grid_selection() -> void:
	for i in range(_beacon_slot_buttons.size()):
		if i < _beacon_entries.size():
			_configure_beacon_card(_beacon_slot_buttons[i], _beacon_entries[i], i == _selected_beacon_index)
		else:
			_configure_empty_beacon_card(_beacon_slot_buttons[i])


func _apply_beacon_card_style(btn: Button, selected: bool, accent: Color, is_empty: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent.darkened(0.86) if not is_empty else Color(0.035, 0.055, 0.08, 1)
	normal.border_color = accent.lightened(0.25) if selected else accent.darkened(0.18)
	normal.set_border_width_all(2 if selected else 1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 10
	normal.content_margin_top = 8
	normal.content_margin_right = 10
	normal.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	if hover != null:
		hover.border_color = accent.lightened(0.4) if selected else accent.lightened(0.12)
		btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_color_override("font_color", accent.lightened(0.55) if not is_empty else Color(0.32, 0.4, 0.5, 1))
	btn.add_theme_color_override("font_hover_color", accent.lightened(0.7) if not is_empty else Color(0.38, 0.46, 0.56, 1))
	btn.add_theme_color_override("font_pressed_color", accent.lightened(0.7) if not is_empty else Color(0.38, 0.46, 0.56, 1))


func _beacon_card_modifier_summary(beacon: Variant) -> String:
	if not bool(_beacon_value(beacon, "consumable", true)):
		return "No Beacon Cost"
	var modifier_ids := _beacon_modifier_ids(beacon)
	if modifier_ids.is_empty():
		return "Clear Signal"
	var names: Array[String] = []
	for modifier_id in modifier_ids:
		names.append(BEACON_MODIFIER_SYSTEM.get_modifier_name(str(modifier_id)))
		if names.size() >= 2:
			break
	var text: String = " | ".join(names)
	if modifier_ids.size() > names.size():
		text += " +%d" % (modifier_ids.size() - names.size())
	return text


func _beacon_card_accent(beacon: Variant) -> Color:
	var depth := int(_beacon_value(beacon, "max_depth", 1))
	var lives := int(_beacon_value(beacon, "lives_max", 1))
	var modifier_ids := _beacon_modifier_ids(beacon)
	if not bool(_beacon_value(beacon, "consumable", true)):
		return Color(0.74, 0.82, 0.92, 1.0)
	if modifier_ids.has("boss_reward"):
		return Color(0.95, 0.73, 0.32, 1.0)
	if lives <= 1 or modifier_ids.has("pressure"):
		return Color(0.94, 0.47, 0.34, 1.0)
	if depth >= 20 or modifier_ids.has("deep_range"):
		return Color(0.38, 0.88, 0.98, 1.0)
	if depth >= 12:
		return Color(0.55, 0.93, 0.72, 1.0)
	return Color(0.63, 0.78, 0.96, 1.0)


func _beacon_modifier_ids(beacon: Variant) -> PackedStringArray:
	var raw_modifier_ids: Variant = _beacon_value(beacon, "modifier_ids", PackedStringArray())
	var modifier_ids := PackedStringArray()
	if raw_modifier_ids is PackedStringArray:
		modifier_ids = raw_modifier_ids
	elif raw_modifier_ids is Array:
		for entry in raw_modifier_ids:
			modifier_ids.append(str(entry))
	return modifier_ids
