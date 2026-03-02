class_name TutorialOverlay
extends Control

const HIGHLIGHT_PADDING := 10.0
const CARD_MARGIN := 18.0
const CARD_WIDTH := 360.0

@onready var dim_rect: ColorRect = $Dim
@onready var highlight: PanelContainer = $Highlight
@onready var card: PanelContainer = $Card
@onready var title_label: Label = $Card/Margin/VBox/Title
@onready var body_label: Label = $Card/Margin/VBox/Body
@onready var continue_button: Button = $Card/Margin/VBox/Buttons/ContinueButton
@onready var skip_button: Button = $Card/Margin/VBox/Buttons/SkipButton

var _target: Control = null
var _pending_action: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_rect.color = Color(0.02, 0.04, 0.08, 0.74)
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var highlight_style := StyleBoxFlat.new()
	highlight_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	highlight_style.border_color = Color(0.94, 0.8, 0.42, 0.98)
	highlight_style.set_border_width_all(3)
	highlight_style.set_corner_radius_all(12)
	highlight.add_theme_stylebox_override("panel", highlight_style)

	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.11, 0.16, 0.98)
	card_style.border_color = Color(0.34, 0.56, 0.78, 0.98)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(14)
	card_style.content_margin_left = 16.0
	card_style.content_margin_top = 16.0
	card_style.content_margin_right = 16.0
	card_style.content_margin_bottom = 16.0
	card.add_theme_stylebox_override("panel", card_style)

	title_label.add_theme_font_size_override("font_size", 22)
	title_label.modulate = Color(0.94, 0.98, 1.0, 1.0)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.modulate = Color(0.84, 0.91, 0.98, 1.0)

	continue_button.custom_minimum_size = Vector2(112.0, 34.0)
	skip_button.custom_minimum_size = Vector2(112.0, 34.0)
	continue_button.pressed.connect(_on_continue_pressed)
	skip_button.pressed.connect(_on_skip_pressed)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_layout()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
			_finish("continue")
			accept_event()
			return
		if key_event.keycode == KEY_ESCAPE and skip_button.visible:
			_finish("skip")
			accept_event()


func present(
	target: Control,
	title: String,
	body: String,
	continue_text: String,
	skip_text: String = ""
) -> String:
	_target = target
	_pending_action = ""
	title_label.text = title
	body_label.text = body
	continue_button.text = continue_text
	skip_button.visible = not skip_text.is_empty()
	skip_button.text = skip_text
	visible = true
	await get_tree().process_frame
	_update_layout()
	continue_button.grab_focus()

	while _pending_action.is_empty():
		await get_tree().process_frame

	visible = false
	return _pending_action


func _update_layout() -> void:
	var viewport_rect := get_viewport_rect()
	size = viewport_rect.size
	var target_rect := _get_target_rect()
	highlight.visible = _rect_has_area(target_rect)

	if highlight.visible:
		highlight.global_position = target_rect.position - Vector2.ONE * HIGHLIGHT_PADDING
		highlight.size = target_rect.size + Vector2.ONE * HIGHLIGHT_PADDING * 2.0

	var card_size := card.size
	if card_size.x <= 0.0:
		card_size.x = CARD_WIDTH
	if card_size.y <= 0.0:
		card_size.y = 180.0

	var card_pos := Vector2(
		(viewport_rect.size.x - card_size.x) * 0.5,
		viewport_rect.size.y - card_size.y - 44.0
	)
	if _rect_has_area(target_rect):
		var below_y := target_rect.end.y + CARD_MARGIN
		var above_y := target_rect.position.y - card_size.y - CARD_MARGIN
		card_pos.x = clampf(
			target_rect.position.x + (target_rect.size.x - card_size.x) * 0.5,
			24.0,
			maxf(24.0, viewport_rect.size.x - card_size.x - 24.0)
		)
		card_pos.y = below_y if below_y + card_size.y <= viewport_rect.size.y - 24.0 else above_y
		card_pos.y = clampf(card_pos.y, 24.0, maxf(24.0, viewport_rect.size.y - card_size.y - 24.0))

	card.global_position = card_pos


func _get_target_rect() -> Rect2:
	if _target == null or not is_instance_valid(_target):
		return Rect2()
	if not _target.is_visible_in_tree():
		return Rect2()
	return _target.get_global_rect()


func _rect_has_area(rect: Rect2) -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0


func _on_continue_pressed() -> void:
	_finish("continue")


func _on_skip_pressed() -> void:
	_finish("skip")


func _finish(action: String) -> void:
	if _pending_action.is_empty():
		_pending_action = action
