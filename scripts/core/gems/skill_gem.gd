class_name SkillGem
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export var weapon_restrictions: Array[StatTypes.WeaponType] = []
@export var tags: Array[StatTypes.SkillTag] = []

@export var base_damage_multiplier: float = 1.0
@export var base_cooldown: float = 0.0
@export var base_range: float = 50.0
@export var projectile_speed: float = 450.0
@export var explosion_radius: float = 0.0
@export var pierce_count: int = 0
@export var chain_count: int = 0
@export var hit_count: int = 1
@export var arrow_count: int = 1

@export var level: int = 1
@export var experience: float = 0.0
@export var is_mutated: bool = false
@export var mutated_id: String = ""

const DAMAGE_PER_LEVEL := 0.05
const RANGE_PER_LEVEL := 0.015
const PROJECTILE_SPEED_PER_LEVEL := 0.02
const EXPLOSION_RADIUS_PER_LEVEL := 0.015


func get_damage_multiplier() -> float:
	return base_damage_multiplier * (1.0 + (level - 1) * DAMAGE_PER_LEVEL)


func get_effective_range() -> float:
	return base_range * (1.0 + (level - 1) * RANGE_PER_LEVEL)


func get_effective_projectile_speed() -> float:
	return projectile_speed * (1.0 + (level - 1) * PROJECTILE_SPEED_PER_LEVEL)


func get_effective_explosion_radius() -> float:
	if explosion_radius <= 0.0:
		return 0.0
	return explosion_radius * (1.0 + (level - 1) * EXPLOSION_RADIUS_PER_LEVEL)


func get_experience_for_next_level() -> float:
	return 100.0 * pow(1.5, level - 1)


func add_experience(amount: float) -> bool:
	if level >= Constants.MAX_GEM_LEVEL:
		return false

	experience += amount
	var leveled_up := false
	while experience >= get_experience_for_next_level() and level < Constants.MAX_GEM_LEVEL:
		experience -= get_experience_for_next_level()
		level += 1
		leveled_up = true

	return leveled_up


func can_use_with_weapon(weapon_type: StatTypes.WeaponType) -> bool:
	return weapon_restrictions.is_empty() or weapon_type in weapon_restrictions


func has_tag(tag: StatTypes.SkillTag) -> bool:
	return tag in tags


func get_tooltip() -> String:
	var lines: Array[String] = []
	var name_prefix := "[變異] " if is_mutated else ""
	lines.append("[color=#00ff00]%s%s[/color]" % [name_prefix, display_name])
	lines.append("等級 %d" % level)
	lines.append("")
	lines.append(description)
	lines.append("")
	lines.append("傷害倍率: %.1f%%" % (get_damage_multiplier() * 100.0))
	lines.append("攻擊範圍: %.0f" % get_effective_range())

	if has_tag(StatTypes.SkillTag.PROJECTILE):
		lines.append("投射速度: %.0f" % get_effective_projectile_speed())
	if get_effective_explosion_radius() > 0.0:
		lines.append("爆炸半徑: %.0f" % get_effective_explosion_radius())
	if hit_count > 1:
		lines.append("命中次數: %d" % hit_count)
	if arrow_count > 1:
		lines.append("齊射數量: %d" % arrow_count)
	if pierce_count > 0:
		lines.append("穿透目標: %d" % pierce_count)
	if chain_count > 0:
		lines.append("連鎖次數: %d" % chain_count)

	if not weapon_restrictions.is_empty():
		var weapons: Array[String] = []
		for w in weapon_restrictions:
			weapons.append(_get_weapon_name(w))
		lines.append("武器限制: %s" % ", ".join(weapons))

	if not tags.is_empty():
		var tag_names: Array[String] = []
		for t in tags:
			tag_names.append(_get_tag_name(t))
		lines.append("標籤: %s" % ", ".join(tag_names))

	return "\n".join(lines)


func _get_weapon_name(weapon: StatTypes.WeaponType) -> String:
	match weapon:
		StatTypes.WeaponType.SWORD: return "劍"
		StatTypes.WeaponType.DAGGER: return "匕首"
		StatTypes.WeaponType.BOW: return "弓"
		StatTypes.WeaponType.WAND: return "法杖"
		_: return "未知"


func _get_tag_name(tag: StatTypes.SkillTag) -> String:
	match tag:
		StatTypes.SkillTag.MELEE: return "近戰"
		StatTypes.SkillTag.RANGED: return "遠程"
		StatTypes.SkillTag.PROJECTILE: return "投射物"
		StatTypes.SkillTag.AOE: return "範圍"
		StatTypes.SkillTag.FAST: return "快速"
		StatTypes.SkillTag.HEAVY: return "重擊"
		StatTypes.SkillTag.TRACKING: return "追蹤"
		_: return "未知"
