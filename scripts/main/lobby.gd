extends Control

const GAME_SCENE := "res://scenes/main/game.tscn"

const LOOT_CATEGORIES := [
	{"key": "equipment", "label": "裝備"},
	{"key": "skill_gems", "label": "技能寶石"},
	{"key": "support_gems", "label": "輔助寶石"},
	{"key": "modules", "label": "模組"},
]

@onready var stash_total_label: Label = $RootPanel/Content/SummaryRow/SummaryLeft/StashTotalLabel
@onready var stash_material_list: RichTextLabel = $RootPanel/Content/SummaryRow/SummaryLeft/StashMaterialList
@onready var stash_loot_total_label: Label = $RootPanel/Content/SummaryRow/SummaryRight/StashLootTotalLabel
@onready var loadout_total_label: Label = $RootPanel/Content/SummaryRow/SummaryRight/LoadoutTotalLabel
@onready var operation_level_spin: SpinBox = $RootPanel/Content/ConfigRow/OperationLevelSpin
@onready var lives_spin: SpinBox = $RootPanel/Content/ConfigRow/LivesSpin
@onready var stash_category: OptionButton = $RootPanel/Content/LootRow/StashSide/StashCategory
@onready var loadout_category: OptionButton = $RootPanel/Content/LootRow/LoadoutSide/LoadoutCategory
@onready var stash_item_list: ItemList = $RootPanel/Content/LootRow/StashSide/StashList
@onready var loadout_item_list: ItemList = $RootPanel/Content/LootRow/LoadoutSide/LoadoutList
@onready var add_button: Button = $RootPanel/Content/LootRow/ActionSide/AddButton
@onready var remove_button: Button = $RootPanel/Content/LootRow/ActionSide/RemoveButton
@onready var clear_loadout_button: Button = $RootPanel/Content/LootRow/ActionSide/ClearLoadoutButton
@onready var start_button: Button = $RootPanel/Content/ButtonsRow/StartButton
@onready var quit_button: Button = $RootPanel/Content/ButtonsRow/QuitButton

var _stash_entries: Array[Dictionary] = []
var _loadout_entries: Array[Dictionary] = []


func _ready() -> void:
	_setup_controls()
	_bind_actions()
	_refresh_all()


func _setup_controls() -> void:
	operation_level_spin.min_value = 1
	operation_level_spin.max_value = 100
	operation_level_spin.step = 1
	operation_level_spin.rounded = true
	operation_level_spin.value = GameManager.get_operation_level()

	lives_spin.min_value = 1
	lives_spin.max_value = 9
	lives_spin.step = 1
	lives_spin.rounded = true
	lives_spin.value = GameManager.get_lives_max()

	stash_category.clear()
	loadout_category.clear()
	for entry in LOOT_CATEGORIES:
		stash_category.add_item(str(entry["label"]))
		stash_category.set_item_metadata(stash_category.item_count - 1, str(entry["key"]))
		loadout_category.add_item(str(entry["label"]))
		loadout_category.set_item_metadata(loadout_category.item_count - 1, str(entry["key"]))

	stash_category.select(0)
	loadout_category.select(0)
	stash_item_list.select_mode = ItemList.SELECT_SINGLE
	loadout_item_list.select_mode = ItemList.SELECT_SINGLE


func _bind_actions() -> void:
	stash_category.item_selected.connect(func(_index: int) -> void: _refresh_stash_list())
	loadout_category.item_selected.connect(func(_index: int) -> void: _refresh_loadout_list())
	add_button.pressed.connect(_on_add_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	clear_loadout_button.pressed.connect(_on_clear_loadout_pressed)
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _refresh_all() -> void:
	_refresh_summary()
	_refresh_stash_list()
	_refresh_loadout_list()


func _refresh_summary() -> void:
	stash_total_label.text = "倉庫材料總量: %d" % GameManager.get_stash_material_total()

	var lines: Array[String] = []
	for material_id in DataManager.get_all_material_ids():
		var amount: int = GameManager.get_stash_material_count(material_id)
		if amount <= 0:
			continue
		var mat_data: Dictionary = DataManager.get_crafting_material(material_id)
		lines.append("- %s x%d" % [str(mat_data.get("display_name", material_id)), amount])
	if lines.is_empty():
		lines.append("- 無")
	stash_material_list.text = "\n".join(lines)

	var stash_counts: Dictionary = GameManager.get_stash_loot_counts()
	var loadout_counts: Dictionary = GameManager.get_operation_loadout_counts()
	stash_loot_total_label.text = "倉庫戰利品: 裝備 %d / 寶石 %d / 模組 %d" % [
		int(stash_counts.get("equipment", 0)),
		int(stash_counts.get("total_gems", 0)),
		int(stash_counts.get("modules", 0)),
	]
	loadout_total_label.text = "出戰配置: 裝備 %d / 寶石 %d / 模組 %d" % [
		int(loadout_counts.get("equipment", 0)),
		int(loadout_counts.get("total_gems", 0)),
		int(loadout_counts.get("modules", 0)),
	]


func _refresh_stash_list() -> void:
	_stash_entries.clear()
	stash_item_list.clear()
	var category: String = _selected_category_key(stash_category)
	var snapshot: Dictionary = GameManager.get_stash_loot_snapshot()
	var items: Array = snapshot.get(category, [])
	for i in range(items.size()):
		_stash_entries.append({"category": category, "index": i})
		stash_item_list.add_item(_loot_label(items[i]))


func _refresh_loadout_list() -> void:
	_loadout_entries.clear()
	loadout_item_list.clear()
	var category: String = _selected_category_key(loadout_category)
	var snapshot: Dictionary = GameManager.get_operation_loadout_snapshot()
	var items: Array = snapshot.get(category, [])
	for i in range(items.size()):
		_loadout_entries.append({"category": category, "index": i})
		loadout_item_list.add_item(_loot_label(items[i]))


func _selected_category_key(option: OptionButton) -> String:
	if option.item_count <= 0:
		return "equipment"
	var idx := option.selected
	if idx < 0:
		idx = 0
	return str(option.get_item_metadata(idx))


func _loot_label(item: Variant) -> String:
	if item is EquipmentData:
		var eq: EquipmentData = item
		var rarity_name: String = StatTypes.RARITY_NAMES.get(eq.rarity, "Unknown")
		return "%s [%s]" % [eq.display_name, rarity_name]
	if item is SkillGem:
		var sg: SkillGem = item
		return "技能寶石: %s Lv%d" % [sg.display_name, sg.level]
	if item is SupportGem:
		var sp: SupportGem = item
		return "輔助寶石: %s Lv%d" % [sp.display_name, sp.level]
	if item is Module:
		var mod: Module = item
		return "模組: %s" % mod.display_name
	return "未知物品"


func _on_add_pressed() -> void:
	var selected := stash_item_list.get_selected_items()
	if selected.is_empty():
		return
	var list_index: int = int(selected[0])
	if list_index < 0 or list_index >= _stash_entries.size():
		return
	var entry: Dictionary = _stash_entries[list_index]
	if GameManager.move_stash_loot_to_loadout(str(entry["category"]), int(entry["index"])):
		_refresh_all()


func _on_remove_pressed() -> void:
	var selected := loadout_item_list.get_selected_items()
	if selected.is_empty():
		return
	var list_index: int = int(selected[0])
	if list_index < 0 or list_index >= _loadout_entries.size():
		return
	var entry: Dictionary = _loadout_entries[list_index]
	if GameManager.move_loadout_loot_to_stash(str(entry["category"]), int(entry["index"])):
		_refresh_all()


func _on_clear_loadout_pressed() -> void:
	var snapshot: Dictionary = GameManager.get_operation_loadout_snapshot()
	for category_entry in LOOT_CATEGORIES:
		var category: String = str(category_entry["key"])
		var items: Array = snapshot.get(category, [])
		for i in range(items.size() - 1, -1, -1):
			GameManager.move_loadout_loot_to_stash(category, i)
	_refresh_all()


func _on_start_pressed() -> void:
	var operation_level := int(operation_level_spin.value)
	var lives := int(lives_spin.value)
	GameManager.reset_risk()
	GameManager.start_operation(operation_level, GameManager.OperationType.NORMAL, lives)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
