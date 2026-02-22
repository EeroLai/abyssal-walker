extends Node

# 戰鬥相關
signal damage_dealt(source: Node, target: Node, damage_info: Dictionary)
signal enemy_died(enemy: Node, position: Vector2)
signal player_died
signal player_health_changed(current: float, max_hp: float)

# 掉落相關
signal item_dropped(item_data, position: Vector2)
signal item_picked_up(item_data)
signal equipment_dropped(equipment: EquipmentData, position: Vector2)
signal gem_dropped(gem: Resource, position: Vector2)
signal module_dropped(module: Module, position: Vector2)
signal material_dropped(material_id: String, amount: int, position: Vector2)

# 裝備相關
signal equipment_changed(slot: StatTypes.EquipmentSlot, old_item: EquipmentData, new_item: EquipmentData)
signal equipment_equipped(slot: StatTypes.EquipmentSlot, equipment: EquipmentData)
signal equipment_unequipped(slot: StatTypes.EquipmentSlot, equipment: EquipmentData)
signal stats_recalculated

# 寶石相關
signal skill_gem_changed(old_gem: SkillGem, new_gem: SkillGem)
signal support_gem_added(gem: SupportGem, slot_index: int)
signal support_gem_removed(gem: SupportGem, slot_index: int)
signal gem_leveled_up(gem: Resource, new_level: int)

# 深淵相關
signal floor_entered(floor_number: int)
signal floor_cleared(floor_number: int)
signal floor_failed(floor_number: int)
signal boss_spawned(boss: Node)
signal boss_defeated(boss: Node)

# 狀態效果
signal status_applied(target: Node, status_type: String, stacks: int)
signal status_removed(target: Node, status_type: String)
signal status_tick(target: Node, status_type: String, damage: float)

# Crafting
signal crafting_started(equipment: EquipmentData, material_id: String)
signal crafting_completed(equipment: EquipmentData, success: bool)

# UI
signal tooltip_requested(content: String, position: Vector2)
signal tooltip_hidden
signal notification_requested(message: String, type: String)
signal loot_filter_changed(mode: int)

# 遊戲狀態
signal game_paused
signal game_resumed
signal game_saved
signal game_loaded

# 統計數據
signal kill_count_changed(count: int)
signal dps_updated(dps: float)
