class_name Player
extends CharacterBody2D

signal health_changed(current: float, max_hp: float)
signal died

const PROJECTILE_SCENE := preload("res://scenes/entities/projectile.tscn")
const MELEE_EFFECT_SCENE := preload("res://scenes/effects/melee_effect.tscn")
const ARROW_RAIN_EFFECT_SCENE := preload("res://scenes/effects/arrow_rain_effect.tscn")
const SHADOW_STRIKE_OFFSET := 28.0
const STAB_FINISHER_MULTIPLIER := 1.6
const ARC_CHAIN_SEARCH_RADIUS := 240.0
const ARC_UNUSED_CHAIN_MORE_PER_STACK := 0.05

@export var pickup_range: float = 50.0
@export var virtual_wall_margin: float = 80.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var pickup_area: Area2D = $PickupArea
@onready var attack_timer: Timer = $AttackTimer
@onready var hitbox: Area2D = $Hitbox

var stats: StatContainer
var gem_link: GemLink
var status_controller: StatusController
var equipment: Dictionary = {}  # EquipmentSlot -> EquipmentData
var inventory: Array[EquipmentData] = []  # 背包
var skill_gem_inventory: Array[SkillGem] = []
var support_gem_inventory: Array[SupportGem] = []
var materials: Dictionary = {}  # material_id -> count
var core_board: CoreBoard
var module_inventory: Array[Module] = []

const MAX_INVENTORY_SIZE: int = 60
const MAX_SKILL_GEM_INVENTORY: int = Constants.MAX_SKILL_GEM_INVENTORY
const MAX_SUPPORT_GEM_INVENTORY: int = Constants.MAX_SUPPORT_GEM_INVENTORY
const MAX_MODULE_INVENTORY: int = Constants.MAX_MODULE_INVENTORY

var current_hp: float = 100.0
var is_dead: bool = false

# AI 相關
var ai: PlayerAI
var current_target: Node2D = null


func _ready() -> void:
	_initialize_stats()
	_initialize_gem_link()
	_setup_ai()
	_connect_signals()

	# 初始化生命值
	current_hp = stats.get_stat(StatTypes.Stat.HP)
	_emit_health_changed()


func _initialize_stats() -> void:
	stats = StatContainer.new()
	stats.stats_changed.connect(_on_stats_changed)

	core_board = CoreBoard.new()

	# 狀態控制器
	status_controller = StatusController.new()
	add_child(status_controller)


func _initialize_gem_link() -> void:
	gem_link = GemLink.new()


func _setup_ai() -> void:
	ai = PlayerAI.new()
	ai.player = self
	add_child(ai)


func _connect_signals() -> void:
	if pickup_area:
		pickup_area.area_entered.connect(_on_pickup_area_entered)

	if attack_timer:
		attack_timer.timeout.connect(_on_attack_timer_timeout)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# 生命回復
	var life_regen := stats.get_stat(StatTypes.Stat.LIFE_REGEN)
	if life_regen > 0.0:
		var max_hp := stats.get_stat(StatTypes.Stat.HP)
		if current_hp < max_hp:
			current_hp = minf(current_hp + life_regen * delta, max_hp)
			_emit_health_changed()

	if status_controller and status_controller.is_frozen():
		velocity = Vector2.ZERO
		move_and_slide()
		_apply_virtual_walls()
		return

	# AI 控制移動
	if ai:
		velocity = ai.get_movement_velocity()

	move_and_slide()
	_apply_virtual_walls()

	# 更新朝向
	if velocity.x != 0:
		sprite.flip_h = velocity.x < 0


func _apply_virtual_walls() -> void:
	# 有跟隨相機時不需要螢幕虛擬牆，避免把角色鎖在原點附近。
	if get_viewport().get_camera_2d() != null:
		return
	var view_size := get_viewport_rect().size
	global_position.x = clampf(global_position.x, virtual_wall_margin, view_size.x - virtual_wall_margin)
	global_position.y = clampf(global_position.y, virtual_wall_margin, view_size.y - virtual_wall_margin)


func get_move_speed() -> float:
	return stats.get_stat(StatTypes.Stat.MOVE_SPEED)


func get_attack_speed() -> float:
	var atk_speed := stats.get_stat(StatTypes.Stat.ATK_SPEED)
	if gem_link and gem_link.skill_gem:
		atk_speed *= gem_link.skill_gem.get_attack_speed_multiplier()
	return atk_speed


func get_attack_range() -> float:
	if gem_link.skill_gem:
		return gem_link.skill_gem.get_effective_range()
	return 50.0


# ===== 裝備系統 =====

func equip(item: EquipmentData) -> EquipmentData:
	var slot := _resolve_equip_slot(item)
	item.slot = slot
	var old_item: EquipmentData = null

	# 移除舊裝備的屬性
	if equipment.has(slot):
		old_item = equipment[slot]
		old_item.remove_from_stats(stats)

	# 裝備新物品
	equipment[slot] = item
	item.apply_to_stats(stats)

	EventBus.equipment_changed.emit(slot, old_item, item)
	return old_item


func _resolve_equip_slot(item: EquipmentData) -> StatTypes.EquipmentSlot:
	if item == null:
		return StatTypes.EquipmentSlot.MAIN_HAND
	var slot := item.slot
	if slot != StatTypes.EquipmentSlot.RING_1 and slot != StatTypes.EquipmentSlot.RING_2:
		return slot
	var ring1_empty := get_equipped(StatTypes.EquipmentSlot.RING_1) == null
	var ring2_empty := get_equipped(StatTypes.EquipmentSlot.RING_2) == null
	if ring1_empty:
		return StatTypes.EquipmentSlot.RING_1
	if ring2_empty:
		return StatTypes.EquipmentSlot.RING_2
	return StatTypes.EquipmentSlot.RING_1


func unequip(slot: StatTypes.EquipmentSlot) -> EquipmentData:
	if not equipment.has(slot):
		return null

	var item: EquipmentData = equipment[slot]
	item.remove_from_stats(stats)
	equipment.erase(slot)

	EventBus.equipment_unequipped.emit(slot, item)
	return item


func get_equipped(slot: StatTypes.EquipmentSlot) -> EquipmentData:
	return equipment.get(slot)


func get_weapon_type() -> StatTypes.WeaponType:
	var weapon := get_equipped(StatTypes.EquipmentSlot.MAIN_HAND)
	if weapon:
		return weapon.weapon_type
	return StatTypes.WeaponType.SWORD


# ===== 背包系統 =====

func add_to_inventory(item: EquipmentData) -> bool:
	if inventory.size() >= MAX_INVENTORY_SIZE:
		return false
	inventory.append(item)
	return true


func remove_from_inventory(index: int) -> EquipmentData:
	if index < 0 or index >= inventory.size():
		return null
	var item: EquipmentData = inventory[index]
	inventory.remove_at(index)
	return item


func get_inventory_item(index: int) -> EquipmentData:
	if index < 0 or index >= inventory.size():
		return null
	return inventory[index]


func get_inventory_size() -> int:
	return inventory.size()


func equip_from_inventory(index: int) -> void:
	var item := remove_from_inventory(index)
	if item == null:
		return

	var old_item := equip(item)
	if old_item:
		add_to_inventory(old_item)


# ===== 材料系統 =====

func add_material(id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var current: int = int(materials.get(id, 0))
	materials[id] = current + amount


func consume_material(id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var current: int = int(materials.get(id, 0))
	if current < amount:
		return false
	materials[id] = current - amount
	return true


func get_material_count(id: String) -> int:
	return int(materials.get(id, 0))


# ===== 寶石背包系統 =====

func add_skill_gem_to_inventory(gem: SkillGem) -> bool:
	if gem == null:
		return false
	if _try_merge_skill_gem(gem):
		return true
	for i in range(MAX_SKILL_GEM_INVENTORY):
		if i >= skill_gem_inventory.size():
			skill_gem_inventory.append(gem)
			return true
		if skill_gem_inventory[i] == null:
			skill_gem_inventory[i] = gem
			return true
	return false


func add_support_gem_to_inventory(gem: SupportGem) -> bool:
	if gem == null:
		return false
	if _try_merge_support_gem(gem):
		return true
	for i in range(MAX_SUPPORT_GEM_INVENTORY):
		if i >= support_gem_inventory.size():
			support_gem_inventory.append(gem)
			return true
		if support_gem_inventory[i] == null:
			support_gem_inventory[i] = gem
			return true
	return false


func remove_skill_gem_from_inventory(index: int) -> SkillGem:
	if index < 0 or index >= skill_gem_inventory.size():
		return null
	var gem: SkillGem = skill_gem_inventory[index]
	skill_gem_inventory[index] = null
	_compact_skill_gem_inventory()
	return gem


func remove_support_gem_from_inventory(index: int) -> SupportGem:
	if index < 0 or index >= support_gem_inventory.size():
		return null
	var gem: SupportGem = support_gem_inventory[index]
	support_gem_inventory[index] = null
	_compact_support_gem_inventory()
	return gem


func get_skill_gem_in_inventory(index: int) -> SkillGem:
	if index < 0 or index >= skill_gem_inventory.size():
		return null
	return skill_gem_inventory[index]


func get_support_gem_in_inventory(index: int) -> SupportGem:
	if index < 0 or index >= support_gem_inventory.size():
		return null
	return support_gem_inventory[index]


func equip_skill_from_inventory(index: int) -> bool:
	if index < 0 or index >= MAX_SKILL_GEM_INVENTORY:
		return false
	var gem := get_skill_gem_in_inventory(index)
	if gem == null:
		return false

	var old := gem_link.skill_gem
	if old:
		# 有舊技能時直接和被點擊欄位交換，避免看起來被覆蓋/消失。
		_set_skill_gem_in_inventory(index, old)
	else:
		_set_skill_gem_in_inventory(index, null)
		_compact_skill_gem_inventory()

	gem_link.set_skill_gem(gem)
	return true


func unequip_skill_to_inventory() -> bool:
	if gem_link.skill_gem == null:
		return false
	if not _store_skill_gem_without_merge(gem_link.skill_gem):
		return false
	gem_link.set_skill_gem(null)
	return true


func equip_support_from_inventory(index: int) -> bool:
	var gem := remove_support_gem_from_inventory(index)
	if gem == null:
		return false
	if not gem_link.add_support_gem(gem):
		_set_support_gem_in_inventory(index, gem)
		return false
	return true


func unequip_support_to_inventory(index: int) -> bool:
	var gem := gem_link.remove_support_gem(index)
	if gem == null:
		return false
	if not _store_support_gem_without_merge(gem):
		# 背包滿了就放回原位
		gem_link.set_support_gem(index, gem)
		return false
	return true


func set_skill_gem_in_inventory(index: int, gem: SkillGem) -> bool:
	if index < 0 or index >= MAX_SKILL_GEM_INVENTORY:
		return false
	_set_skill_gem_in_inventory(index, gem)
	return true


func set_support_gem_in_inventory(index: int, gem: SupportGem) -> bool:
	if index < 0 or index >= MAX_SUPPORT_GEM_INVENTORY:
		return false
	_set_support_gem_in_inventory(index, gem)
	return true


func swap_skill_gem_inventory(index_a: int, index_b: int) -> void:
	_ensure_skill_gem_size(index_a)
	_ensure_skill_gem_size(index_b)
	var temp: SkillGem = skill_gem_inventory[index_a]
	skill_gem_inventory[index_a] = skill_gem_inventory[index_b]
	skill_gem_inventory[index_b] = temp


func swap_support_gem_inventory(index_a: int, index_b: int) -> void:
	_ensure_support_gem_size(index_a)
	_ensure_support_gem_size(index_b)
	var temp: SupportGem = support_gem_inventory[index_a]
	support_gem_inventory[index_a] = support_gem_inventory[index_b]
	support_gem_inventory[index_b] = temp


func swap_skill_with_inventory(index: int) -> bool:
	if gem_link.skill_gem == null:
		return false
	if index < 0 or index >= MAX_SKILL_GEM_INVENTORY:
		return false
	_ensure_skill_gem_size(index)
	var temp: SkillGem = skill_gem_inventory[index]
	skill_gem_inventory[index] = gem_link.skill_gem
	gem_link.set_skill_gem(temp)
	return true


func swap_support_with_inventory(slot_index: int, inv_index: int) -> bool:
	if slot_index < 0 or slot_index >= Constants.MAX_SUPPORT_GEMS:
		return false
	if inv_index < 0 or inv_index >= MAX_SUPPORT_GEM_INVENTORY:
		return false
	_ensure_support_gem_size(inv_index)

	var current_slot: SupportGem = null
	if slot_index < gem_link.support_gems.size():
		current_slot = gem_link.support_gems[slot_index] as SupportGem
	var inv_gem: SupportGem = support_gem_inventory[inv_index]

	if inv_gem != null and not gem_link.set_support_gem(slot_index, inv_gem):
		return false

	support_gem_inventory[inv_index] = current_slot
	if inv_gem == null:
		gem_link.set_support_gem(slot_index, null)
	return true


func _set_skill_gem_in_inventory(index: int, gem: SkillGem) -> void:
	_ensure_skill_gem_size(index)
	skill_gem_inventory[index] = gem


func _set_support_gem_in_inventory(index: int, gem: SupportGem) -> void:
	_ensure_support_gem_size(index)
	support_gem_inventory[index] = gem


func _ensure_skill_gem_size(index: int) -> void:
	while skill_gem_inventory.size() <= index:
		skill_gem_inventory.append(null)


func _ensure_support_gem_size(index: int) -> void:
	while support_gem_inventory.size() <= index:
		support_gem_inventory.append(null)


func _compact_skill_gem_inventory() -> void:
	var packed: Array[SkillGem] = []
	for gem in skill_gem_inventory:
		if gem != null:
			packed.append(gem)
	skill_gem_inventory = packed


func _compact_support_gem_inventory() -> void:
	var packed: Array[SupportGem] = []
	for gem in support_gem_inventory:
		if gem != null:
			packed.append(gem)
	support_gem_inventory = packed


func _store_skill_gem_without_merge(gem: SkillGem) -> bool:
	if gem == null:
		return false
	for i in range(MAX_SKILL_GEM_INVENTORY):
		if i >= skill_gem_inventory.size():
			skill_gem_inventory.append(gem)
			return true
		if skill_gem_inventory[i] == null:
			skill_gem_inventory[i] = gem
			return true
	return false


func _store_support_gem_without_merge(gem: SupportGem) -> bool:
	if gem == null:
		return false
	for i in range(MAX_SUPPORT_GEM_INVENTORY):
		if i >= support_gem_inventory.size():
			support_gem_inventory.append(gem)
			return true
		if support_gem_inventory[i] == null:
			support_gem_inventory[i] = gem
			return true
	return false


func _try_merge_skill_gem(incoming: SkillGem) -> bool:
	if incoming.level >= Constants.MAX_GEM_LEVEL:
		return false
	if gem_link != null and gem_link.skill_gem != null and _can_merge_same_level_skill(gem_link.skill_gem, incoming):
		_merge_skill_pair(gem_link.skill_gem)
		return true
	for gem in skill_gem_inventory:
		if gem != null and _can_merge_same_level_skill(gem, incoming):
			_merge_skill_pair(gem)
			return true
	return false


func _try_merge_support_gem(incoming: SupportGem) -> bool:
	if incoming.level >= Constants.MAX_GEM_LEVEL:
		return false
	if gem_link != null:
		for equipped in gem_link.support_gems:
			if equipped != null and _can_merge_same_level_support(equipped, incoming):
				_merge_support_pair(equipped)
				return true
	for gem in support_gem_inventory:
		if gem != null and _can_merge_same_level_support(gem, incoming):
			_merge_support_pair(gem)
			return true
	return false


func _can_merge_same_level_skill(a: SkillGem, b: SkillGem) -> bool:
	return a.id == b.id and a.level == b.level and a.level < Constants.MAX_GEM_LEVEL


func _can_merge_same_level_support(a: SupportGem, b: SupportGem) -> bool:
	return a.id == b.id and a.level == b.level and a.level < Constants.MAX_GEM_LEVEL


func _merge_skill_pair(target_gem: SkillGem) -> void:
	target_gem.level = mini(target_gem.level + 1, Constants.MAX_GEM_LEVEL)
	target_gem.experience = 0.0
	EventBus.gem_leveled_up.emit(target_gem, target_gem.level)


func _merge_support_pair(target_gem: SupportGem) -> void:
	target_gem.level = mini(target_gem.level + 1, Constants.MAX_GEM_LEVEL)
	target_gem.experience = 0.0
	EventBus.gem_leveled_up.emit(target_gem, target_gem.level)


# ===== 戰鬥系統 =====

func start_auto_attack() -> void:
	if attack_timer.is_stopped():
		_perform_attack()
		_restart_attack_timer()


func stop_auto_attack() -> void:
	attack_timer.stop()


func _restart_attack_timer() -> void:
	var atk_speed := get_attack_speed()
	var interval := 1.0 / maxf(atk_speed, 0.1)
	attack_timer.wait_time = interval
	attack_timer.start()


func _perform_attack() -> void:
	if not gem_link.is_valid():
		return

	var skill := gem_link.skill_gem
	if skill == null:
		return

	if not skill.can_use_with_weapon(get_weapon_type()):
		return

	if current_target == null or not is_instance_valid(current_target):
		return

	_try_shadow_strike_reposition()

	var support_mods := gem_link.get_combined_modifiers()
	var skill_mult := gem_link.get_final_damage_multiplier()

	var is_ranged := (skill.has_tag(StatTypes.SkillTag.RANGED)
		or skill.has_tag(StatTypes.SkillTag.PROJECTILE))

	if is_ranged:
		if skill.id == "arrow_rain":
			_apply_arrow_rain(skill_mult, support_mods)
			return
		var ranged_damage := DamageCalculator.calculate_attack_damage(stats, skill_mult, support_mods, skill)
		if skill.id == "arc_lightning":
			_cast_arc_lightning(ranged_damage, support_mods)
			return
		_launch_projectile(ranged_damage, support_mods)
	else:
		if skill.hit_count > 1:
			_apply_flurry_hit(skill_mult, support_mods)
			return
		var melee_damage := DamageCalculator.calculate_attack_damage(stats, skill_mult, support_mods, skill)
		_apply_melee_hit(melee_damage, support_mods)


func _try_shadow_strike_reposition() -> void:
	if gem_link == null or gem_link.skill_gem == null:
		return
	if gem_link.skill_gem.id != "shadow_strike":
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	if not (current_target is Node2D):
		return

	var target_node := current_target as Node2D
	var to_target := (target_node.global_position - global_position).normalized()
	if to_target == Vector2.ZERO:
		to_target = Vector2.RIGHT

	var desired := target_node.global_position + to_target * SHADOW_STRIKE_OFFSET
	if _can_teleport_to(desired, target_node):
		global_position = desired
		return

	# 找不到理想背後點時，嘗試背後附近數個偏移角。
	var angle_offsets := [20.0, -20.0, 40.0, -40.0, 60.0, -60.0]
	for angle_deg in angle_offsets:
		var dir := to_target.rotated(deg_to_rad(angle_deg))
		var candidate := target_node.global_position + dir * SHADOW_STRIKE_OFFSET
		if _can_teleport_to(candidate, target_node):
			global_position = candidate
			return


func _can_teleport_to(pos: Vector2, target_node: Node2D) -> bool:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = collision_mask

	var hits := get_world_2d().direct_space_state.intersect_point(params, 8)
	for hit in hits:
		var collider = hit.get("collider")
		if collider == null:
			continue
		if collider == self or collider == target_node:
			continue
		if collider.has_method("is_dead"):
			continue
		return false

	return true


func _apply_melee_hit(
	damage_result: DamageCalculator.DamageResult,
	support_mods: Dictionary,
	spawn_effect: bool = true
) -> void:
	if spawn_effect:
		_spawn_melee_effect(damage_result, support_mods)

	var targets := _get_melee_targets(support_mods)
	for target in targets:
		if target != null and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(damage_result, self)
			_try_apply_status_on_hit(target, damage_result, support_mods)
			_try_apply_knockback_on_hit(target, support_mods)


func _apply_flurry_hit(skill_mult: float, support_mods: Dictionary) -> void:
	var skill := gem_link.skill_gem
	if skill == null:
		return
	var hit_count := maxi(1, skill.hit_count)
	for i in range(hit_count):
		var per_hit_mult := skill_mult
		# Stab's second strike is a finisher to improve single-target burst identity.
		if skill.id == "stab" and i == hit_count - 1:
			per_hit_mult *= STAB_FINISHER_MULTIPLIER
		var damage_result := DamageCalculator.calculate_attack_damage(stats, per_hit_mult, support_mods, skill)
		_apply_melee_hit(damage_result, support_mods, i == 0)


func _apply_arrow_rain(skill_mult: float, support_mods: Dictionary) -> void:
	if current_target == null or not is_instance_valid(current_target):
		return
	if not (current_target is Node2D):
		return
	var skill := gem_link.skill_gem
	if skill == null:
		return

	var area_multiplier := maxf(float(support_mods.get("area_multiplier", 1.0)), 0.1)
	var rain_radius := skill.get_effective_explosion_radius()
	if rain_radius <= 0.0:
		rain_radius = 80.0
	rain_radius *= area_multiplier

	var center := (current_target as Node2D).global_position
	var arrow_count := maxi(1, skill.arrow_count)
	_spawn_arrow_rain_effect(center, rain_radius, arrow_count)
	var targets := _get_enemies_in_circle(center, rain_radius)
	if targets.is_empty():
		targets.append(current_target as Node2D)

	for i in range(arrow_count):
		var target: Node2D = targets[randi() % targets.size()]
		if target == null or not is_instance_valid(target):
			continue
		var damage_result := DamageCalculator.calculate_attack_damage(stats, skill_mult, support_mods, skill)
		if target.has_method("take_damage"):
			target.take_damage(damage_result, self)
			_try_apply_status_on_hit(target, damage_result, support_mods)
			_try_apply_knockback_on_hit(target, support_mods)


func _launch_projectile(
	damage_result: DamageCalculator.DamageResult,
	support_mods: Dictionary
) -> void:
	if current_target == null or not is_instance_valid(current_target):
		return
	var skill := gem_link.skill_gem
	if skill == null:
		return

	var projectile_count := maxi(1, int(round(support_mods.get("projectile_count", 0.0))) + 1)
	var spread_deg := 14.0 + maxf(float(projectile_count - 1), 0.0) * 3.0
	var base_angle := (current_target.global_position - global_position).angle()
	var is_tracking := gem_link.skill_gem.has_tag(StatTypes.SkillTag.TRACKING)
	var projectile_speed := skill.get_effective_projectile_speed()
	var area_multiplier := maxf(float(support_mods.get("area_multiplier", 1.0)), 0.1)
	var explosion_radius := skill.get_effective_explosion_radius() * area_multiplier
	var pierce_count := maxi(0, skill.pierce_count + int(round(support_mods.get("pierce_count", 0.0))))
	var chain_count := maxi(0, skill.chain_count + int(round(support_mods.get("chain_count", 0.0))))
	var color: Color = StatTypes.ELEMENT_COLORS.get(
		_get_primary_element(damage_result), Color.WHITE)

	for i in range(projectile_count):
		var projectile: Projectile = PROJECTILE_SCENE.instantiate()

		var angle_offset := 0.0
		if projectile_count > 1:
			var t := float(i) / float(projectile_count - 1)
			angle_offset = lerpf(-spread_deg * 0.5, spread_deg * 0.5, t)
		var aim_direction := Vector2.from_angle(base_angle + deg_to_rad(angle_offset))
		var side_dir := Vector2(-aim_direction.y, aim_direction.x)
		var side_index := float(i) - (float(projectile_count - 1) * 0.5)
		var side_spacing := 10.0 if is_tracking else 0.0
		projectile.global_position = global_position + side_dir * side_index * side_spacing

		projectile.setup(
			self,
			current_target,
			damage_result,
			support_mods,
			is_tracking,
			color,
			aim_direction,
			projectile_speed,
			explosion_radius,
			pierce_count,
			chain_count
		)
		get_parent().add_child(projectile)


func _cast_arc_lightning(
	damage_result: DamageCalculator.DamageResult,
	support_mods: Dictionary
) -> void:
	if current_target == null or not is_instance_valid(current_target):
		return
	if not (current_target is Node2D):
		return
	var skill := gem_link.skill_gem
	if skill == null:
		return

	var max_chain := maxi(0, skill.chain_count + int(round(support_mods.get("chain_count", 0.0))))
	var hit_targets: Dictionary = {}
	var chain_targets: Array[Node2D] = []
	var current_node := current_target as Node2D
	var hops := 0

	while current_node != null and is_instance_valid(current_node):
		var key := str(current_node.get_instance_id())
		if hit_targets.has(key):
			break
		hit_targets[key] = true
		chain_targets.append(current_node)
		if hops >= max_chain:
			break
		var next_target := _find_arc_chain_target(current_node, hit_targets)
		if next_target == null:
			break
		current_node = next_target
		hops += 1

	var used_chain := maxi(chain_targets.size() - 1, 0)
	var unused_chain := maxi(max_chain - used_chain, 0)
	var bonus_mult := 1.0 + float(unused_chain) * ARC_UNUSED_CHAIN_MORE_PER_STACK
	var result_to_apply := _scale_damage_result(damage_result, bonus_mult) if unused_chain > 0 else damage_result

	var from_pos := global_position
	var color: Color = StatTypes.ELEMENT_COLORS.get(_get_primary_element(damage_result), Color.WHITE)
	for target_node in chain_targets:
		if target_node == null or not is_instance_valid(target_node):
			continue
		_spawn_arc_beam_effect(from_pos, target_node.global_position, color)
		if target_node.has_method("take_damage"):
			target_node.take_damage(result_to_apply, self)
			_try_apply_status_on_hit(target_node, result_to_apply, support_mods)
			_try_apply_knockback_on_hit(target_node, support_mods)
		from_pos = target_node.global_position


func _find_arc_chain_target(from_target: Node2D, hit_targets: Dictionary) -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var best: Node2D = null
	var best_dist_sq := INF
	var max_dist_sq := ARC_CHAIN_SEARCH_RADIUS * ARC_CHAIN_SEARCH_RADIUS

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
		if hit_targets.has(key):
			continue
		var dist_sq := enemy_node.global_position.distance_squared_to(from_target.global_position)
		if dist_sq > max_dist_sq:
			continue
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = enemy_node

	return best


func _spawn_arc_beam_effect(start_pos: Vector2, end_pos: Vector2, color: Color) -> void:
	var beam := Line2D.new()
	beam.width = 3.5
	beam.default_color = color
	beam.z_index = 50
	beam.add_point(start_pos)
	beam.add_point(end_pos)
	get_parent().add_child(beam)

	var tween := create_tween()
	tween.tween_property(beam, "modulate:a", 0.0, 0.12)
	tween.tween_callback(beam.queue_free)


func _scale_damage_result(
	base: DamageCalculator.DamageResult,
	multiplier: float
) -> DamageCalculator.DamageResult:
	var scaled := DamageCalculator.DamageResult.new()
	var m := maxf(multiplier, 0.0)
	scaled.physical_damage = base.physical_damage * m
	scaled.fire_damage = base.fire_damage * m
	scaled.ice_damage = base.ice_damage * m
	scaled.lightning_damage = base.lightning_damage * m
	scaled.total_damage = (
		scaled.physical_damage +
		scaled.fire_damage +
		scaled.ice_damage +
		scaled.lightning_damage
	)
	scaled.is_crit = base.is_crit
	scaled.crit_multiplier = base.crit_multiplier
	return scaled


func _spawn_melee_effect(
	damage_result: DamageCalculator.DamageResult,
	support_mods: Dictionary
) -> void:
	if current_target == null or not is_instance_valid(current_target):
		return
	var effect: MeleeEffect = MELEE_EFFECT_SCENE.instantiate()
	effect.global_position = global_position
	var angle := (current_target.global_position - global_position).angle()
	var area_multiplier := float(support_mods.get("area_multiplier", 1.0))
	var skill := gem_link.skill_gem
	var is_circle := skill != null and skill.id == "whirlwind"
	var is_aoe_melee := skill != null and skill.has_tag(StatTypes.SkillTag.AOE)
	var effect_range := get_attack_range()
	var cone_angle_deg := 102.0
	if is_aoe_melee:
		effect_range *= maxf(area_multiplier, 0.1)
	else:
		# 單體近戰維持短距離視覺，避免看起來像範圍技。
		effect_range = minf(effect_range, 55.0)
		cone_angle_deg = 42.0
		if skill != null and (skill.id == "flurry" or skill.id == "shadow_strike"):
			effect_range = minf(effect_range, 42.0)
			cone_angle_deg = 30.0
		elif skill != null and skill.id == "stab":
			# 刺擊視覺跟著實際攻擊距離，避免看起來打不到卻有傷害。
			effect_range = get_attack_range()
			cone_angle_deg = 34.0
	var color: Color = StatTypes.ELEMENT_COLORS.get(
		_get_primary_element(damage_result), Color.WHITE)
	effect.setup(effect_range, angle, color, is_circle, cone_angle_deg)
	get_parent().add_child(effect)


func _spawn_arrow_rain_effect(center: Vector2, radius: float, arrow_count: int) -> void:
	var effect: ArrowRainEffect = ARROW_RAIN_EFFECT_SCENE.instantiate()
	var color := Color(0.88, 0.95, 1.0, 1.0)
	effect.setup(center, radius, arrow_count, color)
	get_parent().add_child(effect)


func _get_melee_targets(support_mods: Dictionary) -> Array[Node2D]:
	if current_target == null or not is_instance_valid(current_target):
		return []
	if not (current_target is Node2D):
		return []
	var target_node := current_target as Node2D

	if gem_link == null or gem_link.skill_gem == null:
		if _is_target_in_melee_range(target_node, get_attack_range()):
			return _single_target_array(target_node)
		return []

	var skill := gem_link.skill_gem
	var area_multiplier := float(support_mods.get("area_multiplier", 1.0))
	var radius := get_attack_range() * maxf(area_multiplier, 0.1)

	# 暗影突襲固定單體。
	if skill.id == "shadow_strike":
		if _is_target_in_melee_range(target_node, get_attack_range()):
			return _single_target_array(target_node)
		return []

	if not skill.has_tag(StatTypes.SkillTag.AOE):
		if _is_target_in_melee_range(target_node, get_attack_range()):
			return _single_target_array(target_node)
		return []

	# 近戰 AOE：旋風斬為全圓，其餘 AOE 近戰預設前方扇形。
	if skill.id == "whirlwind":
		return _get_enemies_in_circle(global_position, radius)

	var forward := (target_node.global_position - global_position).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	return _get_enemies_in_cone(global_position, forward, radius, 120.0)


func _is_target_in_melee_range(target_node: Node2D, max_range: float) -> bool:
	if target_node == null or not is_instance_valid(target_node):
		return false
	var clamped_range := maxf(max_range, 0.0)
	return global_position.distance_squared_to(target_node.global_position) <= clamped_range * clamped_range


func _single_target_array(target_node: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if target_node != null and is_instance_valid(target_node):
		result.append(target_node)
	return result


func _get_enemies_in_circle(center: Vector2, radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var enemies := get_tree().get_nodes_in_group("enemies")
	var radius_sq := radius * radius

	for enemy in enemies:
		if not (enemy is Node2D):
			continue
		var enemy_node := enemy as Node2D
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node.has_method("is_dead") and enemy_node.is_dead():
			continue
		if enemy_node.global_position.distance_squared_to(center) <= radius_sq:
			result.append(enemy_node)

	return result


func _get_enemies_in_cone(
	center: Vector2,
	forward: Vector2,
	radius: float,
	angle_deg: float
) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var enemies := get_tree().get_nodes_in_group("enemies")
	var radius_sq := radius * radius
	var dir := forward.normalized()
	var min_dot := cos(deg_to_rad(angle_deg * 0.5))

	for enemy in enemies:
		if not (enemy is Node2D):
			continue
		var enemy_node := enemy as Node2D
		if enemy_node == null or not is_instance_valid(enemy_node):
			continue
		if enemy_node.has_method("is_dead") and enemy_node.is_dead():
			continue

		var to_enemy := enemy_node.global_position - center
		if to_enemy.length_squared() > radius_sq:
			continue

		var dot := dir.dot(to_enemy.normalized())
		if dot >= min_dot:
			result.append(enemy_node)

	return result


func on_projectile_hit(
	target: Node,
	damage_result: DamageCalculator.DamageResult,
	support_mods: Dictionary
) -> void:
	_try_apply_status_on_hit(target, damage_result, support_mods)
	_try_apply_knockback_on_hit(target, support_mods)


func _get_primary_element(result: DamageCalculator.DamageResult) -> StatTypes.Element:
	var max_dmg := result.physical_damage
	var element := StatTypes.Element.PHYSICAL
	if result.fire_damage > max_dmg:
		max_dmg = result.fire_damage
		element = StatTypes.Element.FIRE
	if result.ice_damage > max_dmg:
		max_dmg = result.ice_damage
		element = StatTypes.Element.ICE
	if result.lightning_damage > max_dmg:
		element = StatTypes.Element.LIGHTNING
	return element


func _on_attack_timer_timeout() -> void:
	if current_target and is_instance_valid(current_target):
		_perform_attack()
	_restart_attack_timer()


# ===== 受傷與死亡 =====

func take_damage(damage_result: DamageCalculator.DamageResult, attacker: Node) -> void:
	if is_dead:
		return

	var final_damage := DamageCalculator.calculate_received_damage(stats, damage_result)
	if status_controller:
		final_damage *= status_controller.get_damage_taken_multiplier()
	current_hp -= final_damage

	_emit_health_changed()

	# 生命竊取
	var life_steal := stats.get_stat(StatTypes.Stat.LIFE_STEAL)
	if life_steal > 0:
		heal(final_damage * life_steal)

	if current_hp <= 0:
		_die()


func heal(amount: float) -> void:
	var max_hp := stats.get_stat(StatTypes.Stat.HP)
	current_hp = minf(current_hp + amount, max_hp)
	_emit_health_changed()


func _die() -> void:
	is_dead = true
	stop_auto_attack()
	died.emit()
	EventBus.player_died.emit()


func _emit_health_changed() -> void:
	var max_hp := stats.get_stat(StatTypes.Stat.HP)
	health_changed.emit(current_hp, max_hp)
	EventBus.player_health_changed.emit(current_hp, max_hp)


func apply_status_damage(amount: float, element: StatTypes.Element) -> void:
	if is_dead:
		return

	# 直接扣血（持續傷害）
	current_hp -= amount
	_emit_health_changed()

	if current_hp <= 0:
		_die()


# ===== 拾取 =====

func _on_pickup_area_entered(area: Area2D) -> void:
	if area.has_method("pickup"):
		area.pickup(self)


func _on_stats_changed() -> void:
	# 更新最大生命時，按比例調整當前生命
	var max_hp := stats.get_stat(StatTypes.Stat.HP)
	current_hp = minf(current_hp, max_hp)
	_emit_health_changed()

	# 更新拾取範圍
	var range_bonus := stats.get_stat(StatTypes.Stat.PICKUP_RANGE)
	var final_range := pickup_range * (1.0 + range_bonus)
	if pickup_area and pickup_area.has_node("CollisionShape2D"):
		var shape: CollisionShape2D = pickup_area.get_node("CollisionShape2D")
		if shape.shape is CircleShape2D:
			shape.shape.radius = final_range


func _try_apply_status_on_hit(
	target: Node,
	damage_result: DamageCalculator.DamageResult,
	support_mods: Dictionary
) -> void:
	if status_controller == null:
		return
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("get_status_controller"):
		return

	var target_status: StatusController = target.get_status_controller()
	if target_status == null:
		return

	var support_bonus: float = support_mods.get("status_chance_bonus", 0.0)
	var total: float = maxf(damage_result.total_damage, 1.0)

	if damage_result.fire_damage > 0.0:
		_try_apply("burn", Constants.BURN_BASE_CHANCE, StatTypes.Stat.BURN_CHANCE, support_bonus + _get_skill_status_bonus("burn"), damage_result.fire_damage, total, target_status)
	if damage_result.ice_damage > 0.0:
		_try_apply("freeze", Constants.FREEZE_BASE_CHANCE, StatTypes.Stat.FREEZE_CHANCE, support_bonus + _get_skill_status_bonus("freeze"), damage_result.ice_damage, total, target_status)
	if damage_result.lightning_damage > 0.0:
		_try_apply("shock", Constants.SHOCK_BASE_CHANCE, StatTypes.Stat.SHOCK_CHANCE, support_bonus + _get_skill_status_bonus("shock"), damage_result.lightning_damage, total, target_status)
	if damage_result.physical_damage > 0.0:
		_try_apply("bleed", Constants.BLEED_BASE_CHANCE, StatTypes.Stat.BLEED_CHANCE, support_bonus + _get_skill_status_bonus("bleed"), damage_result.physical_damage, total, target_status)


func _try_apply(
	status_type: String,
	base_chance: float,
	stat_type: StatTypes.Stat,
	bonus: float,
	source_damage: float,
	total_damage: float,
	target_status: StatusController
) -> void:
	var portion := clampf(source_damage / maxf(total_damage, 1.0), 0.1, 1.0)
	var chance := (base_chance + stats.get_stat(stat_type) + bonus) * portion
	if randf() < chance:
		target_status.apply_status(status_type, source_damage, stats)


func _try_apply_knockback_on_hit(target: Node, support_mods: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("apply_knockback"):
		return
	var force := float(support_mods.get("knockback_force", 0.0))
	if force <= 0.0:
		return
	target.apply_knockback(global_position, force)


func _get_skill_status_bonus(status_type: String) -> float:
	if gem_link == null or gem_link.skill_gem == null:
		return 0.0
	return gem_link.skill_gem.get_status_chance_bonus_for(status_type)


func get_status_controller() -> StatusController:
	return status_controller


# ===== 重生 =====

func respawn() -> void:
	is_dead = false
	current_hp = stats.get_stat(StatTypes.Stat.HP)
	_emit_health_changed()


# ===== 模組系統 =====

func add_module_to_inventory(module: Module) -> bool:
	if module == null:
		return false
	if module_inventory.size() >= MAX_MODULE_INVENTORY:
		return false
	module_inventory.append(module)
	return true


func remove_module_from_inventory(index: int) -> Module:
	if index < 0 or index >= module_inventory.size():
		return null
	var module: Module = module_inventory[index]
	module_inventory.remove_at(index)
	return module


func equip_module_from_inventory(index: int) -> bool:
	var module := remove_module_from_inventory(index)
	if module == null:
		return false
	if not core_board.equip(module, stats):
		module_inventory.insert(index, module)
		return false
	return true


func unequip_module_to_inventory(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= core_board.slots.size():
		return false
	var module: Module = core_board.slots[slot_index]
	if module_inventory.size() >= MAX_MODULE_INVENTORY:
		return false
	core_board.unequip(module, stats)
	module_inventory.append(module)
	return true
