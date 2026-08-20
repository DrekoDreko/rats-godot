extends VBoxContainer
## The wallet on screen: what the shift has earned so far, and a passing notice
## of the last animal delivered.
##
## It only mirrors the `Wallet` autoload — it never keeps a count of its own, so
## the number on screen cannot drift from the one that survives the map.

## How long the notice stays whole on screen before it starts to fade.
const NOTICE_HOLD := 1.6
## How long the fade itself takes.
const NOTICE_FADE := 0.8

@onready var total: Label = $Total
@onready var notice: Label = $Notice

## What is left of the notice's life, in seconds. Zero means there is none.
var _notice_time := 0.0

func _ready() -> void:
	notice.modulate.a = 0.0
	set_process(false)
	# `Wallet` is an autoload: it is already in the tree, so there is no frame to
	# wait for here, unlike the HUD pieces that go looking for the player.
	Wallet.money_changed.connect(_on_money_changed)
	Wallet.catch_recorded.connect(_on_catch_recorded)
	# The map may start over with money already earned.
	_on_money_changed(Wallet.money, 0)

func _process(delta: float) -> void:
	_notice_time -= delta
	if _notice_time <= 0.0:
		notice.modulate.a = 0.0
		set_process(false)
		return
	notice.modulate.a = minf(1.0, _notice_time / NOTICE_FADE)

## The total comes from the signal and not from `Wallet.money` so that a
## `reset()`, which announces zero, wipes the screen along with the wallet.
func _on_money_changed(total_value: int, _gain: int) -> void:
	total.text = "$ %d" % total_value

func _on_catch_recorded(_species: RatSpecies, death_type: Death.Type, value: int) -> void:
	# The death is what the player can still act on: it is the discount they pay
	# for how they killed. Once there is more than one breed on the map,
	# `_species.display_name` joins the line.
	notice.text = "+$%d  %s" % [value, Death.name_of(death_type)]
	notice.modulate.a = 1.0
	_notice_time = NOTICE_HOLD + NOTICE_FADE
	set_process(true)
