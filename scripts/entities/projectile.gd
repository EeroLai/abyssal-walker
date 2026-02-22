class_name Projectile
extends Node2D

var damage_result: DamageCalculator.DamageResult
var support_mods: Dictionary
var source: Node
var target: Node2D
var target_position: Vector2
var speed: float = 450.0
var is_tracking: bool = false
var explosion_radius: float = 0.0
var pierce_remaining: int = 0
var chain_remaining: int = 0
var _aim_direction: Vector2 = Vector2.RIGHT
var _hit_targets: Dictionary = {}

var _color: Color = Color.WHITE
var _lifetime: float = 4.0
const HIT_RADIUS: float = 14.0
const CHAIN_SEARCH_RADIUS: float = 240.0


func setup(
	src: Node,
	tgt: Node2D,
	dmg: DamageCalculator.DamageResult,
	mods: Dictionary,
	tracking: bool,
	proj_color: Color,
	aim_direction: Vector2 = Vector2.ZERO,
	projectile_speed: float = 450.0,
	explosion_radius_value: float = 0.0,
	pierce_count: int = 0,
	chain_count: int = 0
) -> void:
	source = src
	target = tgt
	target_position = tgt.global_position if is_instance_valid(tgt) else src.global_position
	damage_result = dmg
	support_mods = mods
	is_tracking = tracking
	_color = proj_color
	speed = projectile_speed
	explosion_radius = maxf(explosion_radius_value, 0.0)
	pierce_remaining = max(0, pierce_count)
	chain_remaining = max(0, chain_count)
	_hit_targets.clear()
	_aim_direction = aim_direction.normalized()
	if _aim_direction == Vector2.ZERO:
		_aim_direction = (target_position - global_position).normalized()
	if _aim_direction == Vector2.ZERO:
		_aim_direction = Vector2.RIGHT
	if not is_tracking:
		target_position = global_position + _aim_direction * 2000.0
	rotation = _aim_direction.angle()
	queue_redraw()


func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		if explosion_radius > 0.0:
			_deal_explosion_damage()
		queue_free()
		return

	if is_tracking and target and is_instance_valid(target) and not _is_dead(target):
		target_position = target.global_position

	var dist := global_position.distance_to(target_position)
	if dist < HIT_RADIUS:
		_on_reach_target()
		return

	var dir := (target_position - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = _aim_direction
	global_position += dir * speed * delta
	rotation = dir.angle()
	_check_overlap_hit()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, _color)
	draw_circle(Vector2.ZERO, 3.0, _color.lightened(0.4))
	draw_line(Vector2(-12.0, 0.0), Vector2(-4.0, 0.0),
		Color(_color.r, _color.g, _color.b, 0.5), 2.5)


func _on_reach_target() -> void:
	if explosion_radius > 0.0:
		_deal_explosion_damage()
		queue_free()
	elif target and is_instance_valid(target) and not _is_dead(target):
		_handle_target_hit(target)
	else:
		queue_free()


func _deal_damage_to_target(tgt: Node) -> void:
	if not tgt.has_method("take_damage"):
		return
	tgt.take_damage(damage_result, source)

	if source and source.has_method("on_projectile_hit"):
		source.on_projectile_hit(tgt, damage_result, support_mods)


func _handle_target_hit(tgt: Node2D) -> void:
	if tgt == null or not is_instance_valid(tgt):
		return
	var key := str(tgt.get_instance_id())
	if _hit_targets.has(key):
		return
	_hit_targets[key] = true
	_deal_damage_to_target(tgt)

	if chain_remaining > 0:
		var next_target := _find_chain_target(tgt)
		chain_remaining -= 1
		if next_target != null:
			target = next_target
			target_position = next_target.global_position
			is_tracking = true
			return

	if pierce_remaining > 0:
		pierce_remaining -= 1
		target = null
		target_position = global_position + _aim_direction * 2000.0
		return

	queue_free()


func _check_overlap_hit() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not (enemy is Node2D):
			continue
		var enemy_node := enemy as Node2D
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node.has_method("is_dead") and enemy_node.is_dead():
			continue
		if enemy_node.global_position.distance_squared_to(global_position) <= HIT_RADIUS * HIT_RADIUS:
			_handle_target_hit(enemy_node)
			return


func _find_chain_target(from_target: Node2D) -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var best: Node2D = null
	var best_dist_sq := INF
	var max_dist_sq := CHAIN_SEARCH_RADIUS * CHAIN_SEARCH_RADIUS

	for enemy in enemies:
		if not (enemy is Node2D):
			continue
		var enemy_node := enemy as Node2D
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node == from_target:
			continue
		if enemy_node.has_method("is_dead") and enemy_node.is_dead():
			continue
		var key := str(enemy_node.get_instance_id())
		if _hit_targets.has(key):
			continue

		var dist_sq := enemy_node.global_position.distance_squared_to(from_target.global_position)
		if dist_sq > max_dist_sq:
			continue
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = enemy_node

	return best


func _deal_explosion_damage() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var radius_sq := explosion_radius * explosion_radius

	for enemy in enemies:
		if not (enemy is Node2D):
			continue
		var enemy_node := enemy as Node2D
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node.has_method("is_dead") and enemy_node.is_dead():
			continue
		if enemy_node.global_position.distance_squared_to(global_position) > radius_sq:
			continue
		_deal_damage_to_target(enemy_node)


func _is_dead(node: Node) -> bool:
	if node.has_method("is_dead"):
		return node.is_dead()
	return false
