class_name EquipmentPanel
extends Control

## 裝備面板 - 顯示裝備欄位和背包

signal closed
signal navigate_to(panel_id: String)

@onready var panel_vbox: VBoxContainer = $PanelContainer/VBox
@onready var panel_root: PanelContainer = $PanelContainer
@onready var title_label: Label = $PanelContainer/VBox/Header/Title
@onready var close_button: Button = $PanelContainer/VBox/Header/CloseButton
@onready var equipment_grid: GridContainer = $PanelContainer/VBox/HBox/EquipmentSide/EquipmentGrid
@onready var inventory_grid: GridContainer = $PanelContainer/VBox/HBox/InventorySide/ScrollContainer/InventoryGrid
@onready var stats_summary_label: RichTextLabel = $PanelContainer/VBox/HBox/StatsSide/StatsSummary

var item_tooltip: PanelContainer = null
var tooltip_label: RichTextLabel = null

var player: Player = null
var equipment_slots: Dictionary = {}  # EquipmentSlot -> Button
var inventory_buttons: Array[Button] = []
var _last_alt_pressed: bool = false

const SLOT_SIZE := Vector2(48, 48)
const PANEL_HALF_SIZE := Vector2(450, 250)
const TAB_ACTIVE_BG := Color(0.24, 0.35, 0.55, 0.95)
const TAB_INACTIVE_BG := Color(0.2, 0.2, 0.25, 0.92)
const TAB_BORDER := Color(0.45, 0.45, 0.55)
const TAB_ACTIVE_BORDER := Color(0.72, 0.82, 1.0)


func _ready() -> void:
	# 設定為暫停時仍可處理
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_visual_style()
	_setup_nav_tabs()
	_create_equipment_slots()
	_create_inventory_slots()
	_create_tooltip()
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
		_style_nav_button(btn, tab_id == "equipment")
		btn.pressed.connect(func() -> void:
			if tab_id != "equipment":
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


func _process(_delta: float) -> void:
	var alt_pressed := Input.is_key_pressed(KEY_ALT)
	if alt_pressed != _last_alt_pressed:
		_last_alt_pressed = alt_pressed
		if visible:
			_refresh_hover_tooltip_from_mouse()

	if item_tooltip != null and item_tooltip.visible:
		_position_tooltip()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return

	if visible and event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_I:
			close()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_M:
			navigate_to.emit("module")
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_K:
			navigate_to.emit("skill")
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_C:
			navigate_to.emit("crafting")
			get_viewport().set_input_as_handled()


func open(p: Player) -> void:
	player = p
	visible = true
	refresh()
	# 暫停遊戲
	get_tree().paused = true


func close() -> void:
	visible = false
	hide_tooltip()
	get_tree().paused = false
	closed.emit()


func refresh() -> void:
	if player == null:
		return
	_refresh_equipment()
	_refresh_inventory()
	_refresh_stats_summary()
	call_deferred("_refresh_hover_tooltip_from_mouse")


func _create_equipment_slots() -> void:
	if equipment_grid == null:
		return

	# 清空現有
	for child in equipment_grid.get_children():
		child.queue_free()

	# 創建 10 個裝備欄位
	var slots: Array[StatTypes.EquipmentSlot] = [
		StatTypes.EquipmentSlot.HELMET,
		StatTypes.EquipmentSlot.ARMOR,
		StatTypes.EquipmentSlot.AMULET,
		StatTypes.EquipmentSlot.GLOVES,
		StatTypes.EquipmentSlot.BELT,
		StatTypes.EquipmentSlot.BOOTS,
		StatTypes.EquipmentSlot.RING_1,
		StatTypes.EquipmentSlot.RING_2,
		StatTypes.EquipmentSlot.MAIN_HAND,
		StatTypes.EquipmentSlot.OFF_HAND,
	]

	for slot in slots:
		var btn := _create_slot_button(slot)
		equipment_grid.add_child(btn)
		equipment_slots[slot] = btn


func _create_slot_button(slot: StatTypes.EquipmentSlot) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	btn.text = ""
	btn.tooltip_text = StatTypes.SLOT_NAMES.get(slot, "未知")

	# 設定按鈕樣式
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.border_color = Color(0.6, 0.6, 0.8)
	btn.add_theme_stylebox_override("hover", hover_style)

	# 連接信號
	btn.pressed.connect(_on_equipment_slot_pressed.bind(slot))
	btn.mouse_entered.connect(_on_equipment_slot_hovered.bind(slot))
	btn.mouse_exited.connect(hide_tooltip)

	return btn


func _create_inventory_slots() -> void:
	if inventory_grid == null:
		return

	# 清空現有
	for child in inventory_grid.get_children():
		child.queue_free()
	inventory_buttons.clear()

	# 創建 60 個背包格子
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
	btn.gui_input.connect(_on_inventory_slot_gui_input.bind(index))
	btn.mouse_entered.connect(_on_inventory_slot_hovered.bind(index))
	btn.mouse_exited.connect(hide_tooltip)

	return btn


func _refresh_equipment() -> void:
	for slot in equipment_slots.keys():
		var btn: Button = equipment_slots[slot]
		var item: EquipmentData = player.get_equipped(slot)

		if item:
			btn.text = item.display_name.substr(0, 2)
			var color: Color = StatTypes.RARITY_COLORS.get(item.rarity, Color.WHITE)
			btn.add_theme_color_override("font_color", color)
			_set_button_rarity_border(btn, item.rarity)
		else:
			btn.text = StatTypes.SLOT_NAMES.get(slot, "")
			btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.62))
			_set_button_rarity_border(btn, -1)


func _refresh_inventory() -> void:
	for i in range(inventory_buttons.size()):
		var btn: Button = inventory_buttons[i]
		var item: EquipmentData = player.get_inventory_item(i)

		if item:
			btn.text = item.display_name.substr(0, 2)
			var color: Color = StatTypes.RARITY_COLORS.get(item.rarity, Color.WHITE)
			btn.add_theme_color_override("font_color", color)
			_set_button_rarity_border(btn, item.rarity)
		else:
			btn.text = ""
			btn.remove_theme_color_override("font_color")
			_set_button_rarity_border(btn, -1)


func _set_button_rarity_border(btn: Button, rarity: int) -> void:
	var style := btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	if style == null:
		return

	if rarity >= 0:
		var color: Color = StatTypes.RARITY_COLORS.get(rarity, Color.WHITE)
		style.border_color = color
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.3, 0.3, 0.35)
		style.set_border_width_all(1)

	btn.add_theme_stylebox_override("normal", style)


func _on_equipment_slot_pressed(slot: StatTypes.EquipmentSlot) -> void:
	var item: EquipmentData = player.get_equipped(slot)
	if item:
		# 卸下裝備到背包
		var unequipped := player.unequip(slot)
		if unequipped:
			player.add_to_inventory(unequipped)
		refresh()


func _on_inventory_slot_pressed(index: int) -> void:
	var item: EquipmentData = player.get_inventory_item(index)
	if item:
		# 從背包裝備
		player.equip_from_inventory(index)
		refresh()


func _on_inventory_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var item: EquipmentData = player.get_inventory_item(index)
			if item:
				player.remove_from_inventory(index)
				refresh()
				get_viewport().set_input_as_handled()


func _on_equipment_slot_hovered(slot: StatTypes.EquipmentSlot) -> void:
	var item: EquipmentData = player.get_equipped(slot)
	if item:
		show_tooltip(item)
	else:
		show_empty_slot_tooltip(slot)


func _on_inventory_slot_hovered(index: int) -> void:
	var item: EquipmentData = player.get_inventory_item(index)
	if item:
		var equipped: EquipmentData = player.get_equipped(item.slot)
		show_tooltip(item, equipped)
	else:
		hide_tooltip()


func _refresh_hover_tooltip_from_mouse() -> void:
	if not visible or player == null:
		return
	var mouse_pos := get_global_mouse_position()

	for i in range(inventory_buttons.size()):
		var btn: Button = inventory_buttons[i]
		if btn != null and btn.visible and btn.get_global_rect().has_point(mouse_pos):
			_on_inventory_slot_hovered(i)
			return

	for slot in equipment_slots.keys():
		var eq_btn: Button = equipment_slots[slot]
		if eq_btn != null and eq_btn.visible and eq_btn.get_global_rect().has_point(mouse_pos):
			_on_equipment_slot_hovered(slot)
			return

	hide_tooltip()


func show_tooltip(item: EquipmentData, compare_item: EquipmentData = null) -> void:
	if item_tooltip == null or tooltip_label == null:
		return

	var text := _build_tooltip_text(item, compare_item)
	tooltip_label.text = text
	tooltip_label.reset_size()
	item_tooltip.reset_size()
	item_tooltip.visible = true


func show_empty_slot_tooltip(slot: StatTypes.EquipmentSlot) -> void:
	if item_tooltip == null or tooltip_label == null:
		return

	var slot_name: String = StatTypes.SLOT_NAMES.get(slot, "")
	tooltip_label.text = "[color=gray]%s\n空槽[/color]" % slot_name
	tooltip_label.reset_size()
	item_tooltip.reset_size()
	item_tooltip.visible = true


func hide_tooltip() -> void:
	if item_tooltip:
		item_tooltip.visible = false


func _create_tooltip() -> void:
	item_tooltip = PanelContainer.new()
	item_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_tooltip.top_level = true
	item_tooltip.visible = false
	item_tooltip.z_index = 100

	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	tip_style.border_color = Color(0.5, 0.5, 0.7)
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(4)
	item_tooltip.add_theme_stylebox_override("panel", tip_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	item_tooltip.add_child(margin)

	tooltip_label = RichTextLabel.new()
	tooltip_label.bbcode_enabled = true
	tooltip_label.fit_content = true
	tooltip_label.custom_minimum_size = Vector2(220, 0)
	margin.add_child(tooltip_label)

	add_child(item_tooltip)


func _refresh_stats_summary() -> void:
	if player == null or player.stats == null or stats_summary_label == null:
		return
	var s: StatContainer = player.stats
	var lines: Array[String] = []
	lines.append("生命值   : %d" % int(round(s.get_stat(StatTypes.Stat.HP))))
	lines.append("攻擊力   : %d" % int(round(s.get_stat(StatTypes.Stat.ATK))))
	lines.append("防禦力   : %d" % int(round(s.get_stat(StatTypes.Stat.DEF))))
	lines.append("攻擊速度 : %.2f" % s.get_stat(StatTypes.Stat.ATK_SPEED))
	lines.append("移動速度 : %.0f" % s.get_stat(StatTypes.Stat.MOVE_SPEED))
	lines.append("暴擊率   : %.1f%%" % (s.get_stat(StatTypes.Stat.CRIT_RATE) * 100.0))
	lines.append("暴擊傷害 : %.1f%%" % (s.get_stat(StatTypes.Stat.CRIT_DMG) * 100.0))
	lines.append("最終傷害 : %.1f%%" % (s.get_stat(StatTypes.Stat.FINAL_DMG) * 100.0))
	lines.append("物理穿透 : %.1f%%" % (s.get_stat(StatTypes.Stat.PHYS_PEN) * 100.0))
	lines.append("元素穿透 : %.1f%%" % (s.get_stat(StatTypes.Stat.ELEMENTAL_PEN) * 100.0))
	lines.append("破甲     : %.0f" % s.get_stat(StatTypes.Stat.ARMOR_SHRED))
	lines.append("抗性削減 : %.1f%%" % (s.get_stat(StatTypes.Stat.RES_SHRED) * 100.0))
	lines.append("閃避率   : %.1f%%" % (s.get_stat(StatTypes.Stat.DODGE) * 100.0))
	lines.append("格擋率   : %.1f%%" % (s.get_stat(StatTypes.Stat.BLOCK_RATE) * 100.0))
	lines.append("格擋減傷 : %.1f%%" % (s.get_stat(StatTypes.Stat.BLOCK_REDUCTION) * 100.0))
	lines.append("吸血     : %.1f%%" % (s.get_stat(StatTypes.Stat.LIFE_STEAL) * 100.0))
	lines.append("回血/秒  : %.1f" % s.get_stat(StatTypes.Stat.LIFE_REGEN))
	lines.append("")
	lines.append("火/冰/雷抗: %.0f/%.0f/%.0f%%" % [
		s.get_stat(StatTypes.Stat.FIRE_RES) * 100.0,
		s.get_stat(StatTypes.Stat.ICE_RES) * 100.0,
		s.get_stat(StatTypes.Stat.LIGHTNING_RES) * 100.0
	])
	lines.append("燃/凍/電/血機率: %.0f/%.0f/%.0f/%.0f%%" % [
		s.get_stat(StatTypes.Stat.BURN_CHANCE) * 100.0,
		s.get_stat(StatTypes.Stat.FREEZE_CHANCE) * 100.0,
		s.get_stat(StatTypes.Stat.SHOCK_CHANCE) * 100.0,
		s.get_stat(StatTypes.Stat.BLEED_CHANCE) * 100.0
	])
	stats_summary_label.text = "\n".join(lines)


func _position_tooltip() -> void:
	if item_tooltip == null:
		return

	var tip_size := item_tooltip.get_combined_minimum_size()
	var mouse_pos := get_global_mouse_position()
	var screen_size := get_viewport_rect().size

	var pos := mouse_pos + Vector2(16, 16)
	if pos.x + tip_size.x > screen_size.x:
		pos.x = mouse_pos.x - tip_size.x - 16
	if pos.y + tip_size.y > screen_size.y:
		pos.y = mouse_pos.y - tip_size.y - 16

	item_tooltip.global_position = pos



func _build_tooltip_text(item: EquipmentData, compare_item: EquipmentData = null) -> String:
	var rarity_color: Color = StatTypes.RARITY_COLORS.get(item.rarity, Color.WHITE)
	var rarity_hex := rarity_color.to_html(false)
	var rarity_name: String = StatTypes.RARITY_NAMES.get(item.rarity, "未知")

	var text := "[color=#%s][b]%s[/b][/color]\n" % [rarity_hex, item.display_name]
	text += "[color=gray]%s - %s[/color]\n\n" % [StatTypes.SLOT_NAMES.get(item.slot, ""), rarity_name]
	if Input.is_key_pressed(KEY_ALT):
		text += "[color=gray]iLvl: %d[/color]\n\n" % item.item_level

	# 基礎屬性
	if not item.base_stats.is_empty():
		for mod: StatModifier in item.base_stats:
			text += _format_modifier(mod) + "\n"
		text += "\n"

	# 前綴
	for affix: Affix in item.prefixes:
		var prefix_label := "[color=#8888ff]前綴 T%d[/color]" % _display_tier(affix.tier)
		if affix.stat_modifiers.is_empty():
			text += prefix_label + "\n"
		else:
			for i in range(affix.stat_modifiers.size()):
				var mod: StatModifier = affix.stat_modifiers[i]
				if i == 0:
					text += "%s  %s\n" % [prefix_label, _format_modifier(mod)]
				else:
					text += "  " + _format_modifier(mod) + "\n"

	# 後綴
	for affix: Affix in item.suffixes:
		var suffix_label := "[color=#88ff88]後綴 T%d[/color]" % _display_tier(affix.tier)
		if affix.stat_modifiers.is_empty():
			text += suffix_label + "\n"
		else:
			for i in range(affix.stat_modifiers.size()):
				var mod: StatModifier = affix.stat_modifiers[i]
				if i == 0:
					text += "%s  %s\n" % [suffix_label, _format_modifier(mod)]
				else:
					text += "  " + _format_modifier(mod) + "\n"

	if compare_item:
		text += "\n" + _build_compare_text(item, compare_item)

	return text


func _format_modifier(mod: StatModifier) -> String:
	var stat_name: String = StatTypes.Stat.keys()[mod.stat]
	var value_str: String

	if mod.modifier_type == StatModifier.ModifierType.PERCENT or _is_ratio_stat(mod.stat):
		value_str = "%+.1f%%" % (mod.value * 100)
	else:
		if is_equal_approx(mod.value, round(mod.value)):
			value_str = "%+d" % int(round(mod.value))
		else:
			value_str = "%+.2f" % mod.value

	# 翻譯屬性名稱
	var translated := _translate_stat_name(stat_name)
	return "%s %s" % [value_str, translated]


func _translate_stat_name(stat_name: String) -> String:
	var translations := {
		"HP": "生命值",
		"ATK": "攻擊力",
		"ATK_SPEED": "攻擊速度",
		"MOVE_SPEED": "移動速度",
		"DEF": "防禦力",
		"CRIT_RATE": "暴擊率",
		"CRIT_DMG": "暴擊傷害",
		"FINAL_DMG": "最終傷害",
		"PHYS_PEN": "物理穿透",
		"ELEMENTAL_PEN": "元素穿透",
		"ARMOR_SHRED": "破甲",
		"RES_SHRED": "抗性削減",
		"LIFE_STEAL": "生命竊取",
		"LIFE_REGEN": "生命回復",
		"DODGE": "閃避",
		"BLOCK_RATE": "格擋率",
		"BLOCK_REDUCTION": "格擋減傷",
		"PHYSICAL_DMG": "物理傷害",
		"FIRE_DMG": "火焰傷害",
		"ICE_DMG": "冰霜傷害",
		"LIGHTNING_DMG": "閃電傷害",
		"FIRE_RES": "火焰抗性",
		"ICE_RES": "冰霜抗性",
		"LIGHTNING_RES": "閃電抗性",
		"ALL_RES": "全部抗性",
		"BURN_CHANCE": "燃燒機率",
		"FREEZE_CHANCE": "凍結機率",
		"SHOCK_CHANCE": "感電機率",
		"BLEED_CHANCE": "流血機率",
		"BURN_DMG_BONUS": "燃燒傷害加成",
		"FREEZE_DURATION_BONUS": "凍結持續加成",
		"SHOCK_EFFECT_BONUS": "感電效果加成",
		"BLEED_DMG_BONUS": "流血傷害加成",
		"PHYS_TO_FIRE": "物理轉火焰",
		"PHYS_TO_ICE": "物理轉冰霜",
		"PHYS_TO_LIGHTNING": "物理轉閃電",
		"FIRE_TO_ICE": "火焰轉冰霜",
		"ICE_TO_LIGHTNING": "冰霜轉閃電",
		"DROP_RATE": "掉落率",
		"DROP_QUALITY": "掉落品質",
		"PICKUP_RANGE": "拾取範圍",
	}
	return translations.get(stat_name, stat_name)


func _build_compare_text(new_item: EquipmentData, old_item: EquipmentData) -> String:
	var lines: Array[String] = []
	var name_color: String = StatTypes.RARITY_COLORS.get(old_item.rarity, Color.WHITE).to_html(false)
	lines.append("[color=gray]對比已裝備：[/color][color=#%s]%s[/color]" % [name_color, old_item.display_name])

	var new_totals := _collect_item_modifiers(new_item)
	var old_totals := _collect_item_modifiers(old_item)
	var keys := new_totals.keys()
	for key in old_totals.keys():
		if not keys.has(key):
			keys.append(key)

	var delta_lines: Array[String] = []
	for key: String in keys:
		var new_value: float = new_totals.get(key, 0.0)
		var old_value: float = old_totals.get(key, 0.0)
		var delta := new_value - old_value
		if absf(delta) < 0.0001:
			continue
		var parts: PackedStringArray = key.split("|")
		var stat := int(parts[0])
		var modifier_type := int(parts[1])
		delta_lines.append(_format_delta(stat, modifier_type, delta))

	if delta_lines.is_empty():
		lines.append("[color=gray]無變化[/color]")
	else:
		lines.append_array(delta_lines)

	return "\n".join(lines)


func _collect_item_modifiers(item: EquipmentData) -> Dictionary:
	var totals: Dictionary = {}
	if item == null:
		return totals

	for mod: StatModifier in item.base_stats:
		_add_modifier_total(totals, mod)

	for affix: Affix in item.get_all_affixes():
		for mod: StatModifier in affix.stat_modifiers:
			_add_modifier_total(totals, mod)

	return totals


func _add_modifier_total(totals: Dictionary, mod: StatModifier) -> void:
	var key := "%d|%d" % [mod.stat, mod.modifier_type]
	totals[key] = totals.get(key, 0.0) + mod.value


func _format_delta(stat: int, modifier_type: int, delta: float) -> String:
	var stat_name: String = StatTypes.Stat.keys()[stat]
	var translated := _translate_stat_name(stat_name)
	var value_str: String

	if modifier_type == StatModifier.ModifierType.PERCENT or _is_ratio_stat(stat):
		value_str = "%+.1f%%" % (delta * 100)
	else:
		if is_equal_approx(delta, round(delta)):
			value_str = "%+d" % int(round(delta))
		else:
			value_str = "%+.2f" % delta

	var color := "green" if delta > 0.0 else "red"
	return "[color=%s]%s %s[/color]" % [color, value_str, translated]


func _is_ratio_stat(stat: int) -> bool:
	return stat in [
		StatTypes.Stat.CRIT_RATE,
		StatTypes.Stat.CRIT_DMG,
		StatTypes.Stat.FINAL_DMG,
		StatTypes.Stat.PHYS_PEN,
		StatTypes.Stat.ELEMENTAL_PEN,
		StatTypes.Stat.RES_SHRED,
		StatTypes.Stat.LIFE_STEAL,
		StatTypes.Stat.DODGE,
		StatTypes.Stat.BLOCK_RATE,
		StatTypes.Stat.BLOCK_REDUCTION,
		StatTypes.Stat.FIRE_RES,
		StatTypes.Stat.ICE_RES,
		StatTypes.Stat.LIGHTNING_RES,
		StatTypes.Stat.ALL_RES,
		StatTypes.Stat.BURN_CHANCE,
		StatTypes.Stat.FREEZE_CHANCE,
		StatTypes.Stat.SHOCK_CHANCE,
		StatTypes.Stat.BLEED_CHANCE,
		StatTypes.Stat.BURN_DMG_BONUS,
		StatTypes.Stat.FREEZE_DURATION_BONUS,
		StatTypes.Stat.SHOCK_EFFECT_BONUS,
		StatTypes.Stat.BLEED_DMG_BONUS,
		StatTypes.Stat.DROP_RATE,
		StatTypes.Stat.DROP_QUALITY,
		StatTypes.Stat.PICKUP_RANGE,
		StatTypes.Stat.PHYS_TO_FIRE,
		StatTypes.Stat.PHYS_TO_ICE,
		StatTypes.Stat.PHYS_TO_LIGHTNING,
		StatTypes.Stat.FIRE_TO_ICE,
		StatTypes.Stat.ICE_TO_LIGHTNING,
	]


func _display_tier(raw_tier: int) -> int:
	var clamped := clampi(raw_tier, 1, 5)
	return 6 - clamped
