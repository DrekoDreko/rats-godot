class_name Phase
extends RefCounted
## The stages a shift goes through, from the van pulling up to the pay slip.
##
## It lives apart from the two autoloads that use it, and that is the whole
## point: `SessionManager` has to store which phase the shift is in, and the
## phase machine (`PhaseManager`) has to drive it, and neither one should have
## to load the other to name a phase. A plain table depends on nobody, so both
## can.
##
## What each phase is for, in a line each:
##
## - **LOBBY.** The van is parked. Colours, the contract and who is ready.
##   Nobody is in a hurry, so there is no clock.
## - **TRAVEL.** The van is moving. Two minutes to spend money and read the
##   floor plan, and then it goes whether the crew is ready or not.
## - **SURVEY.** Inside the house with the lights on and no rats out. A minute
##   to walk it, find the holes and set the traps.
## - **HUNT.** The same house, the same traps, the rats loose. It ends when the
##   house is clear, or when the clock the crew booked in the van runs out —
##   whichever comes first.
## - **RESULT.** What the shift paid.
##
## This class is only a table: nothing is ever instantiated from it.

enum Type {
	LOBBY,  ## Van parked, crew assembling.
	TRAVEL, ## Van moving, two minutes of shopping and planning.
	SURVEY, ## In the house, lights on, no rats: one minute to set up.
	HUNT,   ## The same house with the rats out.
	RESULT, ## The tally at the end of the shift.
}

## How long each phase lasts, in seconds. Zero means there is no clock on it:
## `LOBBY` waits on the crew and `RESULT` waits on it being read, and neither one
## should be hurried by a number.
##
## **The hunt is not in this table, and that is the point of it being zero here.**
## Its length is not a property of the phase but of the shift — the crew books it
## at ten minutes, five or two, and is paid accordingly (`HuntTime`). Ask
## `PhaseManager.duration_of` rather than this for a length that has to be right
## for the shift in hand; this table is what that function falls back on for
## every other phase.
const DURATION := {
	Type.LOBBY: 0.0,
	Type.TRAVEL: 120.0,
	Type.SURVEY: 60.0,
	Type.HUNT: 0.0,
	Type.RESULT: 0.0,
}

## What each phase is called on screen and in the test benches.
const NAMES := {
	Type.LOBBY: "lobby",
	Type.TRAVEL: "travel",
	Type.SURVEY: "survey",
	Type.HUNT: "hunt",
	Type.RESULT: "result",
}

## How long this phase runs, or zero when nothing is timing it.
static func duration(type: Type) -> float:
	return DURATION.get(type, 0.0)

## Whether a clock runs during this phase, by the table alone. Whoever wants the
## answer for the shift actually being played asks `PhaseManager.has_timer`,
## which knows what the hunt was booked at.
static func has_timer(type: Type) -> bool:
	return duration(type) > 0.0

static func name_of(type: Type) -> String:
	return NAMES.get(type, "unknown")
