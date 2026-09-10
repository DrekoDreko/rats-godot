class_name TerminalScreen
extends Control
## The one screen painted on the CRT: the shop, the map, the job sheet and
## the palette, leafed through with the two arrows rather than four different
## machines.
##
## **It owns nothing about any of the four pages.** Each one — `StoreScreen`,
## `MapViewer`, `DifficultyScreen`, `ColorScreen` — is exactly the control it
## always was, drawn
## and driven the same way it always has been. This node only decides which one
## is showing and hands the terminal's own bookkeeping (closing the rest of the
## HUD and keeps its own open and closed state up to itself,
## so that switching pages is never mistaken for shutting the terminal.
##
## **Switching pages is not closing one.** `StoreScreen.closed` and
## `MapViewer.closed` exist for benches that open them on their own; this node
## never connects to either, so pressing an arrow can never trigger the camera
## terminal from shutting when a page changes.

signal closed

enum Page { SHOP, MAP, DIFFICULTY, COLOR }

## The order the arrows leaf through, left to right.
const ORDER: Array[Page] = [Page.SHOP, Page.MAP, Page.DIFFICULTY, Page.COLOR]
const OPEN_PHASES: Array[Phase.Type] = [
	Phase.Type.TRAVEL, Phase.Type.SURVEY, Phase.Type.HUNT,
]

@onready var _shop: Control = $Pages/StoreScreen
@onready var _map: Control = $Pages/MapViewer
@onready var _difficulty: Control = $Pages/DifficultyScreen
@onready var _color: Control = $Pages/ColorScreen
@onready var _left: Button = $Nav/Left
@onready var _right: Button = $Nav/Right

var _index := 0
var _open := false
var _user: Node3D


func _ready() -> void:
	# A SubViewport is not a Control parent, so anchor-only sizing can resolve
	# to zero for this root. Match the terminal UI to the viewport explicitly so
	# the pages have a canvas to draw into before its texture reaches the CRT.
	var viewport := get_parent() as SubViewport
	if viewport != null:
		size = Vector2(viewport.size)
	add_to_group("terminal_screen")
	# Every page shut before the glass is ever lit. Three of the four put
	# themselves away in their own `_ready()`, but `MapViewer` is saved visible
	# in its scene file, and a page nobody has closed comes up *over* whichever
	# page the terminal did open. Which page is up is this node's to say, so it
	# says it here rather than trusting four scene files to agree — and it says
	# it with `close()` and not `hide()`, because a page is more than its own
	# visibility (`StoreScreen` shows and hides a child of its own), and it says
	# it of every page hanging under `Pages` rather than of the ones the arrows
	# happen to leaf through, so a page added to the scene is down from the
	# start whether or not it has been wired into `ORDER` yet.
	for page in $Pages.get_children():
		(page as Control).close()
	hide()
	_left.pressed.connect(_step.bind(-1))
	_right.pressed.connect(_step.bind(1))
	PhaseManager.phase_changed.connect(_on_phase_changed)


## Puts the terminal up on the page it was last left on.
func open(by: Node3D) -> bool:
	if _open or by == null or not by.has_method("set_ui_open"):
		return false
	if not OPEN_PHASES.has(PhaseManager.current()):
		return false
	_open = true
	_user = by
	_user.set_ui_open(true)
	_show_rest_of_hud(false)
	show()
	_page(ORDER[_index]).open()
	return true


## Takes the terminal down, wherever it was left leafed to.
func close() -> void:
	if not _open:
		return
	_open = false
	var user := _user
	_user = null
	_page(ORDER[_index]).close()
	_show_rest_of_hud(true)
	hide()
	if is_instance_valid(user) and user.has_method("set_ui_open"):
		user.set_ui_open(false)
	closed.emit()


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("toggle_mouse"):
		close()
		get_viewport().set_input_as_handled()


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	if _open:
		close()


## One arrow: the current page goes down, the next one comes up. `direction`
## is +1 or -1, bound once per button in `_ready()`.
func _step(direction: int) -> void:
	if not _open:
		return
	_page(ORDER[_index]).close()
	_index = wrapi(_index + direction, 0, ORDER.size())
	_page(ORDER[_index]).open()


func _page(page: Page) -> Control:
	match page:
		Page.SHOP:
			return _shop
		Page.MAP:
			return _map
		Page.DIFFICULTY:
			return _difficulty
		_:
			return _color

# --- The rest of the HUD -----------------------------------------------------
# Moved here from `StoreScreen`, which used to be the only page and so was the
# only thing that had to ask for the crosshair, the prompt, the belt and the
# phase clock to get out of the way. Now that four pages share the glass, it is the
# terminal's own opening and closing that decides whether the rest of the HUD
# is showing — never a single page's, or switching from the shop to the map
# would flash the crosshair back on for the frame between them.

func _show_rest_of_hud(on: bool) -> void:
	var clock := get_tree().get_first_node_in_group("hud_phase") as CanvasLayer
	if clock != null:
		clock.visible = on

	var hud := get_tree().root.find_child("HUD", true, false)
	if hud == null:
		return
	var crosshair := hud.get_node_or_null("Crosshair") as CanvasItem
	if crosshair != null:
		crosshair.visible = on

	# The belt goes with it — the three squares and the health bar over them.
	# A man reading the monitor has his legs and his hands taken off him, so
	# neither the slot he is on nor the flesh he has left is anything he can do
	# something about while the glass is up, and a belt drawn at the foot of a
	# screen that is itself a screen reads as two screens at once.
	#
	# It is the container that is hidden and not the two widgets inside it: with
	# a rat in his hands they have already hidden themselves
	# (`hud_hotbar.gd`, `hud_health.gd`), and showing *them* again on the way out
	# would put the belt back over a strangling that is still going on.
	var belt := hud.get_node_or_null("Belt") as CanvasItem
	if belt != null:
		belt.visible = on
	if not on:
		var prompt := hud.get_node_or_null("Prompt") as CanvasItem
		if prompt != null:
			prompt.hide()
