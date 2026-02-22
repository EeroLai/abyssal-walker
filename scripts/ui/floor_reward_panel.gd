class_name FloorRewardPanel
extends Control

signal reward_selected(gem: Resource)

const PANEL_HALF_SIZE := Vector2(330, 150)

var title_label: Label
var buttons: Array[Button] = []
var reward_options: Array[Resource] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.55)
	add_child(dimmer)

	var panel_root := PanelContainer.new()
	panel_root.anchor_left = 0.5
	panel_root.anchor_top = 0.5
	panel_root.anchor_right = 0.5
	panel_root.anchor_bottom = 0.5
	panel_root.offset_left = -PANEL_HALF_SIZE.x
	panel_root.offset_top = -PANEL_HALF_SIZE.y
	panel_root.offset_right = PANEL_HALF_SIZE.x
	panel_root.offset_bottom = PANEL_HALF_SIZE.y
	add_child(panel_root)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.16, 0.98)
	panel_style.border_color = Color(0.45, 0.45, 0.55)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_bottom = 12
	panel_root.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel_root.add_child(vbox)

	title_label = Label.new()
	title_label.text = "樓層獎勵"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title_label)

	var sub := Label.new()
	sub.text = "請選擇 1 顆寶石"
	sub.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	vbox.add_child(sub)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	for i in range(3):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(200, 84)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_pick.bind(i))
		hbox.add_child(btn)
		buttons.append(btn)


func open_with_rewards(floor_number: int, options: Array[Resource]) -> void:
	reward_options = options
	title_label.text = "第 %d 層獎勵" % floor_number
	for i in range(buttons.size()):
		var btn := buttons[i]
		if i < reward_options.size() and reward_options[i] != null:
			btn.visible = true
			btn.disabled = false
			btn.text = _build_gem_text(reward_options[i])
		else:
			btn.visible = false
	visible = true
	get_tree().paused = true


func _build_gem_text(gem: Resource) -> String:
	if gem is SkillGem:
		var skill: SkillGem = gem
		return "技能\n%s\nLv.%d" % [skill.display_name, skill.level]
	if gem is SupportGem:
		var support: SupportGem = gem
		return "輔助\n%s\nLv.%d" % [support.display_name, support.level]
	return "未知獎勵"


func _on_pick(index: int) -> void:
	if index < 0 or index >= reward_options.size():
		return
	var picked: Resource = reward_options[index]
	if picked == null:
		return
	visible = false
	get_tree().paused = false
	reward_selected.emit(picked)
