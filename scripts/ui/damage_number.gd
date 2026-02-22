class_name DamageNumber
extends Node2D

@onready var label: Label = $Label

var damage: float = 0.0
var is_crit: bool = false
var element: StatTypes.Element = StatTypes.Element.PHYSICAL

const FLOAT_SPEED := 50.0
const FADE_TIME := 0.8
const SPREAD := 20.0


func _ready() -> void:
	# 隨機偏移
	position.x += randf_range(-SPREAD, SPREAD)

	# 設定文字
	label.text = str(int(damage))

	# 設定顏色和大小
	var base_color := _get_element_color()
	if is_crit:
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.98))
		label.add_theme_constant_override("outline_size", 3)
		# 暴擊彈跳效果
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.08)
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	else:
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", base_color)
		label.remove_theme_color_override("font_outline_color")
		label.remove_theme_constant_override("outline_size")

	# 上浮並淡出
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 40, FADE_TIME)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME).set_delay(FADE_TIME * 0.5)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func _get_element_color() -> Color:
	match element:
		StatTypes.Element.FIRE:
			return Color(1.0, 0.5, 0.2)
		StatTypes.Element.ICE:
			return Color(0.5, 0.8, 1.0)
		StatTypes.Element.LIGHTNING:
			return Color(1.0, 1.0, 0.4)
		_:
			return Color.WHITE


func setup(dmg: float, crit: bool, elem: StatTypes.Element = StatTypes.Element.PHYSICAL) -> void:
	damage = dmg
	is_crit = crit
	element = elem
