class_name Contract
extends Resource
## One job on the clipboard: whose house it is, where it is, how bad it is and
## what the crew is paid for clearing it.
##
## Each contract is a file in `resources/contracts/`. Another job on the board
## means duplicating one of those and changing the numbers — no code. The
## clipboard station reads the whole folder off disk
## (`scripts/session/contract_manager.gd`), so a new `.tres` shows up on the
## board without anything being registered anywhere.
##
## **It is a sheet of paper and nothing else.** No logic lives here: what the
## infestation level means for how many rats get spawned is the hunt's business,
## and what `house_scene` points at is the phase machine's (`set_house`). This
## only carries the numbers between them, which is what lets the house and the
## hunt be written later without touching the board.
##
## The `id` is what travels on the wire. When the host signs a contract, what is
## broadcast is this string and not the resource — every machine has the same
## folder on disk and looks the job up by id, so a `.tres` never crosses the
## network.

## The key the contract is known by, on the wire and in `SessionManager`. It has
## to be unique across the folder, and it is what `find` matches on.
@export var id := ""
## Who is paying: the name at the top of the sheet.
@export var client_name := "Client"
## Where the house is, as it reads on the sheet. Flavour, and the line under the
## client's name on the board.
@export var address := ""
## What the sheet says about the job, in a sentence or two.
@export var notes := ""

@export_group("The house")
## The scene the survey and the hunt are played in. This is what the phase
## machine is pointed at when the contract is signed (`PhaseManager.set_house`),
## and it is the one field that has to name a file that really exists.
@export_file("*.tscn") var house_scene := ""
## The floor plan, pinned to the map table on the road (card 11) and drawn on
## the clipboard here. Without one the sheet shows the writing and no picture.
@export var floor_plan: Texture2D

@export_group("The job")
## How many rats the house holds. The hunt draws its nests off this and off the
## shift's seed; here it is a number on a sheet the crew reads before signing.
@export_range(1, 60) var infestation := 6
## What the job pays when the house is cleared.
@export var reward := 250
## How hard it is, one to five. It is what the board sorts on and what the row
## of pips on the sheet is drawn from — a number rather than a word so that
## three contracts can be put in order without anybody writing the order down.
@export_range(1, 5) var difficulty := 1
