class_name EnemySpawner
extends Node2D

signal all_enemies_dead

@export var enemy_scene: PackedScene
@export var spawn_radius: float = 200.0
@export var min_spawn_distance: float = 100.0  # 與玩家的最小距離

var active_enemies: Array[EnemyBase] = []
var floor_config: Dictionary = {}
var player: Node2D = null
var current_floor: int = 1

var _spawn_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0
const SPAWN_INTERVAL := 0.1  # 每個敵人生成間隔


func _ready() -> void:
	if enemy_scene == null:
		enemy_scene = preload("res://scenes/entities/enemies/enemy_base.tscn")


func _process(delta: float) -> void:
	if not _spawn_queue.is_empty():
		_spawn_timer -= delta
		if _spawn_timer <= 0:
			_spawn_next_enemy()
			_spawn_timer = SPAWN_INTERVAL


func setup(config: Dictionary, player_ref: Node2D) -> void:
	floor_config = config
	player = player_ref


func set_floor_number(floor_number: int) -> void:
	current_floor = max(1, floor_number)


func spawn_wave() -> void:
	clear_enemies()

	var enemy_count: int = floor_config.get("enemy_count", 10)
	var enemy_types: Array = floor_config.get("enemies", ["slime"])
	var hp_mult: float = floor_config.get("enemy_hp_multiplier", 1.0)
	var atk_mult: float = floor_config.get("enemy_atk_multiplier", 1.0)
	var forced_elites: int = maxi(0, int(floor_config.get("forced_elites", 0)))
	var boss_id: String = str(floor_config.get("boss", ""))

	# BOSS 層：只生成 BOSS，不生成小怪
	if boss_id != "":
		_spawn_queue.append({
			"type": boss_id,
			"hp_mult": hp_mult,
			"atk_mult": atk_mult,
			"force_elite": false,
			"force_boss": true,
		})
		_spawn_timer = 0.0
		return

	# 準備生成佇列
	for i in range(enemy_count):
		var enemy_type: String = enemy_types[randi() % enemy_types.size()]
		_spawn_queue.append({
			"type": enemy_type,
			"hp_mult": hp_mult,
			"atk_mult": atk_mult,
			"force_elite": i < forced_elites,
		})

	_spawn_timer = 0.0


func _spawn_next_enemy() -> void:
	if _spawn_queue.is_empty():
		return

	var spawn_data: Dictionary = _spawn_queue.pop_front()
	var enemy := _create_enemy(spawn_data.type)
	if enemy == null:
		return

	# 應用層數倍率
	enemy.apply_floor_multipliers(spawn_data.hp_mult, spawn_data.atk_mult)
	if bool(spawn_data.get("force_elite", false)):
		var forced_mods: Array[String] = _roll_elite_mods(1)
		if not forced_mods.is_empty():
			enemy.apply_elite_mods(forced_mods)
			print("[EliteSpawn] floor=%d enemy=%s mods=%s (forced)" % [current_floor, enemy.enemy_id, ",".join(forced_mods)])
	else:
		_apply_elite_roll(enemy)

	# 計算生成位置
	var spawn_pos := _get_spawn_position()
	enemy.global_position = spawn_pos

	# 連接死亡信號
	enemy.died.connect(_on_enemy_died)

	# 添加到場景
	add_child(enemy)
	active_enemies.append(enemy)


func _create_enemy(enemy_type: String) -> EnemyBase:
	var enemy: EnemyBase = enemy_scene.instantiate()

	# 從資料載入敵人屬性
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_type)
	if enemy_data.is_empty():
		enemy_data = DataManager.get_enemy("slime")

	enemy.enemy_id = enemy_type
	enemy.display_name = enemy_data.get("display_name", enemy_type)
	enemy.base_hp = enemy_data.get("base_hp", 30.0)
	enemy.base_atk = enemy_data.get("base_atk", 5.0)
	enemy.base_def = enemy_data.get("base_def", 0.0)
	enemy.move_speed = enemy_data.get("move_speed", 40.0)
	enemy.atk_range = enemy_data.get("atk_range", 30.0)
	enemy.atk_speed = enemy_data.get("atk_speed", 0.8)
	enemy.experience = enemy_data.get("experience", 10.0)
	enemy.is_elite = enemy_data.get("is_elite", false)
	enemy.is_boss = enemy_data.get("is_boss", false)
	enemy.behavior = str(enemy_data.get("behavior", "chase"))
	enemy.uses_projectile = bool(enemy_data.get("projectile", false))
	enemy.projectile_speed = float(enemy_data.get("projectile_speed", 320.0))

	# 設定元素
	var element_str: String = enemy_data.get("element", "physical")
	enemy.element = _string_to_element(element_str)

	# 設定抗性
	enemy.resistances = enemy_data.get("resistances", {})

	# 設定顏色（PlaceholderSprite 使用 shape_color）
	if enemy.sprite and enemy.sprite.has_method("set"):
		var color := _get_enemy_color(enemy.element, enemy.is_elite, enemy.is_boss)
		if "shape_color" in enemy.sprite:
			enemy.sprite.shape_color = color
		else:
			enemy.sprite.modulate = color

	return enemy


func _get_spawn_position() -> Vector2:
	if player == null:
		return global_position + Vector2(randf_range(-spawn_radius, spawn_radius), randf_range(-spawn_radius, spawn_radius))

	# 確保不會生成在玩家太近的地方
	var attempts := 10
	for i in range(attempts):
		var angle := randf() * TAU
		var distance := randf_range(min_spawn_distance, spawn_radius)
		var pos := player.global_position + Vector2.from_angle(angle) * distance

		# 確保在場景範圍內
		pos.x = clampf(pos.x, 50, 1230)
		pos.y = clampf(pos.y, 50, 670)

		return pos

	return player.global_position + Vector2(spawn_radius, 0)


func _on_enemy_died(enemy: EnemyBase) -> void:
	active_enemies.erase(enemy)

	if active_enemies.is_empty() and _spawn_queue.is_empty():
		all_enemies_dead.emit()


func clear_enemies() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()
	_spawn_queue.clear()


func get_active_enemy_count() -> int:
	return active_enemies.size() + _spawn_queue.size()


func _string_to_element(element_str: String) -> StatTypes.Element:
	match element_str:
		"fire": return StatTypes.Element.FIRE
		"ice": return StatTypes.Element.ICE
		"lightning": return StatTypes.Element.LIGHTNING
		_: return StatTypes.Element.PHYSICAL


func _get_enemy_color(element: StatTypes.Element, is_elite: bool, is_boss: bool) -> Color:
	var base_color: Color

	match element:
		StatTypes.Element.FIRE:
			base_color = Color(1.0, 0.4, 0.2)
		StatTypes.Element.ICE:
			base_color = Color(0.4, 0.7, 1.0)
		StatTypes.Element.LIGHTNING:
			base_color = Color(1.0, 1.0, 0.3)
		_:
			base_color = Color(0.8, 0.3, 0.3)

	if is_boss:
		base_color = base_color.lightened(0.2)
	elif is_elite:
		base_color = base_color.lightened(0.1)

	return base_color


func _apply_elite_roll(enemy: EnemyBase) -> void:
	if enemy == null or enemy.is_boss:
		return
	var elite_chance := clampf(0.18 + float(current_floor) * 0.003, 0.18, 0.55)
	if randf() > elite_chance:
		return
	var affix_count := 1 if randf() < 0.78 else 2
	var selected: Array[String] = _roll_elite_mods(affix_count)
	if selected.is_empty():
		return

	enemy.apply_elite_mods(selected)
	print("[EliteSpawn] floor=%d enemy=%s mods=%s" % [current_floor, enemy.enemy_id, ",".join(selected)])


func _roll_elite_mods(affix_count: int) -> Array[String]:
	var pool: Array[String] = [
		"swift",
		"armored",
		"elemental_shield",
		"rage",
		"lifeleech",
		"thorns",
		"death_burst",
	]
	var selected: Array[String] = []
	var count := maxi(1, affix_count)
	for i in range(count):
		var choices := pool.filter(func(x: String) -> bool: return not selected.has(x))
		if choices.is_empty():
			break
		selected.append(choices[randi() % choices.size()])
	return selected
