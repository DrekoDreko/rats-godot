class_name ContractVoteCard
extends Button
## One sheet in the crew's vote for the first job: the client's house, how bad
## it is, and — once there are icons for them — what kind of rats are in it.
##
## It draws and it asks, the same split every card in the van already keeps.
## Pressing it asks `ContractManager` to count our vote
## (`ContractManager.request_vote`); the tally and the highlight painted on it
## come back off that autoload's own signal, read by whoever is holding the
## row of cards (`contract_vote_screen.gd`) — this file never reads the vote
## for itself.

## The size a rat-type dot is drawn at. There are no icons for the breeds yet
## (`Contract.rat_types` is a list of ids and nothing more), so a dot is a
## plain hollow circle until there is an icon to put on it.
const DOT_SIZE := 13.0

## The green the whole vote screen is drawn in.
const LINE_COLOR := Color(0.42, 0.74, 0.49)

## How much the card leans out of the row while the mouse is on it. The row
## leaves 16px between cards (`contract_vote_screen.tscn`), and a card 200px
## wide grows 12 of those, so it never touches its neighbour. Growing by
## `scale` and not by size is the point: a container lays its children out by
## size, so a card that grew by size would shove the other two sideways.
const HOVER_SCALE := 1.06
const HOVER_TIME := 0.1

@onready var _name: Label = $Content/Name
@onready var _count: Label = $Content/Count
@onready var _votes: Label = $Content/Votes
@onready var _dots: VBoxContainer = $Content/Dots
@onready var _face: Panel = $Content/Face
@onready var _face_photo: TextureRect = $Content/Face/Photo
@onready var _photo: TextureRect = $Photo/Image
@onready var _mine: Panel = $Mine

## The job this card stands for, filled in by `setup`.
var contract_id := ""

## The growing or shrinking under way, kept only so that turning back halfway
## does not leave two tweens fighting over `scale`.
var _grow: Tween


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# A card grows from its middle, and the middle moves whenever the row
	# gives it a different size.
	resized.connect(_recenter_pivot)
	_recenter_pivot()


## Fills the card in for a job. Called once, straight after the instance is in
## the tree — the job has to be known before anything on the card can be
## drawn, and a node cannot be handed an argument on the way in.
func setup(contract: Contract) -> void:
	contract_id = contract.id
	# The photograph is cut to the card's shape and drawn behind the writing.
	# Only the frame is guaranteed: a job without a picture keeps the plain
	# card, which is what every card looked like before there were any.
	_photo.texture = contract.photo
	_name.text = contract.client_name
	_count.text = tr("CONTRACT_VOTE_RATS") % contract.infestation

	for dot in _dots.get_children():
		dot.queue_free()
	var types := contract.rat_types if not contract.rat_types.is_empty() else [""]
	for _type in types:
		_dots.add_child(_make_dot())

	refresh(0, false)


## Redraws the tally, the face under it and the highlight. Called by the screen
## off `ContractManager.vote_changed` and off a Steam picture landing, so a card
## never has to listen for itself.
##
## Only the man at this screen is drawn, and `is_mine` is already the question
## of whether he signed this sheet — so the face needs nothing the card is not
## being told anyway.
##
## `SteamAvatars.texture_of` never hands back nothing: an account whose picture
## Steam has not fetched yet gets the grey square, and asking is what starts the
## fetch. The face that lands afterwards arrives as `avatar_ready`, which the
## screen answers by calling this again (`contract_vote_screen.gd`).
func refresh(vote_count: int, is_mine: bool) -> void:
	_votes.text = tr("CONTRACT_VOTE_COUNT") % vote_count
	_mine.visible = is_mine

	_face.visible = is_mine
	if is_mine:
		_face_photo.texture = SteamAvatars.texture_of(LobbyManager.our_steam_id())


## One hollow dot on the row at the bottom of the card, standing in for a rat
## type until there is an icon to draw instead.
func _make_dot() -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	# The dots are stacked in a column, and a column stretches its children
	# across its whole width unless they are told to keep to themselves.
	dot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = LINE_COLOR
	var radius := int(DOT_SIZE / 2.0)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	dot.add_theme_stylebox_override("panel", style)

	return dot


func _recenter_pivot() -> void:
	pivot_offset = size / 2.0


## Leans the card out of the row, and lifts it above the other two so the
## grown edges are not painted over by whichever card is drawn after it.
func _on_mouse_entered() -> void:
	z_index = 1
	_grow_to(Vector2.ONE * HOVER_SCALE)


func _on_mouse_exited() -> void:
	# The card stays lifted until it is back in its own footprint; dropping it
	# straight away would let the neighbour cut across it while it shrinks.
	_grow_to(Vector2.ONE).finished.connect(func() -> void: z_index = 0)


func _grow_to(target: Vector2) -> Tween:
	if _grow != null:
		_grow.kill()
	_grow = create_tween()
	_grow.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_grow.tween_property(self, "scale", target, HOVER_TIME)
	return _grow


func _on_pressed() -> void:
	ContractManager.request_vote(LobbyManager.our_crew_id(), contract_id)
