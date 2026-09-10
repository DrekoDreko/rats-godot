extends Control
## The sheets laid out for the whole crew, drawn over the road: which house goes
## first, and how long they give themselves in it once it is picked.
##
## Opened by `ContractManager.voting_opened` and put away by
## `voting_closed` — never by a button on this screen deciding for itself. The
## decision to open or close the vote is the host's and is already broadcast
## (`ContractManager.open_voting` / `settle_vote`); this file only draws what
## that autoload is holding and asks it to change one thing at a time: our own
## vote (`request_vote`), and, for the host alone, the booked hunt length and
## the moment the sheets come down.
##
## **Every card is open to every man, host included.** The buttons below the
## cards are not — the hunt length and the START button are the leader's, the
## same split the rest of the van already draws between "anybody may ask" and
## "only the leader decides".
##
## **It takes the player while it is up.** The van is already moving by the time
## the sheets go up, and a man walking about the box with a screen over his eyes
## is a man who cannot see where he is going — so the body is handed over the
## same way the shop hands it over (`player.gd: set_ui_open`), the mouse comes
## loose for the cards, and the HUD goes with it. He gets all three back the
## moment the vote is settled, which is the whole of "nobody moves until the
## crew has picked".

const CARD_SCENE := preload("res://scenes/contract_vote_card.tscn")

## The van's own HUD — the crosshair and the prompt line, both of them
## instructions for a man who is holding his own legs. Named rather than reached
## by group, the same as the pay slip does it (`result_screen.gd`): it is one
## `CanvasLayer` in the scene and hiding the layer hides the lot.
@export var hud_path: NodePath = ^"../../HUD"

@onready var _cards: HBoxContainer = $Margin/Center/Rows/CardsRow
@onready var _time_3: Button = $Margin/Center/Rows/TimeRow/Time3
@onready var _time_5: Button = $Margin/Center/Rows/TimeRow/Time5
@onready var _time_10: Button = $Margin/Center/Rows/TimeRow/Time10
@onready var _rate: BigFontOutlinedLabel = $Margin/Center/Rows/Rate
@onready var _start: Button = $Margin/Center/Rows/Start
@onready var _hint: BigFontOutlinedLabel = $Margin/Center/Rows/Hint
@onready var _money: BigFontOutlinedLabel = $MoneyRow/Total

## Every card on screen, by the job it stands for. Built once — the board
## does not change while the game is running (`ContractManager.contracts`) —
## and only ever redrawn afterwards.
var _card_of: Dictionary[String, ContractVoteCard] = {}

## The man this screen took, or null while it is down. Held so that he is given
## back to exactly whoever was taken — the scene can be changed out from under
## a vote that never closed.
var _player: Node

## What the HUD's visibility was before the sheets covered it, so putting them
## away gives back what was there rather than turning on a HUD something else
## had deliberately hidden.
var _hud_was_visible := true


func _ready() -> void:
	# The vote can be opened while the game is paused, the same as a phase
	# change can. `PhaseManager` and the other session autoloads are set this
	# way for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS

	hide()
	_outline_start()
	_build_cards()

	_time_3.pressed.connect(func() -> void:
		ContractManager.request_hunt_time(HuntTime.Type.SHORT))
	_time_5.pressed.connect(func() -> void:
		ContractManager.request_hunt_time(HuntTime.Type.MEDIUM))
	_time_10.pressed.connect(func() -> void:
		ContractManager.request_hunt_time(HuntTime.Type.LONG))
	_start.pressed.connect(func() -> void: ContractManager.settle_vote())

	ContractManager.voting_opened.connect(_on_voting_opened)
	ContractManager.voting_closed.connect(_on_voting_closed)
	ContractManager.vote_changed.connect(_on_vote_changed)
	ContractManager.hunt_time_set.connect(_on_hunt_time_set)
	ContractManager.request_refused.connect(_on_refused)
	# A Steam picture almost never arrives in time to be drawn with the vote it
	# belongs to — Steam answers on a callback, seconds later, and until then
	# the card carries the grey square. `SteamAvatars` says when one lands and
	# the sheets are redrawn, which is the same "correct it in place" every
	# other late arrival on this screen already gets.
	SteamAvatars.avatar_ready.connect(_on_avatar_ready)
	SessionManager.player_joined.connect(_on_crew_changed)
	SessionManager.player_left.connect(_on_crew_changed)
	SessionManager.bank_changed.connect(_on_bank_changed)

	# A newcomer can arrive with the vote already under way — the welcome
	# packet adopts it before this scene is even loaded (`JoinGate.adopt_votes`)
	# — so the screen has to check on the way up rather than wait for a signal
	# that already went out on somebody else's machine.
	if ContractManager.voting_open:
		_open()


## Puts the screen's line colour round the START button.
##
## The button is the black slab the menu already uses
## (`scenes/black_button.tscn`), and the only thing this screen wants changed
## about it is the edge. So each state is taken as it comes and handed back
## with a border, rather than the slab's four black styleboxes being copied
## into this scene to change one property of each — copies that would quietly
## stop matching the menu the day the slab is restyled.
##
## The duplicate is not optional: a scene's sub-resources are shared between
## every instance of it, so writing on the stylebox we are given would put an
## outlined edge on every black button in the game.
func _outline_start() -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := _start.get_theme_stylebox(state) as StyleBoxFlat
		if style == null:
			continue
		style = style.duplicate() as StyleBoxFlat
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = ContractVoteCard.LINE_COLOR
		_start.add_theme_stylebox_override(state, style)


func _build_cards() -> void:
	for contract in ContractManager.contracts:
		var card := CARD_SCENE.instantiate() as ContractVoteCard
		_cards.add_child(card)
		card.setup(contract)
		_card_of[contract.id] = card

# --- Opening and closing -----------------------------------------------------

func _on_voting_opened() -> void:
	_open()


func _on_voting_closed() -> void:
	_close()


func _open() -> void:
	if visible:
		return
	_refresh_all()
	show()
	_take_player(true)
	_show_hud(false)


func _close() -> void:
	if not visible:
		return
	hide()
	_take_player(false)
	_show_hud(true)


## The body handed over, or given back. Asked of whoever is in the map rather
## than kept anywhere: he is the one who holds the flag (`player.gd`), and a
## second record of it here would be one that could disagree with his.
func _take_player(taken: bool) -> void:
	if taken:
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_method("set_ui_open"):
		_player.set_ui_open(taken)
	if not taken:
		_player = null


func _show_hud(on: bool) -> void:
	var hud := get_node_or_null(hud_path) as CanvasLayer
	if hud == null:
		return
	if not on:
		_hud_was_visible = hud.visible
		hud.visible = false
		return
	hud.visible = _hud_was_visible

# --- Drawing ------------------------------------------------------------------

func _refresh_all() -> void:
	_money.text = tr("HUD_MONEY_TOTAL") % SessionManager.bank_balance
	var mine: String = ContractManager.votes.get(LobbyManager.our_crew_id(), "")
	for contract_id in _card_of:
		_card_of[contract_id].refresh(
			ContractManager.votes_for(contract_id),
			contract_id == mine,
			ContractManager.can_afford(contract_id))
	_refresh_time_buttons()
	_refresh_rate()
	_refresh_start()


func _refresh_time_buttons() -> void:
	var is_host := PhaseManager.is_host()
	_time_3.disabled = not is_host
	_time_5.disabled = not is_host
	_time_10.disabled = not is_host

	var current := ContractManager.hunt_time()
	_time_3.button_pressed = current == HuntTime.Type.SHORT
	_time_5.button_pressed = current == HuntTime.Type.MEDIUM
	_time_10.button_pressed = current == HuntTime.Type.LONG


func _refresh_rate() -> void:
	var per_rat := HuntTime.reward(ContractManager.hunt_time())
	_rate.text = tr("CONTRACT_VOTE_RATE") % per_rat


func _refresh_start() -> void:
	var is_host := PhaseManager.is_host()
	var everybody_voted := ContractManager.everybody_voted()

	_start.visible = is_host
	_start.disabled = not is_host or not everybody_voted

	# The host is told nothing while the crew is still voting. The START button
	# sitting there disabled already says it, and a line of text under it was
	# the same news written twice.
	if is_host:
		_hint.text = ""
	elif everybody_voted:
		_hint.text = tr("CONTRACT_VOTE_WAITING_HOST")
	else:
		_hint.text = tr("CONTRACT_VOTE_PICK_ONE")
	_hint.visible = not _hint.text.is_empty()

# --- What the autoloads say ---------------------------------------------------

func _on_vote_changed(_steam_id: int, _contract_id: String) -> void:
	if visible:
		_refresh_all()


func _on_bank_changed(_balance: int) -> void:
	if visible:
		_refresh_all()


func _on_refused(reason: String) -> void:
	if visible:
		_hint.text = reason
		_hint.show()


func _on_hunt_time_set(_value: HuntTime.Type) -> void:
	if visible:
		_refresh_time_buttons()
		_refresh_rate()


func _on_avatar_ready(_steam_id: int, _texture: ImageTexture) -> void:
	if visible:
		_refresh_all()


func _on_crew_changed(_steam_id: int) -> void:
	if visible:
		_refresh_all()
