class_name CrewList
extends VBoxContainer
## Who else is in the shift, one row each: a dot in the man's colour, his name,
## how many rats he has taken and how far away he is.
##
## It is asked for in two places and it is the same list in both — the pause menu
## a player opens when somebody has stopped moving, and the scoreboard he holds
## Tab for in the van and in the dark. Two copies of a list is two places for the
## crew to be drawn differently, which is exactly the confusion the list exists
## to settle.
##
## **It reads and it draws.** Every number is already on an autoload:
## `SessionManager` for the crew, their colours and their counts, `LobbyManager`
## for the ping. Nothing here is stored and nothing is asked of the host.
##
## The list is drawn off `SessionManager.players` and not off
## `LobbyManager.list_players()`, and the difference is the whole point of it.
## The guest list is Valve's answer to "who is in this lobby"; the crew is the
## game's answer to "who is actually in this shift", which is the question a man
## is asking when he opens a menu to see whether the others are still there. They
## part company exactly when it matters — a player who joined the lobby but never
## got through `JoinGate`, a player whose game died without Steam noticing yet.
##
## **It only ticks while it can be seen.** A ping is a number that wanders by a
## few milliseconds between one reading and the next, so the rows are rebuilt on
## a slow countdown rather than every frame — and the countdown stops dead with
## the list hidden, which is nearly all of the time.

## How often the rows are rebuilt while the list is up, in seconds. Half a second
## is fast enough that a man who has just walked out is gone before it is
## noticed, and slow enough to read.
const REFRESH := 0.5

## The dot in front of each name, drawn in that player's colour. A filled circle
## is the one glyph that reads as a colour swatch at eight points.
const SWATCH := "●"

## What marks the host in the list, as a translation key. It goes after the
## name rather than before, so that the names still line up under each other.
const HOST_MARK := "PAUSE_HOST_MARK"

## The rat beside a man's tally — the same glyph the counter in the corner of the
## HUD is already drawn with, so a player reads the column without being told
## what it is. A picture rather than a word, which also spares the count a plural
## it would get wrong in one language or the other.
const CATCH_ICON := preload("res://assets/textures/hud/icon_rat.svg")
const CATCH_ICON_SIZE := Vector2(10, 10)

## What a row says where a ping would go when there is none to show — solo, or a
## peer who has not answered his first probe. An em dash and not "0 ms", which
## would be a lie of exactly the kind a player would believe.
const NO_PING := "—"

## Font size for a crew row. The same eight points the rest of the small text in
## the game is set in: this is a footnote, not a headline.
const FONT_SIZE := 8
const OUTLINE_SIZE := 4

## The two thresholds a player would draw himself, and the grey for a row with no
## number at all — so that "we do not know" never looks like "this is fine".
const PING_GOOD := 80
const PING_FAIR := 180
const PING_COLOR := {
	"good": Color(0.42, 0.86, 0.42),
	"fair": Color(0.95, 0.83, 0.35),
	"poor": Color(0.95, 0.42, 0.42),
	"none": Color(0.72, 0.72, 0.72),
}

## What is left of the wait before the rows are built again.
var _countdown := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	set_process(false)
	_on_visibility_changed()
	visibility_changed.connect(_on_visibility_changed)


func _process(delta: float) -> void:
	_countdown -= delta
	if _countdown > 0.0:
		return
	_countdown = REFRESH
	refresh()


## Throws the rows away and builds them again from the crew as it stands. Public
## because a screen that has just come up wants the list right in its first frame
## rather than half a second into it.
##
## Rebuilt whole rather than kept in step row by row: four rows is nothing to
## build, and a list that is rebuilt whole can never be a list that quietly
## disagrees with the crew.
func refresh() -> void:
	for row in get_children():
		row.queue_free()

	# Sorted, and by Steam ID rather than by name: the crew is a dictionary and
	# its order is whatever order people happened to arrive in on this machine,
	# which is not the same order on the next one. A man should not find himself
	# in a different place in the list on his friend's screen — and a list that
	# reshuffles as somebody leaves is one nobody can read.
	var ids := SessionManager.players.keys()
	ids.sort()
	for steam_id in ids:
		# Added below the freed ones rather than after them: `queue_free` only
		# lands at the end of the frame.
		add_child(_row(steam_id))


## One line: a dot in the player's colour, his name, the host mark if it is his,
## his tally and his ping.
##
## The dot is a `Label` of its own so that only it carries the colour — a whole
## row tinted red would be a row that reads as an error rather than as a man in
## a red suit.
func _row(steam_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var swatch := _label(SWATCH, SessionManager.color(steam_id))
	row.add_child(swatch)

	var player := SessionManager.player(steam_id)
	var shown_name := String(player.get("name", "..."))
	if SettingsManager.streamer_mode:
		shown_name = ColorManager.display_name_for(steam_id)
	if bool(player.get("is_host", false)):
		shown_name += tr(HOST_MARK)
	var name_label := _label(shown_name, Color.WHITE)
	# The name takes whatever width is going, which is what pins the two numbers
	# to the right-hand edge however long or short the names turn out to be.
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var icon := TextureRect.new()
	icon.texture = CATCH_ICON
	icon.custom_minimum_size = CATCH_ICON_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var tally := _label(str(SessionManager.catches(steam_id)), Color.WHITE)
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(tally)

	var ping := _label(_ping_text(steam_id), _ping_color(steam_id))
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(ping)

	return row


## A cell, dressed the way every other line of small text in the game is: flat
## colour with a hard black outline behind it, so it stays legible over whatever
## the house happens to be showing underneath.
func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	return label


## The ping as a player reads it. Our own row and a solo run both come back
## without a number: asking a man how far he is from himself is not a question,
## and answering "0 ms" would suggest a wire that is not there.
func _ping_text(steam_id: int) -> String:
	var ping := _ping(steam_id)
	return NO_PING if ping < 0 else "%d ms" % ping


func _ping_color(steam_id: int) -> Color:
	var ping := _ping(steam_id)
	if ping < 0:
		return PING_COLOR["none"]
	if ping < PING_GOOD:
		return PING_COLOR["good"]
	if ping < PING_FAIR:
		return PING_COLOR["fair"]
	return PING_COLOR["poor"]


## The round trip to a player, or a negative for "there is no number here".
func _ping(steam_id: int) -> int:
	if steam_id == LobbyManager.our_steam_id():
		return -1
	return LobbyManager.ping_of_steam_id(steam_id)


## The countdown runs only while the list is actually on screen — hidden behind
## the menu's other page, or in a HUD nobody is holding Tab on, it costs nothing.
## Coming up rebuilds at once, so the first frame a player sees is current.
func _on_visibility_changed() -> void:
	var showing := is_visible_in_tree()
	set_process(showing)
	if showing:
		_countdown = REFRESH
		refresh()
