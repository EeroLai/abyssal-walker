class_name StatusController
extends Node

## 管理目標身上的狀態效果

var owner_node: Node = null
var active: Dictionary = {}  # status_type -> StatusEffect


func _ready() -> void:
	owner_node = get_parent()


func _enter_tree() -> void:
	if owner_node == null:
		owner_node = get_parent()


func apply_status(
	status_type: String,
	source_damage: float,
	attacker_stats: StatContainer
) -> void:
	var effect := _build_effect(status_type, source_damage, attacker_stats)
	if effect == null:
		return

	if active.has(status_type):
		var existing: StatusEffect = active[status_type]
		existing.duration = maxf(existing.duration, effect.duration)
		existing.magnitude = maxf(existing.magnitude, effect.magnitude)
		existing.reset_timer()
	else:
		active[status_type] = effect

	_on_status_applied(status_type, effect)


func _process(delta: float) -> void:
	if active.is_empty():
		return

	var to_remove: Array[String] = []
	for key in active.keys():
		var effect: StatusEffect = active[key]
		effect.elapsed += delta
		effect.tick_elapsed += delta

		if effect.tick_interval > 0.0 and effect.tick_elapsed >= effect.tick_interval:
			var ticks := int(effect.tick_elapsed / effect.tick_interval)
			effect.tick_elapsed -= ticks * effect.tick_interval
			_apply_tick(effect, ticks)

		if effect.elapsed >= effect.duration:
			to_remove.append(key)

	for key in to_remove:
		var old: StatusEffect = active[key]
		active.erase(key)
		_on_status_removed(key, old)


func is_frozen() -> bool:
	return active.has("freeze")


func get_damage_taken_multiplier() -> float:
	if not active.has("shock"):
		return 1.0
	var effect: StatusEffect = active["shock"]
	return 1.0 + effect.magnitude


func _build_effect(
	status_type: String,
	source_damage: float,
	attacker_stats: StatContainer
) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.status_type = status_type

	match status_type:
		"burn":
			var bonus := attacker_stats.get_stat(StatTypes.Stat.BURN_DMG_BONUS)
			effect.duration = Constants.BURN_DURATION
			effect.tick_interval = 1.0
			effect.magnitude = source_damage * Constants.BURN_BASE_MULTIPLIER * (1.0 + bonus)
		"bleed":
			var bonus2 := attacker_stats.get_stat(StatTypes.Stat.BLEED_DMG_BONUS)
			effect.duration = Constants.BLEED_DURATION
			effect.tick_interval = 1.0
			effect.magnitude = source_damage * Constants.BLEED_BASE_MULTIPLIER * (1.0 + bonus2)
		"freeze":
			var bonus3 := attacker_stats.get_stat(StatTypes.Stat.FREEZE_DURATION_BONUS)
			var duration := Constants.FREEZE_BASE_DURATION * (1.0 + bonus3)
			effect.duration = minf(duration, Constants.FREEZE_MAX_DURATION)
			effect.tick_interval = 0.0
			effect.magnitude = 0.0
		"shock":
			var bonus4 := attacker_stats.get_stat(StatTypes.Stat.SHOCK_EFFECT_BONUS)
			var shock_bonus := Constants.SHOCK_BASE_BONUS + bonus4
			shock_bonus = minf(shock_bonus, Constants.SHOCK_MAX_BONUS)
			effect.duration = Constants.SHOCK_DURATION
			effect.tick_interval = 0.0
			effect.magnitude = shock_bonus
		_:
			return null

	return effect


func _apply_tick(effect: StatusEffect, ticks: int) -> void:
	if effect.magnitude <= 0.0:
		return

	var total_damage := effect.magnitude * ticks
	match effect.status_type:
		"burn":
			_apply_dot_damage(total_damage, StatTypes.Element.FIRE, effect.status_type)
		"bleed":
			if _is_owner_moving():
				_apply_dot_damage(total_damage, StatTypes.Element.PHYSICAL, effect.status_type)


func _apply_dot_damage(amount: float, element: StatTypes.Element, status_type: String) -> void:
	if owner_node == null or not is_instance_valid(owner_node):
		return

	if owner_node.has_method("apply_status_damage"):
		owner_node.apply_status_damage(amount, element)

	EventBus.status_tick.emit(owner_node, status_type, amount)


func _on_status_applied(status_type: String, effect: StatusEffect) -> void:
	if owner_node == null or not is_instance_valid(owner_node):
		return
	EventBus.status_applied.emit(owner_node, status_type, effect.stacks)


func _on_status_removed(status_type: String, effect: StatusEffect) -> void:
	if owner_node == null or not is_instance_valid(owner_node):
		return
	EventBus.status_removed.emit(owner_node, status_type)


func _is_owner_moving() -> bool:
	if owner_node == null or not is_instance_valid(owner_node):
		return false
	if owner_node is CharacterBody2D:
		var body: CharacterBody2D = owner_node
		return body.velocity.length() > 1.0
	return false
