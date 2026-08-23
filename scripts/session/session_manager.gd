extends Node
## Everything about the shift that has to outlive a scene: who is in the crew,
## what colour each of them is wearing, what contract was taken, and where in
## the shift we are.
##
## The van, the road and the house are three different scenes, and a shift walks
## through all of them. Anything kept in a node of one of those scenes is gone
## the moment the next one loads — so the colour a player picked in the van, the
## contract the host signed and the money in his pocket are kept here instead,
## on a node that is never unloaded. That is the whole reason this file exists.
##
## **It stores and it announces, and it does not touch the wire.** Nothing here
## sends an RPC or asks who the host is; every setter is a plain local write
## that emits a signal. What makes two machines agree is the layer above:
## whoever owns the change asks the host, the host validates it and calls these
## same setters on everybody (see the phase machine and the stations). Keeping
## the network out of here means this file can be read, tested and reasoned
## about on one machine, and it means there is exactly one place a change to a
## player can come from.
##
## The crew is keyed by **Steam ID and not by peer id**, on purpose. Peer ids
## belong to a wire and are handed out fresh by the next one; a Steam ID is the
## same number in the van, on the road and in the house. `LobbyManager` is what
## ties the two together (`steam_id_of_peer`).
##
## What it does *not* hold: the money already earned this session and the box of
## traps in the van. Those are `Wallet` and `Stock`, they are older than this
## file, and they are still single-player. The per-player `money` and
## `inventory` fields below are where the crew's own purses will live once the
## shop is on the wire; until then they are written by nobody and read by
## nobody, and the two old autoloads carry on as they are.

## Somebody joined the crew.
signal player_joined(steam_id: int)
## Somebody left it. Emitted after the entry is gone, so a listener that redraws
## the list off `players` sees the list it is about to draw.
signal player_left(steam_id: int)
## Something about a player changed — colour, ready, money, inventory. One
## signal for all of them, because every listener that cares about one of these
## redraws the same row anyway.
signal player_changed(steam_id: int)
## The contract was settled on.
signal contract_changed(contract_id: String)

## The colours a crew can wear, saturated and few, the way a PSX palette is.
## Eight for four players, so that there is a real choice left for the last one
## in rather than one colour and no say.
const COLORS: Array[Color] = [
	Color("ff2d2d"), ## red
	Color("2d6bff"), ## blue
	Color("29c443"), ## green
	Color("ffd429"), ## yellow
	Color("ff8b1f"), ## orange
	Color("b64bff"), ## purple
	Color("2ad4d4"), ## cyan
	Color("ff7fc4"), ## pink
]

## What a player is worth on the first day, before anything is earned. It is
## here rather than in `Wallet` because it is per player and the wallet is not.
const STARTING_MONEY := 100

## The crew, by Steam ID. Each entry is a dictionary of `name`, `color`,
## `ready`, `money`, `inventory` and `is_host` — see `_new_player`.
##
## Read it freely; write it through the methods below, so that the change is
## announced. Nothing on screen polls this.
var players: Dictionary[int, Dictionary] = {}

## The contract being worked, by id, or empty when none is signed yet. The
## contract resources themselves arrive with the clipboard station.
var current_contract := ""

## Where in the shift we are. The phase machine is what moves it; everybody else
## reads it.
var phase: Phase.Type = Phase.Type.LOBBY

## The number every random thing about this house is drawn from — which room the
## nests are in, which holes are real. The host rolls it once and hands it to
## everybody (`roll_seed`), and that is what makes four machines build the same
## house instead of four different ones.
var random_seed := 0


## A player joined. Handing in a Steam ID that is already in the crew is not a
## mistake worth losing a name over — the introduction can genuinely arrive
## twice — so it updates the name and announces a change rather than starting
## the entry over and wiping the colour and money off it.
func register_player(steam_id: int, player_name: String, is_host := false) -> void:
	if steam_id == 0:
		return
	if players.has(steam_id):
		var known := players[steam_id]
		known["name"] = player_name
		known["is_host"] = is_host
		player_changed.emit(steam_id)
		return
	players[steam_id] = _new_player(player_name, is_host)
	player_joined.emit(steam_id)


## A player left. The colour goes back on the rack with him, since the entry is
## what held it.
func remove_player(steam_id: int) -> void:
	if not players.erase(steam_id):
		return
	player_left.emit(steam_id)


## Whether somebody is in the crew at all. The one question worth asking before
## every other one here.
func has_player(steam_id: int) -> bool:
	return players.has(steam_id)


## What a player looks like right now, or an empty dictionary for somebody who
## is not in the crew. A copy is handed out on purpose: writing to it would be a
## change nobody was told about.
func player(steam_id: int) -> Dictionary:
	return players.get(steam_id, {}).duplicate()


## How many are in the crew.
func count() -> int:
	return players.size()


## Puts a player in a colour. It does not check whether anybody else is already
## wearing it — that is the host's call, and it is made before this is reached
## (see `is_color_taken`).
func set_color(steam_id: int, color: Color) -> void:
	_write(steam_id, "color", color)


## What colour a player is wearing, or white for somebody who is not in the
## crew — a colour, so that whoever is drawing a name never has to check first.
func color(steam_id: int) -> Color:
	return players.get(steam_id, {}).get("color", Color.WHITE)


## Who is wearing a colour already, or zero when nobody is. `except` leaves one
## player out of the question, which is how "is this colour free for me?" is
## asked by somebody who may already be wearing it.
func color_owner(color_wanted: Color, except := 0) -> int:
	for steam_id in players:
		if steam_id != except and players[steam_id]["color"] == color_wanted:
			return steam_id
	return 0


## Whether a colour is spoken for. `except` works as it does above.
func is_color_taken(color_wanted: Color, except := 0) -> bool:
	return color_owner(color_wanted, except) != 0


## The first colour nobody is wearing, which is what a player who has just
## walked in is put in. Falls back to the first of the palette when every one of
## them is taken — which needs more players than the van holds, and is still
## better answered with a colour than with a crash.
func first_free_color() -> Color:
	for palette_color in COLORS:
		if not is_color_taken(palette_color):
			return palette_color
	return COLORS[0]


## Marks a player ready, or not.
func set_ready(steam_id: int, value: bool) -> void:
	_write(steam_id, "ready", value)


## Whether a player has said he is ready.
func is_ready(steam_id: int) -> bool:
	return bool(players.get(steam_id, {}).get("ready", false))


## Whether everybody in the crew has said they are ready.
##
## An empty crew is not ready, and that is deliberate: the alternative is a
## shift that walks itself forward through every phase the moment the last
## player disconnects.
##
## Only the people actually in `players` are counted, which is what keeps a
## player who dropped out from holding the shift at the door forever — whoever
## handles the disconnect takes him out of the crew, and the question is asked
## again over who is left.
func all_ready() -> bool:
	if players.is_empty():
		return false
	for steam_id in players:
		if not players[steam_id]["ready"]:
			return false
	return true


## How many have said they are ready. The HUD draws this over `count()`.
func ready_count() -> int:
	var total := 0
	for steam_id in players:
		if players[steam_id]["ready"]:
			total += 1
	return total


## Everybody back to not-ready. It runs on every phase change: being ready to
## leave the van is not being ready to walk into the house, and a flag left
## standing would skip the next phase the instant it began.
func reset_ready() -> void:
	for steam_id in players:
		if players[steam_id]["ready"]:
			players[steam_id]["ready"] = false
			player_changed.emit(steam_id)


## Sets a player's money outright. The shop is what will call this, through the
## host, once buying is on the wire.
func set_money(steam_id: int, amount: int) -> void:
	_write(steam_id, "money", maxi(0, amount))


## What a player has in his pocket.
func money(steam_id: int) -> int:
	return int(players.get(steam_id, {}).get("money", 0))


## Puts an item in a player's bag, by the same id the store items carry
## (`scripts/economy/store_item.gd`).
func add_item(steam_id: int, item_id: String) -> void:
	if item_id.is_empty() or not players.has(steam_id):
		return
	var bag: Array[String] = players[steam_id]["inventory"]
	bag.append(item_id)
	player_changed.emit(steam_id)


## What a player is carrying. A copy, for the same reason `player()` hands one
## out.
func inventory(steam_id: int) -> Array[String]:
	if not players.has(steam_id):
		return [] as Array[String]
	return (players[steam_id]["inventory"] as Array[String]).duplicate()


## Who the crew answers to, or zero before anybody has been marked. It is the
## Steam ID the stations address their requests to.
func host_id() -> int:
	for steam_id in players:
		if players[steam_id]["is_host"]:
			return steam_id
	return 0


## Settles the contract and says so.
func set_contract(contract_id: String) -> void:
	if current_contract == contract_id:
		return
	current_contract = contract_id
	contract_changed.emit(contract_id)


## Rolls the number the house is built from and returns it. The host calls this
## once; everybody else is handed the answer and writes `random_seed` directly.
func roll_seed() -> int:
	random_seed = randi()
	return random_seed


## Wipes the shift back to the state the game boots in. The end of a shift, and
## the start of every test bench — the same job `Wallet.reset()` does, and named
## the same way for the same reason.
##
## The crew goes with it: a new shift is a new lobby, and whoever is still on
## the wire registers again on the way in.
func reset() -> void:
	for steam_id in players.keys():
		remove_player(steam_id)
	players.clear()
	current_contract = ""
	phase = Phase.Type.LOBBY
	random_seed = 0
	contract_changed.emit("")


## A blank crew member. The colour is settled here, on the way in, so that
## nobody is ever in the crew without one — a player with no colour is a grey
## body on somebody's screen for as long as it takes him to pick.
func _new_player(player_name: String, is_host: bool) -> Dictionary:
	return {
		"name": player_name,
		"color": first_free_color(),
		"ready": false,
		"money": STARTING_MONEY,
		"inventory": [] as Array[String],
		"is_host": is_host,
	}


## One field of one player, announced only when it actually moved. The guard is
## what keeps a station that re-sends the same colour twenty times a second from
## redrawing every HUD in the game twenty times a second.
func _write(steam_id: int, field: String, value: Variant) -> void:
	if not players.has(steam_id) or players[steam_id][field] == value:
		return
	players[steam_id][field] = value
	player_changed.emit(steam_id)
