class_name EnemyBase
extends CharacterBody2D

signal died(enemy: EnemyBase)

@export var enemy_id: String = "slime"
@export var display_name: String = "史萊姆"

# 基礎數值
@export var base_hp: float = 30.0
@export var base_atk: float = 5.0
@export var base_def: float = 0.0
@export var move_speed: float = 40.0
@export var atk_range: float = 30.0
@export var atk_speed: float = 0.8
@export var experience: float = 10.0
@export var behavior: String = "chase"

# 元素屬性
@export var element: StatTypes.Element = StatTypes.Element.PHYSICAL
@export var resistances: Dictionary = {}

# 狀態
var current_hp: float
var is_elite: bool = false
var is_boss: bool = false
var _is_dead: bool = false
var status_controller: StatusController

# 目標
var target: Node2D = null

# 層數倍率
var hp_multiplier: float = 1.0
var atk_multiplier: float = 1.0
var elite_mods: Array[String] = []
var _elite_rage_applied: bool = false
var _elite_life_leech_ratio: float = 0.0
var _elite_thorns_ratio: float = 0.0
var _elite_death_burst: bool = false
var _elite_death_burst_radius: float = 80.0
var _elite_death_burst_multiplier: float = 1.2
var _external_velocity: Vector2 = Vector2.ZERO
var _rank_ring: Line2D = null
var _rank_label: Label = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var attack_timer: Timer = $AttackTimer


func _ready() -> void:
	add_to_group("enemies")
	status_controller = StatusController.new()
	add_child(status_controller)
	current_hp = get_max_hp()
	_setup_attack_timer()
	_find_player()
	_apply_rank_visual_marker()


func _setup_attack_timer() -> void:
	if attack_timer:
		attack_timer.wait_time = 1.0 / atk_speed
		attack_timer.timeout.connect(_on_attack_timer_timeout)


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		target = players[0]


func _physics_process(delta: float) -> void:
	if _is_dead or target == null:
		return

	if status_controller and status_controller.is_frozen():
		velocity = Vector2.ZERO
		attack_timer.stop()
		return

	if not is_instance_valid(target):
		_find_player()
		return
	_apply_elite_runtime_states()

	var distance := global_position.distance_to(target.global_position)
	var engage_distance := _get_engage_distance()

	# 進入攻擊距離就能出手；是否停下則由 engage_distance 控制。
	if distance <= atk_range:
		if attack_timer.is_stopped():
			attack_timer.start()
	else:
		attack_timer.stop()

	if distance <= engage_distance:
		# 近身停下來攻擊
		velocity = Vector2.ZERO
	else:
		# 追蹤玩家
		var direction := (target.global_position - global_position).normalized()
		velocity = direction * move_speed

	if _external_velocity.length_squared() > 0.01:
		velocity += _external_velocity
		_external_velocity = _external_velocity.move_toward(Vector2.ZERO, 650.0 * delta)

	move_and_slide()

	# 更新朝向
	if velocity.x != 0 and sprite:
		sprite.flip_h = velocity.x < 0


func get_max_hp() -> float:
	return base_hp * hp_multiplier


func get_attack_damage() -> float:
	return base_atk * atk_multiplier


func get_current_hp() -> float:
	return current_hp


func is_dead() -> bool:
	return _is_dead


func take_damage(damage_result: DamageCalculator.DamageResult, attacker: Node) -> void:
	if _is_dead:
		return

	# 簡化的受傷計算（敵人用簡單的防禦公式）
	var total_damage := damage_result.total_damage
	var attacker_stats: StatContainer = _extract_attacker_stats(attacker)
	var armor_shred: float = 0.0
	var phys_pen: float = 0.0
	var element_pen: float = 0.0
	var res_shred: float = 0.0
	if attacker_stats != null:
		armor_shred = maxf(attacker_stats.get_stat(StatTypes.Stat.ARMOR_SHRED), 0.0)
		phys_pen = clampf(attacker_stats.get_stat(StatTypes.Stat.PHYS_PEN), 0.0, 0.95)
		element_pen = clampf(attacker_stats.get_stat(StatTypes.Stat.ELEMENTAL_PEN), 0.0, 0.95)
		res_shred = clampf(attacker_stats.get_stat(StatTypes.Stat.RES_SHRED), 0.0, 0.95)

	# 應用抗性
	total_damage -= damage_result.fire_damage * _get_effective_resistance("fire", element_pen, res_shred)
	total_damage -= damage_result.ice_damage * _get_effective_resistance("ice", element_pen, res_shred)
	total_damage -= damage_result.lightning_damage * _get_effective_resistance("lightning", element_pen, res_shred)

	# 應用防禦
	var effective_def: float = maxf(base_def - armor_shred, 0.0)
	var def_reduction := effective_def / (effective_def + 50.0)
	def_reduction *= (1.0 - phys_pen)
	total_damage *= (1.0 - def_reduction)
	if status_controller:
		total_damage *= status_controller.get_damage_taken_multiplier()

	total_damage = maxf(total_damage, 1.0)  # 最少造成 1 點傷害
	current_hp -= total_damage
	if _elite_thorns_ratio > 0.0:
		_apply_thorns(attacker, total_damage)

	# 顯示傷害數字
	_spawn_damage_number(total_damage, damage_result, attacker)

	# 受擊反饋
	_on_hit()

	if current_hp <= 0:
		_die()


func apply_status_damage(amount: float, element: StatTypes.Element) -> void:
	if _is_dead:
		return
	current_hp -= amount
	if current_hp <= 0:
		_die()


func _spawn_damage_number(damage: float, damage_result: DamageCalculator.DamageResult, source: Node) -> void:
	# 發送事件，讓 UI 系統處理
	var display_element := _get_primary_damage_element(damage_result)
	var damage_info: Dictionary = {
		"damage": damage,
		"final_damage": damage,
		"is_crit": damage_result.is_crit,
		"position": global_position + Vector2(0, -20),
		"element": display_element,
	}
	EventBus.damage_dealt.emit(source, self, damage_info)


func _get_primary_damage_element(damage_result: DamageCalculator.DamageResult) -> StatTypes.Element:
	var physical := maxf(damage_result.physical_damage, 0.0)
	var fire := maxf(damage_result.fire_damage, 0.0)
	var ice := maxf(damage_result.ice_damage, 0.0)
	var lightning := maxf(damage_result.lightning_damage, 0.0)

	var max_value := physical
	var result := StatTypes.Element.PHYSICAL
	if fire > max_value:
		max_value = fire
		result = StatTypes.Element.FIRE
	if ice > max_value:
		max_value = ice
		result = StatTypes.Element.ICE
	if lightning > max_value:
		result = StatTypes.Element.LIGHTNING

	return result


func _on_hit() -> void:
	# 受擊閃爍效果
	if sprite:
		var original_color: Color = sprite.shape_color if "shape_color" in sprite else sprite.modulate
		var tween := create_tween()
		if "shape_color" in sprite:
			tween.tween_property(sprite, "shape_color", Color.WHITE, 0.05)
			tween.tween_property(sprite, "shape_color", original_color, 0.1)
		else:
			tween.tween_property(sprite, "modulate", Color.RED, 0.05)
			tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)


func _die() -> void:
	_is_dead = true
	attack_timer.stop()
	if _elite_death_burst:
		_trigger_death_burst()

	# 發送死亡事件
	died.emit(self)
	EventBus.enemy_died.emit(self, global_position)

	# 死亡動畫
	if sprite:
		var tween := create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 0.2)
		tween.tween_callback(queue_free)
	else:
		queue_free()


func _on_attack_timer_timeout() -> void:
	if _is_dead or target == null or not is_instance_valid(target):
		return

	var distance := global_position.distance_to(target.global_position)
	if distance > atk_range:
		return

	# 對玩家造成傷害
	if target.has_method("take_damage"):
		var damage_result := DamageCalculator.DamageResult.new()

		match element:
			StatTypes.Element.PHYSICAL:
				damage_result.physical_damage = get_attack_damage()
			StatTypes.Element.FIRE:
				damage_result.fire_damage = get_attack_damage()
			StatTypes.Element.ICE:
				damage_result.ice_damage = get_attack_damage()
			StatTypes.Element.LIGHTNING:
				damage_result.lightning_damage = get_attack_damage()

		damage_result.total_damage = get_attack_damage()
		target.take_damage(damage_result, self)
		if _elite_life_leech_ratio > 0.0:
			heal(get_attack_damage() * _elite_life_leech_ratio)


func apply_floor_multipliers(hp_mult: float, atk_mult: float) -> void:
	hp_multiplier = hp_mult
	atk_multiplier = atk_mult
	current_hp = get_max_hp()


func reset() -> void:
	_is_dead = false
	current_hp = get_max_hp()
	target = null
	velocity = Vector2.ZERO
	elite_mods.clear()
	_elite_rage_applied = false
	_elite_life_leech_ratio = 0.0
	_elite_thorns_ratio = 0.0
	_elite_death_burst = false
	_external_velocity = Vector2.ZERO
	if sprite:
		sprite.modulate = Color.WHITE


func get_status_controller() -> StatusController:
	return status_controller


func heal(amount: float) -> void:
	current_hp = minf(current_hp + amount, get_max_hp())


func apply_elite_mods(mods: Array[String]) -> void:
	elite_mods = mods.duplicate()
	if elite_mods.is_empty():
		return
	is_elite = true
	var original_name := display_name
	for mod in elite_mods:
		match mod:
			"swift":
				move_speed *= 1.35
				atk_speed *= 1.20
			"armored":
				base_def += 10.0
				hp_multiplier *= 1.25
			"elemental_shield":
				resistances["fire"] = clampf(float(resistances.get("fire", 0.0)) + 0.25, 0.0, 0.9)
				resistances["ice"] = clampf(float(resistances.get("ice", 0.0)) + 0.25, 0.0, 0.9)
				resistances["lightning"] = clampf(float(resistances.get("lightning", 0.0)) + 0.25, 0.0, 0.9)
			"rage":
				pass
			"lifeleech":
				_elite_life_leech_ratio += 0.25
			"thorns":
				_elite_thorns_ratio += 0.08
			"death_burst":
				_elite_death_burst = true
			_:
				pass

	if attack_timer:
		attack_timer.wait_time = maxf(0.08, 1.0 / maxf(atk_speed, 0.1))
	current_hp = get_max_hp()
	display_name = _build_elite_display_name(original_name)
	_apply_rank_visual_marker()


func _build_elite_display_name(base_name: String) -> String:
	if elite_mods.is_empty():
		return base_name
	var labels := {
		"swift": "迅捷",
		"armored": "厚甲",
		"elemental_shield": "元素盾",
		"rage": "狂怒",
		"lifeleech": "吸血",
		"thorns": "尖刺",
		"death_burst": "爆裂",
	}
	var parts: Array[String] = []
	for mod in elite_mods:
		parts.append(str(labels.get(mod, mod)))
	return "[精英:%s] %s" % ["+".join(parts), base_name]


func _apply_elite_runtime_states() -> void:
	if elite_mods.has("rage") and not _elite_rage_applied and current_hp <= get_max_hp() * 0.35:
		_elite_rage_applied = true
		atk_multiplier *= 1.5
		move_speed *= 1.2
		if sprite:
			sprite.modulate = sprite.modulate.lightened(0.18)


func _get_effective_resistance(element_key: String, pen: float, shred: float) -> float:
	var base_res: float = float(resistances.get(element_key, 0.0))
	return clampf(base_res - pen - shred, -0.5, 0.9)


func _extract_attacker_stats(attacker: Node) -> StatContainer:
	if attacker == null:
		return null
	if "stats" in attacker:
		return attacker.stats
	return null


func _apply_thorns(attacker: Node, incoming_damage: float) -> void:
	if attacker == null or not attacker.has_method("take_damage"):
		return
	var reflected: float = maxf(incoming_damage * _elite_thorns_ratio, 1.0)
	var result := DamageCalculator.DamageResult.new()
	result.physical_damage = reflected
	result.total_damage = reflected
	attacker.take_damage(result, self)


func _trigger_death_burst() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > _elite_death_burst_radius:
		return
	if not target.has_method("take_damage"):
		return
	var dmg := maxf(get_attack_damage() * _elite_death_burst_multiplier, 1.0)
	var result := DamageCalculator.DamageResult.new()
	result.physical_damage = dmg
	result.total_damage = dmg
	target.take_damage(result, self)


func _apply_rank_visual_marker() -> void:
	if sprite == null:
		return
	if is_boss:
		sprite.scale = Vector2(1.45, 1.45)
		if "shape_color" in sprite:
			sprite.shape_color = Color(1.0, 0.25, 0.32, 1.0)
			if "shape_type" in sprite:
				sprite.shape_type = 1
		else:
			sprite.modulate = Color(1.0, 0.25, 0.32, 1.0)
		if not display_name.begins_with("【BOSS】"):
			display_name = "【BOSS】%s" % display_name
		_ensure_rank_ring(Color(1.0, 0.2, 0.25, 0.95), 18.0, 2.8)
		_ensure_rank_label("BOSS", Color(1.0, 0.3, 0.35, 1.0))
		return
	if is_elite:
		sprite.scale = Vector2(1.22, 1.22)
		if "shape_color" in sprite:
			sprite.shape_color = Color(1.0, 0.82, 0.25, 1.0)
			if "shape_type" in sprite:
				sprite.shape_type = 2
		else:
			sprite.modulate = Color(1.0, 0.82, 0.25, 1.0)
		_ensure_rank_ring(Color(1.0, 0.82, 0.25, 0.9), 14.0, 2.0)
		_clear_rank_label()
		return
	_clear_rank_ring()
	_clear_rank_label()


func _ensure_rank_ring(color: Color, radius: float, width: float) -> void:
	if _rank_ring == null:
		_rank_ring = Line2D.new()
		_rank_ring.z_index = -1
		add_child(_rank_ring)
	_rank_ring.clear_points()
	var points := 32
	for i in range(points + 1):
		var t := TAU * float(i) / float(points)
		_rank_ring.add_point(Vector2(cos(t), sin(t)) * radius)
	_rank_ring.default_color = color
	_rank_ring.width = width


func _clear_rank_ring() -> void:
	if _rank_ring != null:
		_rank_ring.queue_free()
		_rank_ring = null


func _ensure_rank_label(text: String, color: Color) -> void:
	if _rank_label == null:
		_rank_label = Label.new()
		_rank_label.position = Vector2(-18, -34)
		_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rank_label.add_theme_font_size_override("font_size", 13)
		add_child(_rank_label)
	_rank_label.text = text
	_rank_label.modulate = color


func _clear_rank_label() -> void:
	if _rank_label != null:
		_rank_label.queue_free()
		_rank_label = null


func _get_engage_distance() -> float:
	if behavior == "ranged" or behavior == "hit_and_run":
		return atk_range
	var contact_distance := _get_body_radius(self) + _get_body_radius(target) + 4.0
	return minf(atk_range, contact_distance)


func _get_body_radius(node: Node) -> float:
	if node == null:
		return 10.0
	var shape_node := node.get_node_or_null("CollisionShape2D")
	if shape_node is CollisionShape2D:
		var collision := shape_node as CollisionShape2D
		if collision.shape is CircleShape2D:
			var circle := collision.shape as CircleShape2D
			return circle.radius
	return 10.0


func apply_knockback(source_position: Vector2, force: float) -> void:
	if _is_dead:
		return
	var clamped_force := clampf(force, 0.0, 1200.0)
	if clamped_force <= 0.0:
		return
	var dir := (global_position - source_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var weight := 1.0
	if is_elite:
		weight *= 0.6
	if is_boss:
		weight *= 0.35
	_external_velocity += dir * clamped_force * weight
