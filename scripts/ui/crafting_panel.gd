class_name CraftingPanel
extends Control

## Crafting 面板 - 選擇裝備並使用材料

signal closed
signal navigate_to(panel_id: String)

@onready var panel_vbox: VBoxContainer = $PanelContainer/VBox
@onready var panel_root: PanelContainer = $PanelContainer
@onready var header_row: HBoxContainer = $PanelContainer/VBox/Header
@onready var content_row: HBoxContainer = $PanelContainer/VBox/HBox
@onready var title_label: Label = $PanelContainer/VBox/Header/Title
@onready var close_button: Button = $PanelContainer/VBox/Header/CloseButton
@onready var inventory_grid: GridContainer = $PanelContainer/VBox/HBox/InventorySide/InvScroll/InventoryGrid
@onready var inventory_scroll: ScrollContainer = $PanelContainer/VBox/HBox/InventorySide/InvScroll
@onready var material_buttons: HBoxContainer = $PanelContainer/VBox/HBox/CraftingSide/MaterialButtons
@onready var selected_label: Label = $PanelContainer/VBox/HBox/CraftingSide/SelectedLabel
@onready var tooltip_box: PanelContainer = $PanelContainer/VBox/HBox/CraftingSide/TooltipBox
@onready var tooltip_label: RichTextLabel = $PanelContainer/VBox/HBox/CraftingSide/TooltipBox/TooltipMargin/TooltipText
@onready var alter_button: Button = $PanelContainer/VBox/HBox/CraftingSide/MaterialButtons/AlterButton
@onready var augment_button: Button = $PanelContainer/VBox/HBox/CraftingSide/MaterialButtons/AugmentButton
@onready var refine_button: Button = $PanelContainer/VBox/HBox/CraftingSide/MaterialButtons/RefineButton
@onready var material_count_label: Label = $PanelContainer/VBox/HBox/CraftingSide/MaterialCount

var player: Player = null
var inventory_buttons: Array[Button] = []
var selected_index: int = -1
var current_floor: int = 1

const SLOT_SIZE := Vector2(48, 48)
const PANEL_HALF_SIZE := Vector2(450, 250)
const TAB_ACTIVE_BG := Color(0.24, 0.35, 0.55, 0.95)
const TAB_INACTIVE_BG := Color(0.2, 0.2, 0.25, 0.92)
const TAB_BORDER := Color(0.45, 0.45, 0.55)
const TAB_ACTIVE_BORDER := Color(0.72, 0.82, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_visual_style()
	_setup_material_summary_row()
	_setup_nav_tabs()
	_create_inventory_slots()
	_connect_buttons()
	visible = false


func _setup_nav_tabs() -> void:
	if panel_vbox == null:
		return
	var nav := HBoxContainer.new()
	nav.name = "NavTabs"
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 6)

	var tabs := [
		{"id": "equipment", "label": "裝備"},
		{"id": "module", "label": "模組"},
		{"id": "skill", "label": "技能"},
		{"id": "crafting", "label": "打造"},
	]

	for tab in tabs:
		var tab_id: String = str(tab["id"])
		var btn := Button.new()
		btn.text = str(tab["label"])
		_style_nav_button(btn, tab_id == "crafting")
		btn.pressed.connect(func() -> void:
			if tab_id != "crafting":
				navigate_to.emit(tab_id)
		)
		nav.add_child(btn)

	panel_vbox.add_child(nav)
	panel_vbox.move_child(nav, 1)


func _apply_visual_style() -> void:
	if panel_root:
		panel_root.anchor_left = 0.5
		panel_root.anchor_top = 0.5
		panel_root.anchor_right = 0.5
		panel_root.anchor_bottom = 0.5
		panel_root.offset_left = -PANEL_HALF_SIZE.x
		panel_root.offset_top = -PANEL_HALF_SIZE.y
		panel_root.offset_right = PANEL_HALF_SIZE.x
		panel_root.offset_bottom = PANEL_HALF_SIZE.y
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.12, 0.12, 0.16, 0.97)
		panel_style.border_color = Color(0.45, 0.45, 0.55)
		panel_style.set_border_width_all(2)
		panel_style.set_corner_radius_all(4)
		panel_style.content_margin_left = 12
		panel_style.content_margin_top = 12
		panel_style.content_margin_right = 12
		panel_style.content_margin_bottom = 12
		panel_root.add_theme_stylebox_override("panel", panel_style)
	if panel_vbox:
		panel_vbox.add_theme_constant_override("separation", 8)
	if header_row:
		header_row.custom_minimum_size.y = 34
	if content_row:
		content_row.add_theme_constant_override("separation", 12)
	if inventory_scroll:
		inventory_scroll.custom_minimum_size = Vector2(0, 220)
	if material_buttons:
		material_buttons.add_theme_constant_override("separation", 8)
	if tooltip_box:
		tooltip_box.custom_minimum_size = Vector2(0, 300)
	if tooltip_label:
		tooltip_label.fit_content = false
		tooltip_label.scroll_active = true
		tooltip_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if selected_label:
		selected_label.custom_minimum_size = Vector2(0, 22)
		selected_label.clip_text = true
		selected_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if title_label:
		title_label.add_theme_font_size_override("font_size", 15)
	if close_button:
		close_button.text = "X"
		close_button.custom_minimum_size = Vector2(30, 30)


func _style_nav_button(btn: Button, active: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = TAB_ACTIVE_BG if active else TAB_INACTIVE_BG
	normal.border_color = TAB_ACTIVE_BORDER if active else TAB_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)

	var hover := normal.duplicate() as StyleBoxFlat
	if not active:
		hover.border_color = TAB_ACTIVE_BORDER

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	btn.custom_minimum_size = Vector2(72, 26)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_C:
			close()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_I:
			navigate_to.emit("equipment")
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_M:
			navigate_to.emit("module")
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_K:
			navigate_to.emit("skill")
			get_viewport().set_input_as_handled()


func open(p: Player, floor_level: int) -> void:
	player = p
	current_floor = floor_level
	visible = true
	refresh()
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func refresh() -> void:
	_refresh_inventory()
	_refresh_selected()
	_refresh_material_counts()
	_refresh_material_button_texts()


func _create_inventory_slots() -> void:
	if inventory_grid == null:
		return

	for child in inventory_grid.get_children():
		child.queue_free()
	inventory_buttons.clear()

	for i in range(60):
		var btn := _create_inventory_button(i)
		inventory_grid.add_child(btn)
		inventory_buttons.append(btn)


func _create_inventory_button(index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	btn.text = ""

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.border_color = Color(0.5, 0.5, 0.6)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.pressed.connect(_on_inventory_slot_pressed.bind(index))
	btn.mouse_entered.connect(_on_inventory_slot_hovered.bind(index))
	btn.mouse_exited.connect(_on_inventory_slot_exited)

	return btn


func _refresh_inventory() -> void:
	if player == null:
		return

	for i in range(inventory_buttons.size()):
		var btn: Button = inventory_buttons[i]
		var item: EquipmentData = player.get_inventory_item(i)

		if item:
			btn.text = item.display_name.substr(0, 2)
			var color: Color = StatTypes.RARITY_COLORS.get(item.rarity, Color.WHITE)
			btn.add_theme_color_override("font_color", color)
		else:
			btn.text = ""
			btn.remove_theme_color_override("font_color")


func _refresh_selected() -> void:
	if selected_index < 0 or player == null:
		selected_label.text = "未選擇裝備"
		tooltip_label.text = "選擇裝備以查看"
		return

	var item: EquipmentData = player.get_inventory_item(selected_index)
	if item == null:
		selected_label.text = "未選擇裝備"
		tooltip_label.text = "選擇裝備以查看"
		return

	selected_label.text = "已選擇：%s" % item.display_name
	tooltip_label.text = item.get_tooltip()


func _refresh_material_counts() -> void:
	if player == null:
		return
	var alter := player.get_material_count("alter")
	var augment := player.get_material_count("augment")
	var refine := player.get_material_count("refine")
	material_count_label.text = "改造: %d | 增幅: %d | 精煉: %d" % [alter, augment, refine]


func _connect_buttons() -> void:
	if alter_button:
		alter_button.pressed.connect(_on_material_pressed.bind("alter"))
	if augment_button:
		augment_button.pressed.connect(_on_material_pressed.bind("augment"))
	if refine_button:
		refine_button.pressed.connect(_on_material_pressed.bind("refine"))


func _setup_material_summary_row() -> void:
	if selected_label == null or material_count_label == null:
		return
	var parent := selected_label.get_parent()
	if parent == null or parent != material_count_label.get_parent():
		return

	var row := HBoxContainer.new()
	row.name = "SelectedAndMaterialRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	parent.add_child(row)
	parent.move_child(row, selected_label.get_index())

	parent.remove_child(selected_label)
	parent.remove_child(material_count_label)
	row.add_child(selected_label)
	row.add_child(material_count_label)

	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _on_inventory_slot_pressed(index: int) -> void:
	selected_index = index
	_refresh_selected()


func _on_inventory_slot_hovered(index: int) -> void:
	if player == null:
		return
	var item: EquipmentData = player.get_inventory_item(index)
	if item:
		tooltip_label.text = item.get_tooltip()


func _on_inventory_slot_exited() -> void:
	_refresh_selected()


func _on_material_pressed(material_id: String) -> void:
	if player == null:
		return
	if selected_index < 0:
		return

	var item: EquipmentData = player.get_inventory_item(selected_index)
	if item == null:
		return

	if not CraftingSystem.can_apply_material(item, material_id):
		return
	var material_cost: int = CraftingSystem.get_material_cost(item, material_id)
	if not player.consume_material(material_id, material_cost):
		return

	var success := CraftingSystem.apply_material(item, material_id, current_floor)
	if not success:
		player.add_material(material_id, material_cost)
	EventBus.crafting_started.emit(item, material_id)
	EventBus.crafting_completed.emit(item, success)

	_refresh_selected()
	_refresh_material_counts()
	_refresh_material_button_texts()


func _refresh_material_button_texts() -> void:
	if player == null:
		return
	var item: EquipmentData = null
	if selected_index >= 0:
		item = player.get_inventory_item(selected_index)

	_set_material_button(alter_button, "改造", item, "alter")
	_set_material_button(augment_button, "增幅", item, "augment")
	_set_material_button(refine_button, "精煉", item, "refine")


func _set_material_button(btn: Button, label: String, item: EquipmentData, material_id: String) -> void:
	if btn == null:
		return
	var cost := CraftingSystem.get_material_cost(item, material_id)
	var count := player.get_material_count(material_id) if player != null else 0
	var can_use := item != null and CraftingSystem.can_apply_material(item, material_id) and count >= cost
	btn.text = label
	btn.disabled = not can_use
