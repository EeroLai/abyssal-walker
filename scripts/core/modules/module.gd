class_name Module
extends Resource

enum ModuleType {
	ATTACK,
	DEFENSE,
	UTILITY,
	SPECIAL,
}

var id: String = ""
var display_name: String = ""
var description: String = ""
var module_type: ModuleType = ModuleType.ATTACK
var load_cost: int = 0
var is_starter: bool = false
var modifiers: Array[StatModifier] = []


func apply_to_stats(stats: StatContainer) -> void:
	for mod in modifiers:
		mod.apply_to_stats(stats, "module_%s" % id)


func remove_from_stats(stats: StatContainer) -> void:
	for mod in modifiers:
		mod.remove_from_stats(stats, "module_%s" % id)


func get_type_name() -> String:
	match module_type:
		ModuleType.ATTACK:  return "攻擊"
		ModuleType.DEFENSE: return "防禦"
		ModuleType.UTILITY: return "功能"
		ModuleType.SPECIAL: return "特殊"
	return "未知"


func get_type_color() -> Color:
	match module_type:
		ModuleType.ATTACK:  return Color(1.0, 0.4, 0.3)
		ModuleType.DEFENSE: return Color(0.3, 0.7, 1.0)
		ModuleType.UTILITY: return Color(0.4, 1.0, 0.5)
		ModuleType.SPECIAL: return Color(0.9, 0.5, 1.0)
	return Color.WHITE
