extends Control

const GAME_SCENE := "res://scenes/main/game.tscn"
const LOBBY_GRID_RENDERER := preload("res://scripts/main/lobby/lobby_grid_renderer.gd")
const LOBBY_PRESENTER := preload("res://scripts/main/lobby/lobby_presenter.gd")
const LOBBY_PREP_SERVICE := preload("res://scripts/main/lobby/lobby_prep_service.gd")
const LOBBY_STATE_SERVICE := preload("res://scripts/main/lobby/lobby_state_service.gd")
const LOBBY_TOOLTIP_PRESENTER := preload("res://scripts/main/lobby/lobby_tooltip_presenter.gd")
const LOBBY_VIEW_BINDER := preload("res://scripts/main/lobby/lobby_view_binder.gd")
const SLOT_SIZE := Vector2(48, 48)
const GRID_COLUMNS := 7
const MIN_GRID_SLOTS := 63
const BEACON_GRID_COLUMNS := 3
const BEACON_CARD_SIZE := Vector2(190, 96)
const MIN_BEACON_SLOTS := 6

const LOOT_CATEGORIES: Array[Dictionary] = [
	{"key": "equipment", "label": "Equipment"},
	{"key": "skill_gems", "label": "Skill Gems"},
	{"key": "support_gems", "label": "Support Gems"},
	{"key": "modules", "label": "Modules"},
]

@onready var stash_total_label: Label = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryLeft/SummaryLeftBody/StashTotalLabel
@onready var stash_material_list: RichTextLabel = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryLeft/SummaryLeftBody/StashMaterialList
@onready var stash_loot_total_label: Label = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryRight/SummaryRightBody/StashLootTotalLabel
@onready var loadout_total_label: Label = $PrepOverlay/PrepPanel/PrepContent/SummaryRow/SummaryRight/SummaryRightBody/LoadoutTotalLabel
@onready var config_row: HBoxContainer = $RootPanel/Content/ConfigRow
@onready var beacon_count_label: Label = $RootPanel/Content/BeaconCard/BeaconCardBody/BeaconCount
@onready var beacon_grid: GridContainer = $RootPanel/Content/BeaconCard/BeaconCardBody/BeaconScroll/BeaconGrid
@onready var beacon_summary_label: Label = $RootPanel/Content/BeaconCard/BeaconCardBody/BeaconSummary
@onready var stash_category: OptionButton = $PrepOverlay/PrepPanel/PrepContent/LootRow/StashSide/StashBody/StashCategory
@onready var loadout_category: OptionButton = $PrepOverlay/PrepPanel/PrepContent/LootRow/LoadoutSide/LoadoutBody/LoadoutCategory
@onready var stash_grid: GridContainer = $PrepOverlay/PrepPanel/PrepContent/LootRow/StashSide/StashBody/StashScroll/StashGrid
@onready var loadout_grid: GridContainer = $PrepOverlay/PrepPanel/PrepContent/LootRow/LoadoutSide/LoadoutBody/LoadoutScroll/LoadoutGrid
@onready var add_button: Button = $PrepOverlay/PrepPanel/PrepContent/LootRow/ActionSide/ActionBody/AddButton
@onready var remove_button: Button = $PrepOverlay/PrepPanel/PrepContent/LootRow/ActionSide/ActionBody/RemoveButton
@onready var clear_loadout_button: Button = $PrepOverlay/PrepPanel/PrepContent/LootRow/ActionSide/ActionBody/ClearLoadoutButton
@onready var start_button: Button = $RootPanel/Content/ButtonsRow/StartButton
@onready var quit_button: Button = $RootPanel/Content/ButtonsRow/QuitButton
@onready var prep_toggle_button: Button = $RootPanel/Content/PrepToggleRow/PrepToggleButton
@onready var prep_overlay: Control = $PrepOverlay
@onready var prep_close_button: Button = $PrepOverlay/PrepPanel/PrepContent/PrepHeader/PrepCloseButton

var _lobby_grid_renderer: LobbyGridRenderer = LOBBY_GRID_RENDERER.new()
var _lobby_presenter = LOBBY_PRESENTER.new()
var _lobby_prep_service: LobbyPrepService = LOBBY_PREP_SERVICE.new()
var _lobby_state_service: LobbyStateService = LOBBY_STATE_SERVICE.new()
var _lobby_tooltip_presenter: LobbyTooltipPresenter = LOBBY_TOOLTIP_PRESENTER.new()
var _lobby_view_binder: LobbyViewBinder = LOBBY_VIEW_BINDER.new()


func _ready() -> void:
	prep_overlay.visible = false
	_lobby_presenter.setup(
		self,
		_lobby_prep_service,
		_lobby_state_service,
		_lobby_grid_renderer,
		_lobby_tooltip_presenter,
		_lobby_view_binder,
		LOOT_CATEGORIES,
		SLOT_SIZE,
		GRID_COLUMNS,
		MIN_GRID_SLOTS,
		BEACON_GRID_COLUMNS,
		BEACON_CARD_SIZE,
		MIN_BEACON_SLOTS,
		stash_total_label,
		stash_material_list,
		stash_loot_total_label,
		loadout_total_label,
		config_row,
		beacon_count_label,
		beacon_grid,
		beacon_summary_label,
		stash_category,
		loadout_category,
		stash_grid,
		loadout_grid,
		add_button,
		remove_button,
		clear_loadout_button,
		start_button,
		prep_toggle_button
	)
	_lobby_presenter.setup_controls()
	_bind_actions()
	_lobby_presenter.refresh_beacon_inventory()
	_lobby_presenter.refresh_all()


func _process(_delta: float) -> void:
	_lobby_presenter.process()


func _bind_actions() -> void:
	stash_category.item_selected.connect(Callable(_lobby_presenter, "on_stash_category_selected"))
	loadout_category.item_selected.connect(Callable(_lobby_presenter, "on_loadout_category_selected"))
	add_button.pressed.connect(Callable(_lobby_presenter, "move_selected_stash_to_loadout"))
	remove_button.pressed.connect(Callable(_lobby_presenter, "move_selected_loadout_to_stash"))
	clear_loadout_button.pressed.connect(Callable(_lobby_presenter, "clear_loadout"))
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	prep_toggle_button.pressed.connect(_on_prep_toggle_pressed)
	prep_close_button.pressed.connect(_on_prep_close_pressed)
	EventBus.beacon_inventory_changed.connect(Callable(_lobby_presenter, "on_beacon_inventory_changed"))


func _on_prep_toggle_pressed() -> void:
	prep_overlay.visible = true
	_lobby_presenter.refresh_all()


func _on_prep_close_pressed() -> void:
	prep_overlay.visible = false
	_lobby_presenter.hide_tooltip()


func _on_start_pressed() -> void:
	if not _lobby_presenter.start_selected_beacon(GameManager.OperationType.NORMAL):
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
