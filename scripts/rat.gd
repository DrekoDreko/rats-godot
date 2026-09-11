extends CharacterBody3D
## Rat: a fearful mob. It wanders the map slowly, bolts when the player comes
## close and looks for a spot outside his line of sight to hide in. When the
## player grabs it, it is torn off the ground and ends up in his hand, where it
## struggles until it is strangled — and then comes apart in his fist — or until
## it gets loose and goes back to fleeing.
##
## Both the wandering and the fleeing follow the navigation mesh baked in
## `world.tscn`: it only picks destinations it can actually reach, and the path
## to them already comes routed around the walls and the crates.

signal died(rat: Node3D, death_type: Death.Type)

## The order is the wire format (`sync_state`), so anything new goes on the end.
enum State { WANDERING, IDLE, FLEEING, HIDING, CAPTURED, DEAD, SPRAYING }

## The beats of the capture, from the grab until the animal comes apart in the
## fist.
##
## `BURSTING` is where a strangling now ends, and it replaced two phases that
## used to follow it: the body going limp in the hand, and the arm carrying the
## carcass down to the waist. It is a shorter beat than either of them on
## purpose — what it draws is the half-second in which the rat is squeezed past
## what it can take, and then there is no rat.
enum Capture { POUNCE, RISING, IN_HAND, BURSTING }

@export_group("Species")
## Which rat this is: where its fur and its price come from. See
## `resources/species/`.
@export var species: RatSpecies

@export_group("Movement")
@export var wander_speed := 2.2
## Fleeing speed: slower than the player's run, faster than his walk.
@export var flee_speed := 7.0
## The startled dash, in the first moments of the flight.
@export var burst_speed := 9.5
@export var acceleration := 45.0
@export var gravity := 22.0
@export var turn_speed := 11.0
## Ground distance between two rat footsteps.
const STEP_DISTANCE := 0.8

@export_group("Perception")
## Distance at which the rat flees if it can see the player.
@export var alert_radius := 16.0
## Distance at which it flees even without seeing the player (it heard footsteps).
@export var panic_radius := 6.0
## Hidden, it holds its breath and only bolts if the player nearly steps on it.
@export var hidden_panic_radius := 3.0
## Distance from which it feels safe again.
@export var safe_radius := 26.0

@export_group("Health")
@export var max_health := 1
@export var knockback_force := 5.0

## Height of the rat's eyes, used in the line-of-sight checks.
const EYE_HEIGHT := 0.10
## Height of the player's chest, the point the rat tries to see.
const PLAYER_HEIGHT := 1.2
## Above this ground speed a man counts as running, and a running man is noticed
## from further off (`_alert_radius_for`). It was a bare 7.0 in the middle of the
## sight check for as long as there was one player to ask; it is a constant now
## because it is asked of everybody in the house, character and avatar alike, and
## the two work their speed out by different roads.
const RUNNING_SPEED := 7.0
## Only the scenery takes part in the sight and clearance checks (layer 1).
const SCENERY_LAYER := 1
## Range of the "whiskers" that sniff out walls ahead. They only come into play
## when the rat has no path through the mesh and has to run on instinct.
const WHISKER_RANGE := 2.2
## Angles (degrees) tried when routing around an obstacle, smallest detour first.
const DODGE_ANGLES := [32.0, -32.0, 64.0, -64.0, 100.0, -100.0]
## How long the initial dash of the flight lasts.
const BURST_TIME := 1.2
## How often it reconsiders its hideout while fleeing.
const SEARCH_INTERVAL := 0.6
## Radius in which it looks for obstacles to use as cover.
const COVER_RADIUS := 14.0
## How many obstacles it considers per search.
const MAX_COVERS := 10
## Steps taken behind an obstacle looking for the blind spot.
const COVER_STEPS := 8
const COVER_STEP := 1.5
## Points rolled behind it on each search, on top of the covers.
const CANDIDATES := 10
## Spread (radians) of the flight fan, to each side of "away from the player".
const FAN_SPREAD := 1.8
const MIN_SEARCH_DISTANCE := 3.0
const MAX_SEARCH_DISTANCE := 15.0
## Maximum distance a destination may sit from the navigation mesh. Beyond that
## it landed inside a wall or off the map and is no destination at all.
const MESH_TOLERANCE := 1.5
## Maximum height difference accepted in a destination — the rat does not climb
## crates.
const MAX_HEIGHT_DROP := 1.5
## What vanishing from the player's view is worth in a hideout's score.
const HIDDEN_BONUS := 25.0
## What each free exit around the hideout is worth: a dead end hides well, but
## leaves the rat with nowhere to run afterwards.
const EXIT_BONUS := 3.0
const EXIT_RANGE := 2.5
## Weight of the path length in the score: close beats far.
const PATH_WEIGHT := 0.6
## Penalty for a path that grazes the player.
const NEAR_MISS_PENALTY := 60.0
## What a dead rat left rotting in a trap does to the ground around it. It is
## heavier than the bonus for being out of sight (`HIDDEN_BONUS`) on purpose: a
## rat would rather be seen than lie down next to a corpse.
const FEAR_PENALTY := 40.0
## What crossing that ground costs on the way somewhere else. Lighter than
## standing in it: a rat in a hurry will run past what it would never sit in.
const FEAR_CROSSING_PENALTY := 30.0
## How far a foul spot's reach goes when it does not say (`fear_radius`).
const DEFAULT_FEAR_RADIUS := 4.0
## How far a baited heap of rubbish pulls from when it does not say
## (`lure_radius`). It is the mirror of the line above: ground the rats want.
const DEFAULT_LURE_RADIUS := 22.0
## How often a rat picking somewhere new to stroll makes for the food rather
## than for a spot of its own choosing. Not one, on purpose — a house where
## every animal walked straight to the bait would be a house with one room in it,
## and the crew would never have to look anywhere else.
const LURE_PULL := 0.65
## How wide a circle round the food a rat is content to end up in. The animals
## mill about the heap rather than stack up on a single point.
const LURE_SPREAD := 2.5
## How often the map's foul spots are re-read. They do not move and are not made
## often, so the rat reads them on a slow clock and every decision it makes in
## between uses the list it already has.
const FEAR_REFRESH := 0.5
## How many times the wander re-rolls a destination that turned out to be foul
## before giving up and standing still for a moment.
const WANDER_TRIES := 4

# --- Bolting through the walls ----------------------------------------------
#
# A hole is one mouth of a run through the walls and the far one is somewhere
# else in the house (`scripts/house/rat_hole.gd`). A cornered rat that reaches
# one is gone: it dives in and comes out at the other end, which is the single
# most useful thing the crew can have learned during the survey and the single
# most infuriating thing to watch if they did not.

## How far a fleeing rat will go out of its way for a hole. Shorter than the
## hideout search (`COVER_RADIUS`): bolting is what it does when a way out is
## right there, not a thing it crosses the house for.
const BOLT_RADIUS := 12.0
## How long after coming out of a hole before it will dive into another one. It
## is what stops a rat that is frightened at both ends of a run from spending the
## hunt flickering between them.
const BOLT_COOLDOWN := 6.0
## How much further from the hunters the far mouth has to be before the run is
## worth taking. A hole that puts the animal down beside the man chasing it is
## not an escape.
const BOLT_GAIN := 4.0

# --- Spraying ---------------------------------------------------------------
#
# What one breed does instead of only running (`RatSpecies.sprays`). Cornered, it
# stops, turns, and gets the man in the face. It is the only thing in the game
# that hurts the player on purpose, and it is built to be *dodgeable*: the animal
# plants itself and plays its attack for a third of a second before anything
# lands, which is the whole of the counterplay — back off, or wear it.

## How close a hunter has to be before it stops running and turns on him. Inside
## its own `panic_radius`, so a rat only ever sprays somebody who is already on
## top of it.
const SPRAY_RANGE := 2.6
## How far the spray carries, and how wide it opens, as a half-angle in degrees.
## Shorter than the range it triggers at: closing the last stride is what makes it
## land, and a man who reads the wind-up and steps back is out of it.
const SPRAY_REACH := 2.2
const SPRAY_ANGLE := 38.0
## How long it plants itself before the spray lands, and how long it stands there
## afterwards. The first number is the dodge window and the only reason this is
## fair; the second is what stops the animal spraying and bolting in one motion.
const SPRAY_WINDUP := 0.35
const SPRAY_RECOVER := 0.45
## How long before it can do it again. Long: being sprayed twice in a corner is
## not a fight, it is a tax.
const SPRAY_COOLDOWN := 7.0
## What a faceful costs. Heavier than standing on an old streak, because this one
## came looking for you.
const SPRAY_DAMAGE := 12
## How far in front of its feet the mark lands.
const SPRAY_MARK_REACH := 0.5
## The noise it makes: shorter and louder than a streak's, because this one is
## under pressure.
const SPRAY_SOUND_TIME := 0.3
const SPRAY_SOUND_LOUDNESS := 95.0
## Time pushing against a corner before shaking sideways.
const STUCK_TIME := 0.6
## Duration of the sidestep that unwedges the rat from the corner.
const DODGE_TIME := 0.4
## How long the carcass stays on the ground before vanishing.
const CARCASS_TIME := 1.4
## Height at which the rat is sent back to where it was born.
const MIN_HEIGHT := -20.0
## Scale of the model while the rat crouches in its hideout.
const CROUCH_SCALE := Vector3(1.1, 0.6, 1.0)
const INVALID_POINT := Vector3.INF

# --- Capture measurements --------------------------------------------------
## The pounce: the instant it hunches on the ground, before being torn off. It is
## short on purpose — it is only the anticipation that makes the following pull
## read as a pull.
const POUNCE_TIME := 0.1
## How long the rise from the ground to the hand takes.
const RISE_TIME := 0.35
## Height of the arc of the rise over the straight ground-to-hand line: without
## it the rat *slides* into the hand instead of being torn off.
const ARC_HEIGHT := 0.55
## The somersault it turns in the air while rising, unwinding as it arrives.
const FLIP_SPIN := PI
## How the rat sits in the hand: upright, nearly vertical, with its belly and
## snout turned towards the player — the head tips a little forward, and the
## body sits crooked sideways so it is not flat-on to the camera. Its tail and
## hind legs hang below it.
const HELD_POSE := Vector3(66.0, 200.0, 0.0)
## How big the animal is drawn in *somebody else's* hands.
##
## A man carrying a rat is drawn holding it in front of his chest, and at its own
## size the animal is a good deal of him: it reads as a rat the size of a dog and
## it hides the arms that are supposed to be doing the work. A little smaller and
## the pose comes back.
##
## It is a scale on the *whole* node and not on `model`, which is already spoken
## for by the squeeze and the crouch: those stay written against one, and this
## multiplies them.
##
## **It is not applied to the rat in our own hands**, and that is the point of
## `_held_scale` rather than an oversight. The first-person grip is a pose solved
## against this animal at this size — where the fist sits, how much of the body
## it covers, how much of it comes through the glove
## (`player_view_model.gd: grip_offset`) — and shrinking the rat
## inside it takes the hand off the animal without moving the hand at all: the
## glove went from covering an eighth of the rat to covering a fortieth, which is
## a fist beside a rat rather than round one. The two views are two pictures with
## two solutions, and this is the one for the picture taken from outside.
const HELD_SCALE := Vector3(0.85, 0.85, 0.85)
## How big the animal is drawn in *our own* hands.
##
## It exists because the animal was brought in front of the gloves rather than
## left behind them: `Hands.hands_distance` came in from 0.48 metres to 0.26,
## inside the fist at about 0.33, and perspective grows whatever comes nearer the
## lens. At its own size the rat would then fill two frames instead of two thirds
## of one. This is the distance it moved, 0.26 over 0.48, divided back out, so
## what changed is which of the two is in front and not how big either is drawn.
##
## `Hands.hands_height` came in by the same fraction, and for the same reason:
## what has to hold still is the picture, not the metres.
const FIRST_PERSON_SCALE := Vector3(0.54, 0.54, 0.54)
## The line drawn round it while somebody has it in his sights (`highlight`).
##
## Shared by every rat rather than duplicated per animal: nothing about it is
## per-rat — the pulse runs off `TIME` in the shader — so six rats lighting up
## and going dark again cost one material between them.
const OUTLINE_MATERIAL: ShaderMaterial = preload("res://materials/rat_outline.tres")
## How it sits in the last moments, crushed rather than held: the body tips
## forward and slumps sideways with nothing holding the head up. It is what a
## watcher sees of a kill happening in somebody else's hands, where the crush
## itself is drawn on the holder's machine alone (`_process_burst`).
const LIMP_POSE := Vector3(16.0, 200.0, 28.0)
## The middle of its body, in the rat's own coordinates. The rat's origin sits on
## the ground between its feet, and the trunk (snout to hip) sits ahead of and
## above it — this point, not the origin, is what the hand puts in the middle of
## the screen. Without it the animal is hung by its feet and its body leaves the
## frame; standing, its snout came within a hand's width of the camera.
const BODY_CENTER := Vector3(0.0, 0.08, -0.05)
## Hunched on the ground, in the pounce.
const POUNCE_SCALE := Vector3(1.2, 0.7, 1.2)
## Stretched in the pull — its belly lengthens as it leaves the ground.
const STRETCHED_SCALE := Vector3(0.85, 1.3, 0.85)
## Squashed, on the frame of each squeeze. Held upright, what the camera sees
## shrink is its *length*, not the height of something walking on all fours: the
## squashing happens along the body's axis (Z) and the rest bulges sideways.
const SQUEEZED_SCALE := Vector3(1.2, 1.2, 0.78)
## How long the last squeeze lasts before the animal comes apart, in seconds.
##
## It is the anticipation, and it is the whole reason the burst reads as a burst
## rather than as a rat blinking out. In it the body is crushed in the fist — it
## squashes, it shakes, and it does not fight back — and the eye is given just
## enough time to see that something has gone wrong before it goes wrong. Cut
## this to nothing and the kill loses its punch entirely: a spray of red appears
## with no cause on screen.
##
## Short, though. Anything much longer and the player is waiting on an animation
## in the middle of what should be the fastest moment in the game.
const BURST_WINDUP := 0.16
## How far the body is crushed by the end of the windup, on top of whatever the
## squeezes already did to it. Flattened along its own length, like every squeeze
## (`SQUEEZED_SCALE`), and bulging further sideways than any single squeeze does:
## this is the one it does not survive.
const BURST_SCALE := Vector3(1.45, 1.45, 0.45)
## How hard the crushed body shakes in the last moments, in metres and degrees.
## Far more than the ordinary tremor: it is not struggling any more, it is being
## crushed.
const BURST_SHAKE := 0.02
const BURST_SHAKE_ANGLE := 14.0
## The cadence of that shake, in shakes per second.
const BURST_SHAKE_SPEED := 46.0
## How hard the burst throws the player's own view. It is the biggest shake in
## the game and it is meant to be: it is the only one that happens a hand's
## width from the lens.
const BURST_SHAKE_STRENGTH := 0.85
## How much of a burst a rat killed at a distance throws, against the one that
## goes off in the fist.
##
## Small, and a long way short of it. What happens at arm's length is the animal
## being crushed until it bursts, and what happens across the room is a trap
## breaking its back or a bat catching it — the body stays a body, and a full
## spray for one of those would read as every rat in the house being made of the
## same thing. This is the splash of a blow landing, and it is drawn for the same
## reason the burst is: a kill with nothing coming off it does not feel like a
## kill.
const HIT_SPRAY := 0.4
## Where the spray comes from, relative to the point the animal hangs from, and
## which way it is thrown: out of the fist and back towards the player, because
## the fist is between him and the rest of the room. Forwards it would spray
## away from the camera and the kill would happen off in the distance.
const BURST_BACK := 0.35
## After escaping, it stays impossible to re-grab for a while.
const IMMUNITY_TIME := 1.5
## How much of the usual work a rat already stuck on the glue is worth. Pinned,
## it has nothing to brace against and gives in in a fraction of the goes it
## takes one caught loose on the floor. It is a *fraction of the effort*, and not
## a number of squeezes, so that every weapon measuring its work in some number
## of goes can scale that number by it without knowing what glue is.
const PINNED_EFFORT := 0.35
## How far the body rocks pulling against the glue, and how fast.
const PIN_SHAKE := 0.12
const PIN_CADENCE := 8.0
## The struggle of something held with nobody squeezing. It is never zero: it
## thrashes the whole time.
const BASE_STRUGGLE := 0.35
## How much of a squeeze's struggle is left after one second.
const STRUGGLE_DAMPING := 0.08
## Offset (m) and rotation (degrees) of the constant tremor, at full struggle.
const TREMOR := 0.035
const TREMOR_ANGLE := 9.0
## Interval between one kick and the next, and its strength.
const KICK_INTERVAL := Vector2(0.6, 1.0)
const KICK_FORCE := 0.07
const KICK_FORCE_ANGLE := 22.0
## How much of the jolt is left after one second.
const JOLT_DAMPING := 0.0005
## Chance of a kick turning into a bite.
const BITE_CHANCE := 0.35
## Cadence of the run cycle while it kicks in the air.
const STRUGGLE_CADENCE := 1.8
## The lurch with which it leaps out of the hand when it gets loose.
const ESCAPE_LEAP := 2.5

## Animations that come ready from `mobs/rats/Rat_Fbx.fbx`. (It also brings a
## `Rat|Attack`, which this fearful rat never uses.)
const ANIM_IDLE := "Rat|Idle"
## The pause in which it sniffs the air — used now and then in place of the idle.
const ANIM_SNIFF := "Rat|Idle_Break"
const ANIM_RUN := "Rat|Run"
const ANIM_DEATH := "Rat|Death"
## The bite the fearful rat never uses loose on the map — but does use held in
## the hand of whoever is strangling it.
const ANIM_ATTACK := "Rat|Attack"
## Chance of picking the sniff instead of the plain idle.
const SNIFF_CHANCE := 0.3
## Speed at which the run cycle plays at its natural cadence; slower than that it
## trots, faster and its legs go flying.
const CYCLE_SPEED := 4.5
const MIN_CADENCE := 0.35
const MAX_CADENCE := 2.2
## Below this speed it counts as standing still.
const IDLE_SPEED := 0.35
## Blend time between one animation and the next.
const BLEND := 0.15
## What species a rat is when somebody drops one on the map without saying which.
const DEFAULT_SPECIES := preload("res://resources/species/common_rat.tres")

## Every breed the house can put out, in the order their index crosses the wire
## (`sync_species`). The **order is the wire format**: a breed inserted in the
## middle rather than appended would repaint every rat already in flight on a
## guest as something else, and pay for it at the wrong price.
##
## It exists because a species is a `Resource` and a resource cannot cross a
## wire. What crosses is where it sits in this list — the same trick `sync_fur`
## plays with the coats — and it has to cross at all because the price of the
## animal is read off it (`_pay_reward`), on whichever machine ends up paying.
const SPECIES: Array[RatSpecies] = [
	preload("res://resources/species/common_rat.tres"),
	preload("res://resources/species/sprayer_rat.tres"),
]

## How fast a watched rat closes on where the wire last said it was, per second.
## A rate and not a duration, so that the easing comes out the same whatever the
## frame rate at either end.
##
## Higher than the players' (`player_avatar.gd`) on purpose: a rat bolts and
## turns far more sharply than a man walks, and at twenty the body would be
## visibly wide of every corner it took.
const SMOOTHING := 28.0
## Further off than this and nothing is eased at all — that is a rat put back
## where it was born (`MIN_HEIGHT`), or a gap in the wire, and neither of them
## ran there.
const SNAP_DISTANCE := 3.0

@onready var agent: NavigationAgent3D = $Navigation
@onready var model: Node3D = $Model
@onready var animator: AnimationPlayer = $Model/Mesh/AnimationPlayer
## A deep path, because it follows the hierarchy that came from the FBX.
@onready var mesh: MeshInstance3D = $"Model/Mesh/Rat/Skeleton3D/Rat Model"
## What carries this rat to the other machines. Fetched with `get_node_or_null`
## rather than `$Sync` because a rat put together in code — the benches do — has
## no such node, and a missing synchroniser should leave a working solo rat
## rather than a broken one.
@onready var _sync: MultiplayerSynchronizer = get_node_or_null("Sync") as MultiplayerSynchronizer

var _state := State.WANDERING
var _health := 1
var _player: Node3D
var _start_position: Vector3
var _target := Vector3.ZERO
var _has_target := false
var _state_time := 0.0
var _target_time := 0.0
var _search_time := 0.0
## The map's foul spots as the rat last read them, each an (x, y, z, radius). A
## `Vector4` and not a dictionary because this is read from the hot paths and
## rebuilt on a timer: the packed form costs no allocation per spot.
var _fear_cache: Array[Vector4] = []
var _fear_time := 0.0
var _stuck_time := 0.0
var _dodge_time := 0.0
var _dodge_direction := Vector3.ZERO
var _idle_duration := 1.0
var _desired_speed := 0.0
var _previous_position := Vector3.ZERO
var _step_distance := 0.0
var _cover_query := PhysicsShapeQueryParameters3D.new()
## The hole this flight is running for, or null for a flight that is only looking
## for something to hide behind. Set by `_pick_bolt_hole` and spent by
## `_dive_into` the moment the animal arrives.
var _bolt_hole: RatHole
## What is left of the wait before it will use another hole. See `BOLT_COOLDOWN`.
var _bolt_time := 0.0
## What is left of the wait before it can spray again. See `SPRAY_COOLDOWN`.
var _spray_time := 0.0
## Whether this spray has already landed. The state runs on past the moment it
## fires — the animal stands there recovering — so the shot needs a latch of its
## own rather than a timer comparison that is true on every frame after it.
var _sprayed := false

var _capture_phase := Capture.POUNCE
var _capture_time := 0.0
var _capture_point: Node3D
## Whose catch this is, as the wire counts people, on the machine that is
## thinking for the rat. Zero when nobody is holding it.
##
## The host keeps this and puts it on the wire as `sync_holder`; solo it is the
## local peer id, which with no wire at all is 1. It is deliberately separate
## from `_capture_point`: the point is a node and says *where* the animal is
## held, this says *whose* it is, and only the second one means anything on a
## machine other than the holder's.
var _holder_peer := 0
var _original_layer := 0
## Where the rat sits in the hand, in capture-point coordinates. The whole
## gesture — trembling, being crushed — is written against this
## transform and only then carried to the world by `_follow_capture_point`.
##
## It is kept here rather than in the node's own `transform` because the rat
## never becomes a child of the hand: it stays where the `MultiplayerSpawner`
## put it, under the house's `Rats` container. A `reparent` would move the
## `Sync` node with it and make it announce a path — `.../CapturePoint/Rat_N/Sync`
## — that exists on no other machine, and every guest would answer that with
## `get_node: Node not found`.
var _held_transform := Transform3D.IDENTITY
var _rise_origin := Vector3.ZERO
var _origin_basis := Basis.IDENTITY
var _struggle := 1.0
var _jolt := Vector3.ZERO
var _jolt_spin := Vector3.ZERO
var _kick_time := 0.0
var _immune_time := 0.0

## Stuck where it stands, the glue under its feet. It is deliberately *not* one
## of the states: a pinned rat goes on being whatever it was and simply cannot
## leave the spot, and that is what lets the hand still come and take it — off
## the glue it becomes a capture like any other, with no state to unwind first.
var _pinned := false
## What is holding it down, so whatever holds it hears about the ending: killed
## where it lay, or torn off by hand. Null with nothing holding it.
var _pin: Node3D

## Whatever has a claim on the body and will not let it vanish on its own clock.
## It is the carcass's counterpart to `_pin`: the glue holds a rat that is still
## alive, and this holds what is left of one that is not. Null for every rat that
## dies loose on the floor, which is nearly all of them.
var _holder: Node3D

## What it died of, and how big it is for one of its species: the two halves of
## the price. `_paid` is the latch that keeps the reward from landing twice.
var _death_type := Death.Type.UNKNOWN
var _size := 1.0
var _paid := false
## Whose kill this was, as the wire counts people. Zero until something kills it,
## and zero for good for anything that dies with nobody to blame.
##
## Every rat is killed on the host, because that is the machine that thinks for
## it — but the man who killed it is very often sitting at another one, and the
## money has to find him. This is the thread that carries him from the blow, or
## from the hand, all the way to `_pay_reward` at the far end of the gesture.
var _killer_peer := 0

# --- What crosses the wire --------------------------------------------------
#
# A rat is the host's animal. Only the host thinks — picks where to go, decides
# it is frightened, walks the navigation mesh — and what the other machines get
# is the result of that thinking, not the thinking itself. Rats deciding for
# themselves on each machine would be a different rat on every screen: the mesh
# is the same, but the die rolls behind every destination are not.
#
# So the guest's rat is a puppet. Its `_physics_process` returns before the
# state machine (see the guard there), and these three variables — written by
# the `Sync` node twenty times a second — are the whole of what it knows. Same
# split as `player_avatar.gd`, and for the same reason.
#
# The position is *eased* rather than assigned, in `_draw_remote`. Between two
# packets the rat would otherwise stand still and then jump, which at a rat's
# speed reads as a stutter rather than as an animal running.

## Where the host says the body is.
var sync_position := Vector3.ZERO
## Which way it faces. The yaw alone — a rat never leaves the floor.
var sync_yaw := 0.0
## How fast it is going along the ground, in metres per second. The animation is
## picked from this and not from the state, exactly as it is on the host
## (`_update_animation`): what plays follows the speed.
var sync_speed := 0.0
## Its `State`. Only the two ends matter to a watcher — DEAD topples it, CAPTURED
## takes it out of the guest's hands entirely — but the whole value crosses
## because it costs nothing and reads plainly in the debugger.
var sync_state := State.WANDERING
## Which fur it was born with, as an index into the species' `furs`. It is rolled
## on the host and crosses on the spawn so that a rat is the same animal on every
## screen. `-1` is a rat whose species has no furs to roll.
var sync_fur := -1
## What breed it is, as an index into `SPECIES`. Decided by the house that put it
## out (`house.gd::_spawn_rats_if_needed`) and crossed on the spawn, because the
## breed is what the animal is *worth* — and the man who gets paid for it is very
## often sitting at a machine that never rolled it.
##
## It is applied before the coat is (`_on_synchronized`): the fur index counts
## into the species' own list of furs, so a rat painted before its breed is known
## is a rat painted out of the wrong book.
var sync_species := 0
## The hideout crouch, which is a scale on the model and not a position: a rat
## squeezed under a crate on the host should be squeezed under it everywhere.
var sync_crouched := false
## Whose hand this rat is in, as the wire counts people. Zero is a rat nobody is
## holding, which is nearly all of them nearly all the time.
##
## It is what makes a catch mean the same thing on every machine. The host thinks
## for every rat, so a guest's catch is *carried out* on the host — but the man
## it belongs to is sitting somewhere else, and without this the other machines
## would see a rat hanging in mid-air beside him. With it, everybody knows whose
## catch it is: the holder's own machine draws it against his camera, filling his
## frame, and everybody else draws it in front of that man's body
## (`_draw_remote_capture`).
##
## It is also who gets paid. `_pay_reward` reads it, which is the whole reason
## the money lands in the right wallet rather than always in the host's.
var sync_holder := 0

## A packet has landed: this body knows where it stands. Until then it is not
## drawn at all — a rat that is up but has never been told where it is would sit
## at the origin, which is a lie the moment somebody looks at it.
var _seen := false

## A watched rat is in somebody's hand, as far as this machine is concerned. It
## is what tells the first frame of a catch from every frame after it, for a rat
## held by somebody else — where there is no change of parent to notice.
var _held_remotely := false

## A watched rat has died in the hand and should stop fighting. It is a latch and
## not a reading of `sync_state`, because the rat is freed on the host at the end
## of the burst and the last packets before that are the ones that matter: once
## it has gone limp on this screen it does not start thrashing again.
var _remote_limp := false

func _ready() -> void:
	add_to_group("rats")
	# `_process` belongs to the capture alone; loose on the map the rat lives in
	# physics.
	set_process(false)
	if species == null:
		species = DEFAULT_SPECIES
	_size = species.roll_size()
	_health = max_health
	_prepare_cover_query()
	_start_position = global_position
	_previous_position = global_position
	# Spreads the rats' decisions across different frames.
	_search_time = randf() * SEARCH_INTERVAL
	_fear_time = randf() * FEAR_REFRESH
	_fear_cache = _fear_spots()
	_play_idle()
	# Each rat enters the animation at a different point of the cycle, otherwise
	# all ten breathe in the same rhythm.
	animator.seek(randf() * animator.current_animation_length, true)

	# Somebody else's rat: it does not think, it is drawn. Physics goes off — the
	# state machine, the navigation and the gravity all live there — and `_process`
	# comes on to ease the body towards whatever the last packet said. Note the
	# two are swapped compared with the host, which runs physics and leaves
	# `_process` for the capture alone.
	#
	# Solo this is never taken: with no wire at all every node is its own
	# authority, so a lone player's rats think exactly as they always did.
	if not _is_authority():
		_become_puppet()
		return

	# Ours to think for, which is the host's rat and every rat in a solo game.
	_size = species.roll_size()
	# The breed is already on the node — the house wrote it before adding the
	# animal — and what is worked out here is only where it sits in `SPECIES`, so
	# that the guests can be told which one it is.
	sync_species = maxi(0, SPECIES.find(species))
	sync_fur = _roll_fur_index()
	_apply_fur(sync_fur)
	# It may be too early: the freshly baked mesh has not answered the server's
	# first sync yet. In that case it stays without a destination and the wander
	# tries again on the next frame.
	_pick_wander_target()
	_publish()

## Somebody else's rat, on our machine: a body with no opinions. Everything that
## decides is switched off here, in one place, so that what a guest's rat does
## and does not do is one block to read rather than a guard in every method.
func _become_puppet() -> void:
	set_physics_process(false)
	set_process(true)
	# Not drawn until the wire says where it is — see `_seen`.
	visible = false
	if _sync != null:
		_sync.synchronized.connect(_on_synchronized)

func _physics_process(delta: float) -> void:
	# A guest's rat has physics switched off entirely (`_become_puppet`), so this
	# never runs there. The guard is kept anyway because authority can change
	# under a node that is already up, and a rat that started thinking for itself
	# on two machines at once is a bug that shows as a rat in two places.
	if not _is_authority():
		return

	_immune_time = maxf(0.0, _immune_time - delta)

	if _state == State.DEAD:
		_apply_gravity(delta)
		move_and_slide()
		_publish()
		return

	# In the player's hand it leaves physics entirely: what rules its body now is
	# `_process`, which runs on the screen's beat and not on the 60 Hz one — held
	# against the camera, any mismatch between the two shows up as jitter.
	if _state == State.CAPTURED:
		return

	# Stuck on the glue it neither runs nor decides anything: it stays where it
	# was caught, pulling against its own feet. This comes before the fear
	# machine on purpose — there is no sense reassessing a flight it cannot
	# start, and a rat that spent the whole time trying to flee would be a rat
	# wearing its running animation standing still.
	if _pinned:
		_struggle_in_place(delta)
		_apply_gravity(delta)
		move_and_slide()
		_publish()
		return

	_state_time += delta
	_bolt_time = maxf(0.0, _bolt_time - delta)
	_spray_time = maxf(0.0, _spray_time - delta)
	# The map's bad ground, re-read on its own slow clock. Everything below —
	# the state it talks itself into, the hideout it picks, the way it walks
	# there — reads the list this leaves behind.
	_fear_time -= delta
	if _fear_time <= 0.0:
		_fear_time = FEAR_REFRESH
		_fear_cache = _fear_spots()
	_reassess_state()

	match _state:
		State.WANDERING:
			_process_wander(delta)
		State.IDLE:
			_process_idle(delta)
		State.FLEEING:
			_process_flee(delta)
		State.HIDING:
			_process_hide(delta)
		State.SPRAYING:
			_process_spray(delta)

	_apply_gravity(delta)
	move_and_slide()
	_update_steps()
	_update_animation()
	_check_stuck(delta)

	if global_position.y < MIN_HEIGHT:
		global_position = _start_position
		velocity = Vector3.ZERO

	_publish()

## Two jobs, told apart by who owns the rat.
##
## On the host — and solo, where every rat is ours — it belongs to the capture
## alone and is off the rest of the time (see `set_process` in `_ready`): held
## against the camera, the body has to run on the screen's beat rather than the
## 60 Hz one or the mismatch shows up as jitter.
##
## On a guest it is the only thing running at all, and what it does is draw the
## animal the host is thinking for.
func _process(delta: float) -> void:
	if not _is_authority():
		_draw_remote(delta)
		return

	_capture_time += delta
	_follow_holder()
	match _capture_phase:
		Capture.POUNCE:
			_process_pounce(delta)
		Capture.RISING:
			_process_rise(delta)
		Capture.IN_HAND:
			_process_in_hand(delta)
		Capture.BURSTING:
			_process_burst(delta)

	# The capture is the one gesture physics never touches, so it is also the one
	# frame `_physics_process` never reports (it returns early on `CAPTURED`).
	# Publishing here is what puts the rat in the host's hands on everybody
	# else's screen instead of leaving it standing on the floor where it was
	# grabbed. `queue_free` at the end of the burst can land inside the match
	# above, hence the guard.
	if is_inside_tree():
		_publish()

## Takes a hit. With `max_health` 1 (the default) any hit kills. `type` is what
## death the weapon kills with, and it is what decides how much the body pays.
## `leap` is the little hop the body makes as it goes: whatever kills a rat at
## arm's length lets it jump, and whatever comes down on top of it does not.
func take_damage(amount: int = 1, origin: Vector3 = INVALID_POINT,
		type := Death.Type.UNKNOWN, leap := 3.0) -> void:
	if _state == State.DEAD or _state == State.CAPTURED:
		return
	# Only the machine that thinks for this rat may kill it — otherwise a guest
	# would drop it on his own screen alone while on every other machine the same
	# animal went on running, and would pay his own wallet for a rat nobody else
	# saw die.
	#
	# So the hit crosses instead of landing here, and the host lands it. The
	# knockback, the flight, the death and the money all follow from that one
	# decision made in one place, and the guest sees the result come back like
	# any other thing the rat does.
	if not _is_authority():
		_request_damage.rpc_id(get_multiplayer_authority(), amount, origin, type, leap)
		return
	_health -= amount
	if _health <= 0:
		_die(origin, leap, type, _local_peer())
		return
	_change_state(State.FLEEING)
	if origin != INVALID_POINT:
		velocity += _away_from(origin) * knockback_force

## A guest hit this rat. Runs on the host, which is the machine that decides
## whether it dies of it and who is paid if it does.
##
## Everything the blow was crosses, because none of it can be worked out here:
## `origin` is where the weapon swung from and it is what the body is knocked
## away from, `type` is what the weapon kills with and it is what the carcass is
## worth, and `leap` is the hop it makes on the way down. They come from the
## guest's weapon and there is no copy of that weapon on this machine to ask.
##
## The sender is not checked against anything, and that is right: anybody in the
## house may hit any rat, which is the game. What is checked is the state of the
## animal, and that is checked in `_apply_damage` — the same road the host's own
## swing takes.
@rpc("any_peer", "reliable")
func _request_damage(amount: int, origin: Vector3, type: Death.Type, leap: float) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		return
	if _state == State.DEAD or _state == State.CAPTURED:
		return
	_health -= amount
	if _health <= 0:
		_die(origin, leap, type, peer_id)
		return
	_change_state(State.FLEEING)
	if origin != INVALID_POINT:
		velocity += _away_from(origin) * knockback_force

## True as soon as its health runs out, even in the moments when the body is
## still in the player's hand — going limp or dropping to the waist.
func is_dead() -> bool:
	if not _is_authority():
		return sync_state == State.DEAD
	if _state == State.CAPTURED:
		return _capture_phase == Capture.BURSTING
	return _state == State.DEAD

## Whether this rat's account is closed: the money has been paid and the shift
## is finished with it. A rat killed at a distance pays where it falls, so it is
## true the instant it dies; one strangled in the hand pays at the end of the
## gesture, so it is false for as long as the body is still travelling to the
## waist. The house reads it to know whether the hunt is really over
## (`house.gd::pending_rat_count`).
func is_paid() -> bool:
	return _paid

## In somebody's hand — anybody's. It is what keeps a rat already caught out of
## everybody else's sights (`weapon.gd: _rat_in_sights`), and on a machine that
## is only watching, the wire is the only thing that knows.
func is_captured() -> bool:
	if not _is_authority():
		return sync_state == State.CAPTURED
	return _state == State.CAPTURED

## True only once it has finished rising and is settled in the hand.
##
## The phases of the rise do not cross the wire — they are a gesture, and the
## whole of it takes a fraction of a second — so a watcher answers for the state
## it can see. What asks is the escape clock (`hands.gd`), and the difference it
## makes there is a hair of extra grace on a grab whose rise the holder never
## sees anyway.
func is_in_hand() -> bool:
	if not _is_authority():
		return sync_state == State.CAPTURED
	return _state == State.CAPTURED and _capture_phase == Capture.IN_HAND

## Whether *this* machine's player is the one holding it.
##
## It is the question a guest's hands ask to find out whether the grab they sent
## off actually landed (`hands.gd: _forget_lost_rat`), and the one this rat
## answers from `sync_holder` — the holder as the machine that thinks for the
## animal sees it, which is the only reading that counts.
##
## On the host and in a solo hunt it is answered from `_holder_peer` directly,
## which is the same number a frame earlier.
func is_held_by_me() -> bool:
	var holder := _holder_peer if _is_authority() else sync_holder
	return holder != 0 and holder == _local_peer()

## Who is holding it, as the wire counts people, or zero for a rat nobody has.
func holder_peer() -> int:
	return _holder_peer if _is_authority() else sync_holder

## Where the middle of its body is in the world: the point the hand holds and
## the one the capture carries to the middle of the screen.
func body_center() -> Vector3:
	return global_position + global_basis * BODY_CENTER

## Draw the outline around it, or take it off again.
##
## It is the rat's own look and so it lives here, but *whether* it is lit is not
## the rat's business at all: it is whether somebody has it in his sights, which
## only the weapon holding the sights knows (`player.gd: _update_target`).
##
## It goes on the overlay slot rather than the override, and that is the whole
## reason this works: the animal's surfaces already carry the PS1 material
## (`scripts/ps1_material_applier.gd`), and an override here would take the
## animal's own skin off to put a line round it.
##
## Purely local. Nothing about it crosses the wire and nothing should — it is one
## player's aim, drawn on his own screen, and a rat lit up on everybody's would
## be showing the whole crew where one man happens to be pointing.
func highlight(on: bool) -> void:
	if mesh == null or not is_instance_valid(mesh):
		return
	mesh.material_overlay = OUTLINE_MATERIAL if on else null

# --- Stuck -----------------------------------------------------------------
#
# A rat that steps on the glue stops where it is. It does not die of it: it stays
# there pulling against its own feet until somebody comes to finish it — and
# whoever comes may finish it however he likes.
#
# That is the whole trade the glue offers against the mousetrap. The trap works
# while the player is somewhere else and hands back a mangled animal
# (`Death.Type.TRAP`); the glue does only half the job and hands back a rat that
# cannot run, to be strangled whole at full price, or brained with whatever the
# van sells next. The glue has no opinion on how it ends — it only holds.
#
# Being stuck is not one of the rat's states, and that is the point: it is
# something that happens *to* a rat that goes on being whatever it was. Nothing
# in the state machine knows about it, `take_damage` needs no exception for it,
# and the hand can still take the animal off it without any state to unwind.

## Stuck in place. `holder` is whatever is holding it down, and gets told through
## `released()` when the rat dies or is torn off it.
func pin(holder: Node3D = null) -> void:
	if _state == State.DEAD or _state == State.CAPTURED or _pinned:
		return
	_pinned = true
	_pin = holder
	# It stops where it was caught, and whatever it was in the middle of — a path
	# to a hideout, a crouch behind a crate — is over.
	_clear_target()
	velocity = Vector3.ZERO
	model.scale = Vector3.ONE
	animator.speed_scale = 1.0
	_play_idle()

## Release on death, pickup, timed escape or glue expiration.
## Notify the holder once so its capacity can be reused.
func unpin() -> void:
	if not _pinned:
		return
	_pinned = false
	var holder := _pin
	_pin = null
	model.rotation.z = 0.0
	if holder != null and is_instance_valid(holder) and holder.has_method("released"):
		holder.released(self)

## Stuck in place and unable to leave. It is what a weapon asks before deciding
## how much work the animal is going to be.
func is_pinned() -> bool:
	return _pinned

func glue_escape_time() -> float:
	return species.glue_escape_seconds if species != null else 0.0

func is_pinned_by(holder: Node3D) -> bool:
	return _pinned and _pin == holder

## How much of a weapon's usual effort this rat is worth, from 0 to 1. A rat that
## cannot get away was already beaten when it was picked up; one caught loose
## costs the whole job. Every weapon that measures its work in *some number of
## goes* scales that number by this, and none of them has to know what glue is.
func effort() -> float:
	return PINNED_EFFORT if _pinned else 1.0

## The thrashing of something stuck: it pulls against the glue without ever
## leaving the spot. The body rocks side to side and the legs stay still — a rat
## wearing its run cycle going nowhere would read as a bug, not as a struggle.
func _struggle_in_place(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var urgency := 1.0
	if is_instance_valid(_pin) and _pin.has_method("escape_urgency"):
		urgency += _pin.escape_urgency(self)
	model.rotation.z = sin(_state_time * PIN_CADENCE * urgency) * PIN_SHAKE * urgency
	model.scale = model.scale.lerp(Vector3.ONE, minf(delta * 6.0, 1.0))
	_state_time += delta
	_play_idle()

# --- Carcass ---------------------------------------------------------------
#
# The other half of being held. `pin` above holds a rat that is still alive and
# lets go of it the moment it stops being one; this holds what is left after,
# and it is what keeps a body lying in the thing that killed it instead of
# shrinking politely away on its own clock.

## Somebody has a claim on this body before it is even a body. Whatever kills the
## rat from here on, what is left of it stays where it fell until `holder` says
## otherwise.
##
## It is asked for *before* the blow and never after: by the time the blow has
## landed `_die()` has already started the vanishing, and a body on its way out
## is a body nobody can call back.
func claim_carcass(holder: Node3D) -> void:
	# A rat in somebody's hand is already spoken for, and the hand leaves no
	# carcass to hold on to.
	if _state == State.CAPTURED:
		return
	_holder = holder

## True while something out in the world is still holding on to this body.
func is_held() -> bool:
	return _holder != null and is_instance_valid(_holder)

## Whoever was holding the body has finished with it — the trap it was lying in
## has been cleaned out. It goes the way every other carcass goes, on the clock
## it should have had all along.
func release_carcass() -> void:
	if _holder == null:
		return
	_holder = null
	_vanish()

# --- Capture ---------------------------------------------------------------
#
# The player grabs the rat, it is torn off the ground in an arc towards `point` —
# a node in the middle of the screen, child of the player's head — and from the
# moment it arrives it becomes a child of that node. Being a child is what keeps
# it *glued* to the middle of the screen no matter how fast the player swings the
# camera: there is no transform being chased frame by frame, it simply comes
# along.
#
# Strangled, it never goes back to the ground: it goes limp in the hand and drops
# to the fist, where it comes apart. A carcass on the ground belongs to a rat
# killed from a distance — whatever dies in the player's hand leaves nothing but
# the blood it was thrown as.

## The player grabbed this rat. Returns false when it cannot be done: dead,
## already in someone's hand or freshly escaped.
##
## `point` is where *this* machine wants to hold it — the node in the middle of
## its own screen. It matters only on the machine of whoever is holding it; the
## host anchors a guest's catch to that guest's avatar instead, and everybody
## else draws it from the wire.
##
## Called by the weapon on the machine of the man doing the grabbing, whoever he
## is. On the host that is the whole of it. On a guest it asks the host, which is
## the machine that thinks for the animal, and answers **provisionally**: the
## grab is a request, and the guest finds out it succeeded when the rat comes
## back over the wire as his (`sync_holder`). See `_hold` for why answering
## optimistically is the right way round here.
func capture(point: Node3D) -> bool:
	if not _grabbable():
		return false

	# Not ours to decide. The request goes to the host, who runs the very same
	# `capture` there, anchors the animal to this player's avatar and puts the
	# answer on the wire.
	#
	# It answers true without waiting, and that is deliberate: the wait is a
	# round trip, and a hand that goes limp for a fifth of a second on every grab
	# feels broken in a way that a hand which occasionally grabs nothing does
	# not. The rat itself is not moved here — nothing is a fact until the host
	# says so — so the worst an optimistic answer costs is a weapon that thinks
	# it is holding something for one round trip and then finds it is not
	# (`hands.gd: _forget_lost_rat`).
	if not _is_authority():
		_request_capture.rpc_id(get_multiplayer_authority())
		return true

	return _hold(_local_peer(), point)

## Whether this rat can be picked up at all, asked before anybody has committed
## to anything. It is the one rule that is the same on every machine, which is
## why it is checked on the guest before the request goes out as well as on the
## host when it lands: a guest need not trouble the wire to be told that the rat
## he is looking at is already dead.
func _grabbable() -> bool:
	# A puppet has to be asked through the wire and not through itself. Its own
	# `_state` is whatever it was when its physics was switched off — usually
	# `WANDERING`, and stuck there for good — so a rat the host killed a minute
	# ago would still call itself grabbable and every guest in the house would be
	# able to reach for a corpse.
	if not _is_authority():
		return sync_state != State.DEAD and sync_state != State.CAPTURED
	return _state != State.DEAD and _state != State.CAPTURED and _immune_time <= 0.0

## A guest wants this rat. Runs on the host, which is the only machine that may
## say yes.
##
## `any_peer` because anybody in the house may try to grab a rat — that is the
## game — and there is nothing to trust in the message: it carries no state, only
## the wish. Whether it is allowed is decided here, by the same `_hold` the host
## puts his own hand through, and the sender does not get a vote.
@rpc("any_peer", "reliable")
func _request_capture() -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		return
	# Where the animal is held, on this machine, for a man sitting at another
	# one: in front of his avatar's chest. His own machine will draw it against
	# his camera instead — the two are different views of one catch, and
	# `sync_holder` is what tells each machine which of them it is looking at.
	#
	# A grab is never dropped for want of a body to hang it on. A guest whose
	# avatar has not gone up here yet — the first seconds of a hunt, a peer this
	# machine has heard from before it has drawn him — has still *caught the
	# rat*, and refusing it would be a grab that vanished for a reason nobody
	# could see. `_hold` falls back to holding the animal where it stands, and
	# `_follow_holder` moves it onto the man the moment he is drawn.
	_hold(peer_id, _capture_point_of(peer_id))

## The catch itself, on the machine that thinks for the rat. Everything that
## makes a grab real happens here and nowhere else, whoever asked for it: the
## host through `capture`, a guest through `_request_capture`.
func _hold(peer_id: int, point: Node3D) -> bool:
	if not _grabbable():
		return false

	# Torn off whatever was holding it down. It happens before anything else so
	# that from here on this is an ordinary capture with nothing left stuck to
	# it — and whoever wants to know how beaten the animal already was has to ask
	# before the grab, not after (`scripts/weapons/hands.gd`).
	unpin()

	_state = State.CAPTURED
	_capture_phase = Capture.POUNCE
	_capture_time = 0.0
	_capture_point = point
	_holder_peer = peer_id
	_original_layer = collision_layer
	_struggle = 1.0
	_jolt = Vector3.ZERO
	_jolt_spin = Vector3.ZERO
	_kick_time = randf_range(KICK_INTERVAL.x, KICK_INTERVAL.y)

	_clear_target()
	velocity = Vector3.ZERO
	# It leaves every layer so it neither pushes the player nor gets in the way
	# of the other rats' lines of sight while it hangs in the air. The mask stays
	# intact: it is what makes the carcass find the ground if it gets dropped.
	set_deferred("collision_layer", 0)
	# It stays in the `rats` group: for the HUD scoreboard it is still alive, and
	# rightly so — the player can still lose it.
	set_process(true)
	# The holder crosses on the next packet like everything else, but the state
	# is written now so that a rat grabbed and killed inside one frame is never
	# on the wire as a rat nobody is holding.
	_publish()
	return true

## Where a given peer holds a rat, on *this* machine.
##
## Our own hand is the point in the middle of our own screen, which is a child of
## our character's head (`player.tscn`). Everybody else's is the chest of the
## body standing for him (`player_avatar.tscn`), because his character does not
## exist here — the host has no `Player` node for a guest, only an avatar, and a
## catch has to hang off something that is actually in this tree.
func _capture_point_of(peer_id: int) -> Node3D:
	if peer_id == _local_peer():
		var local := get_tree().get_first_node_in_group("player") as Node3D
		if local == null:
			return null
		return local.get_node_or_null("Head/CapturePoint") as Node3D
	for node in get_tree().get_nodes_in_group("player_avatars"):
		var avatar := node as PlayerAvatar
		if avatar != null and avatar.peer_id == peer_id:
			return avatar.capture_point
	return null

## Whether this machine is the one that thinks for this rat.
##
## `is_multiplayer_authority` cannot answer with no wire under it: it asks the
## scene multiplayer for our own id, and a peer that was never dialled — or one
## that closed when the last client left — logs an error for the question. A
## solo hunt has one machine and it decides everything, so the answer there is
## yes without asking anybody.
func _is_authority() -> bool:
	var api := multiplayer
	if api == null or not api.has_multiplayer_peer() \
			or api.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	return is_multiplayer_authority()

## Whether there is anybody to say anything to. An `rpc` with no wire under it is
## an error in the log for a call that would have run here anyway — the same
## question `trap.gd` and the session autoloads ask before their own
## announcements.
func _on_the_wire() -> bool:
	var api := multiplayer
	if api == null or not api.has_multiplayer_peer():
		return false
	return not api.multiplayer_peer is OfflineMultiplayerPeer

## Who we are, as the wire counts people. One with no wire at all: a solo hunt
## has a single pair of hands and they may as well be numbered like the host's,
## so that nothing below has to ask whether there is a wire before reading a
## holder.
func _local_peer() -> int:
	# A wire that is not up — never dialled, or closed under us at the end of a
	# hunt — has no id to give and complains if it is asked. Everything that
	# reads a holder wants a number either way, and one is the right one: with no
	# peers there is a single pair of hands in the game and they may as well be
	# numbered like the host's.
	var api := multiplayer
	if api == null or api.multiplayer_peer == null \
			or api.multiplayer_peer is OfflineMultiplayerPeer \
			or api.multiplayer_peer.get_connection_status() \
				!= MultiplayerPeer.CONNECTION_CONNECTED:
		return 1
	var id := api.get_unique_id()
	return 1 if id == 0 else id

## One squeeze of the neck. Counting the squeezes and deciding when it dies is
## the weapon's job; here the rat only reacts.
##
## It is the holder's hand doing the squeezing, so on his machine it is applied
## at once — the flinch belongs on the frame he clicked, not a round trip later —
## and passed to the host, which is where the body it flinches with actually
## lives. Everybody else sees it as the animal jolting in that man's hands.
func squeeze() -> void:
	if not is_captured():
		return
	_flinch()
	if not _is_authority():
		_request_squeeze.rpc_id(get_multiplayer_authority())

## The flinch itself: what a squeeze looks like, with nothing said about who
## asked for it. Kept apart from `squeeze` so that the holder can play it on his
## own screen and the host can play it on the real body without either of them
## going round the loop twice.
func _flinch() -> void:
	_struggle = 1.0
	model.scale = SQUEEZED_SCALE
	_kick(0.6)

## A guest squeezed the rat he is holding. Runs on the host.
##
## Only the man actually holding it is listened to. Anybody may *ask* — it is
## `any_peer`, like every message a guest sends — and the check is here rather
## than in the sender, which is where a check has to be when the sender is
## somebody else's machine.
@rpc("any_peer", "reliable")
func _request_squeeze() -> void:
	if multiplayer.get_remote_sender_id() != _holder_peer:
		return
	if _state != State.CAPTURED:
		return
	_flinch()

## Died in the hand: the fist closes past what the animal can take and it comes
## apart. `type` comes from the weapon that killed it — today only the hands get
## here, strangling.
func die_in_hands(type := Death.Type.STRANGULATION) -> void:
	# `is_captured` and not `_state`, and that is the whole of what a puppet
	# needs: its own `_state` was frozen at whatever it held when its physics was
	# switched off, so a guest asking his own copy whether it is in his hand is
	# asking a variable that has not been written since the rat was born. What
	# knows is the wire.
	if not is_captured() or is_dead():
		return
	# The killing blow is the host's to land, whoever threw it. A guest that
	# strangled its rat says so and stops there: the body is crushed, burst and
	# paid for on the host, and comes back over the wire as a rat that is dead. Doing it here as well would kill the animal twice — once really, once
	# on a puppet — and pay for it twice with it.
	if not _is_authority():
		_request_kill.rpc_id(get_multiplayer_authority(), type)
		return
	# Whoever hammered too fast can kill it before it has finished rising. In
	# that case it reaches the hand in one go and goes limp from there — without
	# this the body would go limp in hand coordinates while still hanging in the
	# world.
	if _capture_phase != Capture.IN_HAND:
		_snap_to_hand()
	_capture_phase = Capture.BURSTING
	_capture_time = 0.0
	_struggle = 0.0
	animator.speed_scale = 1.0
	animator.play(ANIM_DEATH, BLEND)
	# The rattle of a thing being crushed, under the death sound. Networked
	# rather than local: the burst is a loud, wet thing that happens in one
	# man's hands, and everybody in the house should hear it happen.
	AudioManager.play_networked_3d("rat_death", global_position, -2.0,
		randf_range(0.94, 1.06), self)
	_record_death(type)
	# The money lands here rather than at the end of the gesture, and that is the
	# burst's doing. It used to be paid at the player's waist, because the body
	# had a journey to make and losing it on the way was possible — a man who
	# killed a rat and then dropped off the wire had earned nothing. There is no
	# journey any more: the animal comes apart in the fist and is gone, so the
	# moment it dies and the moment its account closes are the same moment.
	_pay_reward()

## Got loose from the player's hand and bolts.
func escape() -> void:
	# Read through `is_captured` for the same reason as `die_in_hands`: on a
	# guest the only honest answer comes from the wire.
	if not is_captured():
		return
	# Same rule as the kill: the animal gets loose on the machine that thinks for
	# it, and everybody watches it happen. A guest whose grip failed says so and
	# lets go of it locally through the wire, not by hand.
	if not _is_authority():
		_request_escape.rpc_id(get_multiplayer_authority())
		return
	# It leaps out in front of the player. The direction comes from his body, not
	# from the rat's position: hanging in his hand the rat is *on top of* him,
	# and the usual "away from him" would have nowhere to point.
	var player := _get_player()
	var flight := -player.global_basis.z if player != null else -global_basis.z
	flight.y = 0.0
	flight = Vector3.FORWARD if flight.is_zero_approx() else flight.normalized()
	_return_to_world()
	_immune_time = IMMUNITY_TIME
	# `_change_state` only works coming from another state, and the flight has to
	# start from scratch for the rat to pick up `burst_speed`.
	_state = State.WANDERING
	_change_state(State.FLEEING)
	velocity = flight * flee_speed + Vector3.UP * ESCAPE_LEAP

## A guest strangled the rat in his hands. Runs on the host.
##
## The death type crosses because the weapon decides it, and the weapon is on his
## machine — the hands strangle, and the day something else kills in the hand it
## will say so here. It is still checked against the holder: a peer who is not
## holding this rat has no say in how it dies.
@rpc("any_peer", "reliable")
func _request_kill(type: Death.Type) -> void:
	if multiplayer.get_remote_sender_id() != _holder_peer:
		return
	die_in_hands(type)

## A guest lost his grip. Runs on the host.
@rpc("any_peer", "reliable")
func _request_escape() -> void:
	if multiplayer.get_remote_sender_id() != _holder_peer:
		return
	escape()

## Takes the rat out of the hand and gives it back to the tree and the physics it
## came from.
func _return_to_world() -> void:
	set_process(false)
	# Nothing to put back: the rat never left its own branch of the tree, only
	# the hand's coordinates. It is already standing where it was last drawn.
	# Straightens the body: it goes back to the ground on its feet, not upside
	# down. And back to its own size: `HELD_SCALE` is baked into the node while
	# it hangs in a hand, and setting `rotation` keeps whatever scale is there —
	# without this the rat that got loose would run off small for the rest of the
	# hunt.
	rotation = Vector3(0.0, rotation.y, 0.0)
	scale = Vector3.ONE
	set_deferred("collision_layer", _original_layer)
	_capture_point = null
	# Nobody's any more. It matters on the wire as much as here: a rat back on
	# the floor still carrying a holder would be drawn hanging in front of the
	# man who lost it (`_draw_remote_capture`).
	_holder_peer = 0

## Keeps the catch on the man it belongs to, on the machine thinking for the rat.
##
## There are two ways the hand under a rat can change while it is being held, and
## neither of them is the ordinary case:
##
## - It was never there. A guest grabbed a rat before this machine had drawn his
##   body, so the catch was allowed with nowhere to hang it (`_request_capture`).
##   The moment the avatar goes up, the animal moves onto it.
## - It went away. The man dropped off the wire with a rat in his hands, and his
##   body went with him. The rat is let go rather than carried by a ghost — it is
##   the same thing that happens when somebody loses his grip, and from the
##   animal's point of view it is exactly that.
##
## It costs one dictionary-free group walk per held rat per frame, and there is
## at most one rat per player in the game.
func _follow_holder() -> void:
	if _holder_peer == 0:
		return
	var point := _capture_point_of(_holder_peer)
	if point == _capture_point:
		return
	if point == null:
		# His body has gone. Whatever he was holding is loose again.
		escape()
		return
	_capture_point = point
	# Already in a hand: it moves across to the new one rather than starting the
	# rise over, which from a watcher's side is the rat simply being where the
	# man is.
	if _capture_phase == Capture.IN_HAND or _capture_phase == Capture.BURSTING:
		_snap_to_hand()

## The pounce: it hunches on the ground and the hand comes down on it.
func _process_pounce(delta: float) -> void:
	model.scale = model.scale.lerp(POUNCE_SCALE, minf(delta * 22.0, 1.0))
	if _capture_time < POUNCE_TIME:
		return
	_capture_phase = Capture.RISING
	_capture_time = 0.0
	_rise_origin = global_position
	_origin_basis = global_basis.orthonormalized()
	animator.speed_scale = STRUGGLE_CADENCE
	animator.play(ANIM_RUN, BLEND)

## The pull: from the ground to the hand, in an arc and somersaulting.
func _process_rise(_delta: float) -> void:
	# Nowhere to rise to yet: the hand this catch belongs to is not in this tree.
	# It hunches where it is until `_follow_holder` finds the body, which is a
	# frame or two at worst and reads as an animal held down rather than one
	# frozen mid-air.
	if _capture_point == null:
		return
	var t := clampf(_capture_time / RISE_TIME, 0.0, 1.0)
	# It leaves the ground fast and slows down as it reaches the hand — that is
	# what gives the pull.
	var progress := 1.0 - pow(1.0 - t, 3.0)

	var pose := _capture_point.global_basis.orthonormalized() * Basis.from_euler(_radians(HELD_POSE))

	# The destination is read every frame: if the player walks or turns while the
	# rat is rising, the rat corrects its course in the air. The origin is not:
	# it stays where the rat was, in the world, otherwise it would rise "from
	# nowhere" on every camera swing. What reaches the point is the middle of its
	# body, and not the origin down at its feet — hence the rise aiming with the
	# anchoring it will have in the hand already discounted.
	var destination := _capture_point.global_position + _anchor(pose)
	var middle := (_rise_origin + destination) * 0.5 + Vector3.UP * ARC_HEIGHT
	global_position = _bezier(_rise_origin, middle, destination, progress)

	var spin := _origin_basis.get_rotation_quaternion().slerp(pose.get_rotation_quaternion(), progress)
	# The somersault unwinds as it arrives: at the end only the pose is left.
	var flip := Quaternion(Vector3.RIGHT, FLIP_SPIN * (1.0 - progress))
	# It shrinks to the size it is held at as it arrives, rather than snapping to
	# it in the hand: the pull is the only frame where the two sizes are both on
	# screen, and a rat that changes size mid-catch is a rat that pops.
	global_basis = Basis(spin * flip).scaled(
		Vector3.ONE.lerp(_held_scale(_holder_peer), progress))

	model.scale = STRETCHED_SCALE.lerp(Vector3.ONE, progress)

	if t >= 1.0:
		_snap_to_hand()

## It arrived: from now on it is drawn in the coordinates of the point in the
## middle of the screen, though it stays where it is in the tree.
##
## It is never reparented into the hand, not even a hand on this machine. A
## node's path is its address on the wire: a `MultiplayerSynchronizer` writes to
## the node at the same path on the far machine, so moving this rat under a
## capture point renames it from `Rats/Rat_2` to something no other machine has,
## and every guest answers with `get_node: Node not found`. So the gesture is
## written in the hand's coordinates and carried out to the world every frame
## instead — see `_follow_capture_point`.
func _snap_to_hand() -> void:
	var pose := Basis.from_euler(_radians(HELD_POSE))
	_held_transform = Transform3D(pose, _anchor(pose))
	_follow_capture_point()
	_capture_phase = Capture.IN_HAND
	_capture_time = 0.0

## Carries `_held_transform` — written in capture-point coordinates — out to the
## world. This is what a `reparent` used to do for free, and doing it by hand is
## what keeps the rat's node, and the `Sync` under it, on the path every machine
## agreed on when the rat was spawned.
func _follow_capture_point() -> void:
	if _capture_point == null or not is_instance_valid(_capture_point):
		return
	global_transform = _capture_point.global_transform \
		* _held_transform.scaled_local(_held_scale(_holder_peer))
	_previous_position = global_position
	_step_distance = 0.0


## How big to draw the animal in the hand it is in: `FIRST_PERSON_SCALE` in our
## own hands, and `HELD_SCALE` in anybody else's. See there for why the two views do
## not agree, and why they should not.
##
## Asked by whose hand it is rather than by which node the hand is, because that
## is the question: the machine thinking for the rat holds every guest's catch on
## an avatar and its own on a camera, and only the second one is the picture the
## first-person pose was solved for.
func _held_scale(peer_id: int) -> Vector3:
	return FIRST_PERSON_SCALE if peer_id == _local_peer() else HELD_SCALE

## Where the rat's origin has to sit, in the `base` pose, for the middle of its
## body to land right on top of the capture point. It is why it struggles
## *around* the middle of the screen instead of sweeping the whole frame on
## every kick.
func _anchor(base: Basis) -> Vector3:
	return -(base * BODY_CENTER)

## Held in the hand: trembling the whole time, kicking now and then and biting
## when it can. All in local coordinates, over the point in the middle of the
## screen.
func _process_in_hand(delta: float) -> void:
	_struggle = lerpf(BASE_STRUGGLE, _struggle, pow(STRUGGLE_DAMPING, delta))
	_damp_jolt(delta)

	_kick_time -= delta
	if _kick_time <= 0.0:
		_kick_time = randf_range(KICK_INTERVAL.x, KICK_INTERVAL.y)
		_kick(1.0)
		if randf() < BITE_CHANCE:
			animator.play(ANIM_ATTACK, BLEND)
			animator.queue(ANIM_RUN)

	# Sine waves whose periods do not line up with each other: added together,
	# they do not repeat closely enough for the eye to catch the pattern.
	var t := _capture_time
	var tremor := Vector3(
		sin(t * 27.0) * 0.6 + sin(t * 41.0) * 0.4,
		sin(t * 33.0 + 1.3) * 0.5 + sin(t * 19.0) * 0.5,
		sin(t * 23.0 + 2.1)
	) * TREMOR * _struggle
	var spin := Vector3(
		sin(t * 21.0) * 0.5,
		sin(t * 17.0 + 0.7),
		sin(t * 29.0 + 2.2) * 0.7
	) * deg_to_rad(TREMOR_ANGLE) * _struggle

	var pose := Basis.from_euler(_radians(HELD_POSE) + spin + _jolt_spin)
	_held_transform = Transform3D(pose, _anchor(pose) + tremor + _jolt)
	_follow_capture_point()
	model.scale = model.scale.lerp(Vector3.ONE, minf(delta * 9.0, 1.0))

## The last moments: the fist closes past what the animal can take, and then
## there is no animal.
##
## It is one short beat with two halves. For the whole of `BURST_WINDUP` the
## body is crushed — flattened along its length, shaking hard, going nowhere —
## and at the end of it the rat is replaced by a spray of red thrown out of the
## fist (`BloodBurst`) and freed.
##
## The spray is deliberately *not* the rat's own child. This node is freed on the
## same frame it is spawned, and anything hanging off it would be freed with it:
## it goes into the world the rat was standing in and outlives the animal by the
## second or so it takes to fall.
func _process_burst(_delta: float) -> void:
	var t := clampf(_capture_time / BURST_WINDUP, 0.0, 1.0)

	# It shakes on the spot rather than travelling: what is being drawn is
	# something held still and squeezed, and a body that wandered the frame
	# would read as one still fighting. It shakes harder the closer it gets to
	# coming apart.
	var rattle := Vector3(
		sin(_capture_time * BURST_SHAKE_SPEED),
		sin(_capture_time * BURST_SHAKE_SPEED * 1.31 + 1.7),
		sin(_capture_time * BURST_SHAKE_SPEED * 0.83 + 0.4)
	) * BURST_SHAKE * t
	var spin := Vector3(
		sin(_capture_time * BURST_SHAKE_SPEED * 1.13),
		sin(_capture_time * BURST_SHAKE_SPEED * 0.91 + 2.2),
		sin(_capture_time * BURST_SHAKE_SPEED * 1.47 + 0.9)
	) * deg_to_rad(BURST_SHAKE_ANGLE) * t

	var pose := Basis.from_euler(_radians(HELD_POSE) + spin)
	_held_transform = Transform3D(pose, _anchor(pose) + rattle)
	_follow_capture_point()

	# Crushed, not shrinking: it gets *wider* as it gets shorter, which is what
	# a body being squeezed does and what makes the burst that follows read as
	# pressure having to go somewhere.
	model.scale = model.scale.lerp(BURST_SCALE, minf(t * 0.5, 1.0))

	if t < 1.0:
		return
	_burst()

## The animal comes apart. Everything about it that is louder than the rat —
## the spray, the bang, the knock in the player's own neck — is thrown here, and
## then the rat is gone.
func _burst() -> void:
	var point := global_position
	var away := Vector3.UP
	# Thrown out of the fist and back towards whoever is holding it, so the spray
	# crosses his view instead of going off into the room. The capture point sits
	# in front of his face and its -Z is where he is looking, so +Z is back at
	# him.
	if _capture_point != null and is_instance_valid(_capture_point):
		var facing := _capture_point.global_basis
		point = _capture_point.global_position + _anchor(Basis.from_euler(_radians(HELD_POSE)))
		away = (Vector3.UP + facing.z * BURST_BACK).normalized()

	# Everybody in the house sees the same rat come apart in the same place. The
	# spray is thrown here and asked for on every other machine, because this
	# body is freed on the last line of this function and the spawner takes the
	# guests' copies down with it: a burst left to each machine's own reading of
	# the wire would be a burst on none of them.
	_spray(point, away, 1.0)
	if _is_authority():
		_burst_elsewhere.rpc(point, away, 1.0)

	# And the knock in the neck of whoever was holding it. It is his camera
	# alone, so it goes to his machine and no further: everybody else is looking
	# at the spray from across the room, and a shake for something happening in
	# another man's hands is a shake with no cause on screen.
	_shake_holder()

	queue_free()

## The spray itself, and the bang under it. It is the half of `_burst` that has
## to happen on every machine, so it is the half that is its own function.
func _spray(point: Vector3, away: Vector3, strength := 1.0) -> void:
	# Into the world the rat was standing in rather than onto the rat: this body
	# is freed the moment the burst is over, and a spray parented to it would go
	# with it. The parent is the rat's own, which is the house's `Rats` container
	# — a node that outlives every animal in it.
	var world := get_parent()
	if world != null:
		BloodBurst.burst(world, point, away, strength)

	# The bang. Two sounds rather than one: `rat_death` went out with the last
	# squeeze (`die_in_hands`) and is the animal, and this is the wet crack of
	# it coming apart. They overlap on purpose — one sound for a kill this size
	# is a thin sound.
	#
	# Played locally rather than networked, and that is the whole point of this
	# function: the spray it belongs to is already being announced to every
	# machine, and a networked sound on top of that is the same crack played
	# twice on every screen but the one that sent it.
	#
	# Only a full burst bangs. A blow landing across the room has its own weapon
	# sound and does not need a second one under it — and a splash of blood the
	# size of `HIT_SPRAY` with a crack that size on top would be a mousetrap that
	# sounds like an explosion.
	if strength >= 1.0:
		AudioManager.play_3d("explosion_small", point, -4.0, randf_range(0.9, 1.1))
	else:
		AudioManager.play_3d("blood_drop", point, -8.0, randf_range(0.9, 1.15))

## A rat has come apart somewhere. Runs on every machine but the one that
## decided it.
##
## The point and the direction cross rather than being worked out here, because
## by the time this lands the animal may already have been taken down by the
## spawner — and a spray thrown from wherever this copy last heard the rat was
## is a spray in the wrong corner of the room.
@rpc("authority", "call_remote", "reliable")
func _burst_elsewhere(point: Vector3, away: Vector3, strength := 1.0) -> void:
	_spray(point, away, strength)

## Knocks the view of whoever was holding the rat, and only his.
##
## The holder can be sitting at another machine, so this fires on the one that
## owns the camera: ours goes straight to the player in the tree, and anybody
## else's crosses the wire to be played there.
func _shake_holder() -> void:
	if _holder_peer == 0:
		return
	if _holder_peer != _local_peer():
		if _is_authority():
			_shake_kill.rpc_id(_holder_peer)
		return
	_shake_local_player()

## The rat somebody was holding has come apart. Runs on that man's machine, sent
## by the one that thought for the animal.
##
## It carries nothing: the only thing the far machine needs to know is that it
## happened, and how hard a burst knocks the view is this script's business at
## both ends.
@rpc("authority", "reliable")
func _shake_kill() -> void:
	_shake_local_player()

## Knocks this machine's own view, if it has one.
##
## The body in the `player` group is the one man on this machine who is looking
## out of his own eyes — everybody else in the house is an avatar in
## `player_avatars`, and an avatar has no camera to shake. It is deliberately
## not `_get_player`, which answers *the nearest hunter* and would happily hand
## back somebody else's body standing closer.
func _shake_local_player() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player")
	if player != null and player.has_method("shake"):
		player.shake(BURST_SHAKE_STRENGTH)

func _kick(strength: float) -> void:
	_jolt = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)) \
		.normalized() * KICK_FORCE * strength
	_jolt_spin = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
		.normalized() * deg_to_rad(KICK_FORCE_ANGLE) * strength

func _damp_jolt(delta: float) -> void:
	var left := pow(JOLT_DAMPING, delta)
	_jolt *= left
	_jolt_spin *= left

func _bezier(from: Vector3, middle: Vector3, to: Vector3, t: float) -> Vector3:
	return from.lerp(middle, t).lerp(middle.lerp(to, t), t)

func _radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))

# --- States ----------------------------------------------------------------

func _reassess_state() -> void:
	var distance := _player_distance()
	# Hidden, it puts up with the player a lot closer before bolting again.
	var hearing_limit := hidden_panic_radius if _state == State.HIDING else panic_radius
	var scared := distance <= hearing_limit or (distance <= _current_alert_radius() and _sees_player())
	# The other thing that gets a rat off the ground: standing where one of its
	# own is lying dead. It hunts nobody and it does not move, so it never sends
	# the rat anywhere in particular — it only makes it not want to be here, and
	# the flight's own search is what finds it somewhere better.
	var foul := _fear_at(global_position, _fear_cache) > 0.0

	match _state:
		State.WANDERING, State.IDLE:
			if scared or foul:
				_change_state(State.FLEEING)
		State.FLEEING:
			if not scared and not foul and distance >= safe_radius:
				_change_state(State.WANDERING)
		State.HIDING:
			if scared or foul:
				_change_state(State.FLEEING)
			elif distance >= safe_radius and _state_time > 2.0:
				_change_state(State.WANDERING)

func _change_state(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state
	_state_time = 0.0
	match new_state:
		State.WANDERING:
			_pick_wander_target()
		State.IDLE:
			_clear_target()
			_idle_duration = randf_range(0.8, 2.4)
		State.FLEEING:
			_clear_target()
			_search_time = 0.0
			_bolt_hole = null
		State.HIDING:
			_clear_target()
			velocity.x = 0.0
			velocity.z = 0.0
		State.SPRAYING:
			_clear_target()
			velocity.x = 0.0
			velocity.z = 0.0
			_sprayed = false
			# Played here and not in `_process_spray`, so the wind-up the player
			# is being asked to read starts on the frame the decision is made.
			animator.speed_scale = 1.0
			animator.play(ANIM_ATTACK, BLEND)

func _process_wander(delta: float) -> void:
	_target_time += delta
	if not _has_target or _target_time > 6.0 or agent.is_navigation_finished():
		# Now and then it stops to sniff instead of picking another destination.
		if randf() < 0.35:
			_change_state(State.IDLE)
			return
		_pick_wander_target()
	_move(_path_direction(), wander_speed, delta)

func _process_idle(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	if _state_time >= _idle_duration:
		_change_state(State.WANDERING)

func _process_flee(delta: float) -> void:
	# Cornered beats cover. A breed that sprays would rather turn round than keep
	# looking for somewhere to sit, and it is asked every frame rather than on the
	# search clock: the man is a stride away and a third of a second late is a
	# rat that has already been grabbed.
	if _should_spray():
		_change_state(State.SPRAYING)
		return

	_search_time -= delta
	if _search_time <= 0.0:
		_search_time = SEARCH_INTERVAL
		# A way out of the room beats a corner to sit in. The hideout search is
		# only asked once there is no hole worth running for — it is the more
		# expensive of the two by a long way, and a rat that has found a hole is
		# not going to use what it comes back with.
		_bolt_hole = _pick_bolt_hole()
		if _bolt_hole != null:
			_set_target(_bolt_hole.mouth())
		else:
			_search_hideout()

	if _has_target and agent.is_navigation_finished():
		# The hole first: a rat that has arrived at one is gone through it, and
		# what it does next it does from the far end of the house.
		if _bolt_hole != null:
			_dive_into(_bolt_hole)
			return
		# It reached the hideout: if the player cannot reach it with his eyes, it
		# keeps still.
		if not _sees_player() and _player_distance() > panic_radius:
			_change_state(State.HIDING)
			return
		_clear_target()
		_search_time = 0.0

	var direction := _path_direction()
	if direction.is_zero_approx():
		# No reachable hideout (or it fell off the mesh): it runs far away on
		# instinct, sniffing out walls ahead. Away from everybody at once and not
		# merely from the nearest — with two hunters closing in, fleeing the
		# nearer one alone is what runs the animal straight into the other.
		direction = _dodge(_away_from_hunters())
	var speed := burst_speed if _state_time < BURST_TIME else flee_speed
	_move(direction, speed, delta)

func _process_hide(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	model.scale = model.scale.lerp(CROUCH_SCALE, minf(delta * 8.0, 1.0))

# --- Spraying --------------------------------------------------------------

## Whether this animal, right now, would rather turn round than run. A breed that
## does it at all, off its cooldown, with a hunter inside `SPRAY_RANGE` and
## nothing solid in between.
##
## The wall check matters more than it looks: without it a rat sprays through the
## crate it is hiding behind, and the man on the other side loses flesh to an
## animal he cannot see.
func _should_spray() -> bool:
	if species == null or not species.sprays or _spray_time > 0.0:
		return false
	var hunter := _get_player()
	if hunter == null:
		return false
	if _flat_distance(hunter.global_position, global_position) > SPRAY_RANGE:
		return false
	return not _blocked(global_position + Vector3.UP * EYE_HEIGHT,
		hunter.global_position + Vector3.UP * EYE_HEIGHT)


## Planted, turning, and then the spray. Three beats: it faces him while the
## attack plays, it fires once at `SPRAY_WINDUP`, and it stands there for
## `SPRAY_RECOVER` afterwards before going back to running.
##
## It keeps turning through the wind-up on purpose. A rat that locked its aim the
## instant it stopped could be walked around; one that tracks has to be *backed
## away from*, which is the answer the fight is meant to teach.
func _process_spray(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	var hunter := _get_player()
	if hunter != null:
		var facing := _direction_to(hunter.global_position)
		if not facing.is_zero_approx():
			_turn_to(facing, delta)

	if not _sprayed and _state_time >= SPRAY_WINDUP:
		_sprayed = true
		_let_fly()
		return
	if _state_time >= SPRAY_WINDUP + SPRAY_RECOVER:
		_spray_time = SPRAY_COOLDOWN
		_change_state(State.FLEEING)


## The moment it fires. **Host only** — this is reached from the state machine,
## which only ever runs on the machine thinking for the animal — and its whole job
## is to say so to everybody, because what follows has to happen on four screens
## at once.
##
## Off the wire an `rpc` would be an error in the log for a call that is already
## here, so the announcement is made plainly instead. Same code down either road,
## which is what keeps solo from being a second set of rules.
func _let_fly() -> void:
	var facing := -global_basis.z
	facing.y = 0.0
	if facing.is_zero_approx():
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var from := global_position
	if _on_the_wire():
		_spray_at.rpc(from, facing)
	else:
		_spray_at(from, facing)
	# The mark it leaves is a node, so it is the host's alone to make. Just in
	# front of its feet, lying the way the spray went.
	ClueManager.mark(from + facing * SPRAY_MARK_REACH, facing)


## The spray landing, on every machine at once (`call_local`).
##
## **Each machine tests its own player and hurts him locally, and that is the
## whole design.** Flesh is a single-player concern here — the same rule
## `RatStreak` keeps — so what crosses the wire is only *that a rat sprayed, from
## here, that way*. Four machines each answer "was I in it" about the one man they
## are responsible for, and nobody's wound travels.
##
## The cone is written out rather than borrowed. `Weapon._rat_in_sights` is the
## only cone in the project and it is bound to the player's camera, his exports
## and the `rats` group; three lines here are cheaper than making that general.
@rpc("authority", "call_local", "reliable")
func _spray_at(from: Vector3, facing: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		push_warning("Rat: a spray from peer %d, which does not own this animal — ignored."
			% sender)
		return
	_play_spray_sound(from)

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("take_damage"):
		return
	if player.has_method("is_dead") and player.is_dead():
		return
	var to_player := player.global_position - from
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > SPRAY_REACH or distance < 0.01:
		return
	if facing.dot(to_player / distance) < cos(deg_to_rad(SPRAY_ANGLE)):
		return
	if _blocked(from + Vector3.UP * EYE_HEIGHT, player.global_position):
		return
	player.take_damage(SPRAY_DAMAGE)
	# And on the lens. The bar draining says he was hurt; this says by what.
	if player.has_method("splash"):
		player.splash()


## The hiss, where it happened. Built on the same generator the streaks use
## (`RatStreak.build_hiss`) so a spray and the mark it leaves sound like the same
## fluid — louder and shorter, because this one is under pressure.
func _play_spray_sound(from: Vector3) -> void:
	var noise := AudioStreamPlayer3D.new()
	noise.stream = RatStreak.build_hiss(SPRAY_SOUND_TIME, SPRAY_SOUND_LOUDNESS)
	noise.unit_size = 5.0
	noise.max_distance = 16.0
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(noise)
	noise.global_position = from
	noise.finished.connect(noise.queue_free)
	noise.play()

# --- Bolting ---------------------------------------------------------------
#
# The one thing a rat can do that no amount of cornering answers: go into the
# wall here and come out of it over there. The two mouths are a `RatHole` and its
# partner (`scripts/house/rat_hole.gd`), the run between them is not walked, and
# the whole of it costs one teleport.
#
# It is deliberately not a hiding place. A rat that dove into a hole and stayed
# in it would be a rat the crew could never finish the shift over, so what comes
# out of the far end is the same animal in the same flight, looking for somewhere
# to hide from wherever it now finds itself.

## The hole worth running for, or null. The nearest one in reach whose far mouth
## actually buys the animal something: a run that puts it down beside the man
## chasing it is not an escape, and a run it cannot reach on foot is not a run.
func _pick_bolt_hole() -> RatHole:
	if _bolt_time > 0.0:
		return null
	var eyes := _hunter_eyes()
	if eyes.is_empty():
		return null
	var here := _closest_eye_distance(global_position, eyes)
	var best: RatHole = null
	var best_distance := BOLT_RADIUS
	for node in get_tree().get_nodes_in_group("rat_holes"):
		var hole := node as RatHole
		if hole == null:
			continue
		var far_end := hole.linked()
		if far_end == null:
			continue
		# Every measurement is taken at the mouth — the pace of floor in front of
		# the slit — and never at the hole itself, which is in the wall
		# (`RatHole.mouth`). A rat sent to the plaster is a rat sent somewhere it
		# cannot stand, and a path to it comes back empty.
		var stand: Vector3 = hole.mouth()
		var distance := _flat_distance(stand, global_position)
		if distance >= best_distance:
			continue
		# Running *towards* the hunter to reach the hole is worse than standing
		# still, and so is coming out beside him at the other end.
		if _closest_eye_distance(stand, eyes) < panic_radius:
			continue
		if _closest_eye_distance(far_end.mouth(), eyes) < here + BOLT_GAIN:
			continue
		if _path_to(stand).is_empty():
			continue
		best = hole
		best_distance = distance
	return best


## Into the wall and out of it somewhere else. The far mouth is snapped onto the
## mesh before the body is put there: a hole is modelled in the skirting board
## and its origin can sit a finger inside the wall, which is a rat that arrives
## with nowhere to walk.
##
## The flight is not ended by this, only moved. `_search_time` is knocked to zero
## so the animal looks for cover from where it now stands rather than carrying on
## towards a hideout it picked in another room.
func _dive_into(hole: RatHole) -> void:
	_bolt_hole = null
	# A finished navigation path may stop below a mouth on another floor.
	# The rat must physically reach the entrance before taking its wall route.
	if global_position.distance_to(hole.mouth()) > MESH_TOLERANCE:
		_clear_target()
		_search_time = 0.0
		return
	_bolt_time = BOLT_COOLDOWN
	_clear_target()
	_search_time = 0.0
	var far_end := hole.linked()
	if far_end == null:
		return
	var out := _navigable_point(far_end.mouth())
	if out == INVALID_POINT:
		out = far_end.mouth()
	global_position = out
	_clear_target()
	velocity = Vector3.ZERO
	# Where it stands is the one thing the watchers have no other way of
	# learning, and a teleport is further than the easing will ever cover
	# (`SNAP_DISTANCE`), so it lands on their screens as the jump it is.
	_publish()


## How far the nearest hunter is from a point, flat. Null answer is `INF`, which
## every comparison above reads as "nobody near it".
func _closest_eye_distance(point: Vector3, eyes: Array[Vector3]) -> float:
	var closest := INF
	for eye in eyes:
		closest = minf(closest, _flat_distance(point, eye))
	return closest

# --- Food ------------------------------------------------------------------
#
# The mirror of the fear below: ground the rats *want*. A heap of rubbish the
# crew emptied a tub of bait into joins the `lures` group
# (`scripts/house/garbage_pile.gd`), and from then on it is where the animals
# drift back to whenever nothing more urgent is happening.
#
# It is a preference and deliberately not a command. A frightened rat ignores it
# entirely — the flight never asks — and even a calm one only makes for it most
# of the time (`LURE_PULL`), because a house where every animal walked straight
# to the bait would be a house the crew only has to look at one corner of.

## The baited heap this rat can smell, or null. The nearest one whose own reach
## covers where the animal is standing: a tub of food in the alley outside is not
## something a rat in the back bedroom is going to notice.
func _nearest_lure() -> Node3D:
	var nearest: Node3D = null
	var best := INF
	for node in get_tree().get_nodes_in_group("lures"):
		var lure := node as Node3D
		if lure == null:
			continue
		var reach := DEFAULT_LURE_RADIUS
		if lure.has_method("lure_radius"):
			reach = lure.lure_radius()
		var distance := _flat_distance(lure.global_position, global_position)
		if distance > reach or distance >= best:
			continue
		best = distance
		nearest = lure
	return nearest

# --- Fear ------------------------------------------------------------------
#
# Ground the rats will not have. A mousetrap that has gone off with a rat still
# in it joins the `fear` group, and from then on it is a hole in the map as far
# as the others are concerned — not a wall, which is the point: the flight can
# still cross it when there is nowhere else to go, it simply never chooses to.
#
# It is a preference and deliberately not geometry. Baking it into the navigation
# mesh would make the rats route politely around it the way they route around
# crates, and a trap that quietly reshaped the floor is exactly what
# `scripts/traps/trap.gd` warns against.

## Everywhere in the map a rat has learned to hate, each packed as its position
## and how far it reaches. It comes back empty for as long as nothing is foul,
## which is nearly always — and that is what makes the whole thing free to ask
## about when there is nothing to ask.
func _fear_spots() -> Array[Vector4]:
	var spots: Array[Vector4] = []
	for node in get_tree().get_nodes_in_group("fear"):
		var spot := node as Node3D
		if spot == null:
			continue
		var reach := DEFAULT_FEAR_RADIUS
		if spot.has_method("fear_radius"):
			reach = spot.fear_radius()
		var at := spot.global_position
		spots.append(Vector4(at.x, at.y, at.z, reach))
	return spots

## How deep in the fear a point sits, from 0 on clean ground up to 1 at the heart
## of it. It is a sum: two dead rats in the same corner make a corner twice as
## bad as one.
func _fear_at(point: Vector3, spots: Array[Vector4]) -> float:
	var fear := 0.0
	for spot in spots:
		var reach := spot.w
		if reach <= 0.0:
			continue
		var distance := _flat_distance(point, Vector3(spot.x, spot.y, spot.z))
		if distance >= reach:
			continue
		fear += 1.0 - distance / reach
	return fear

# --- Hideout ---------------------------------------------------------------

func _prepare_cover_query() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = COVER_RADIUS
	_cover_query.shape = sphere
	_cover_query.collision_mask = SCENERY_LAYER
	_cover_query.exclude = [get_rid()]

## Picks where to run: it puts the blind spots behind nearby obstacles together
## with a fan of points behind it and keeps the best-scoring one.
func _search_hideout() -> void:
	var player := _get_player()
	if player == null or not _map_ready():
		_clear_target()
		return

	# Everybody in the house, gathered once and handed down through the whole
	# search. Once, and not per candidate, because the scoring below asks about
	# them some hundreds of times per search and the list does not change while
	# it runs.
	var eyes := _hunter_eyes()
	# Found a good hideout? Then it does not keep changing its mind halfway.
	if _hideout_still_works(eyes):
		return
	_clear_target()

	var best := INVALID_POINT
	var best_score := -INF

	for point in _candidates(eyes):
		# The point's score comes first because it is cheap; the path only
		# subtracts, so anything already losing to the leader need not be asked
		# about at all.
		var score := _score_point(point, eyes)
		if score <= best_score:
			continue
		var path := _path_to(point)
		if path.is_empty():
			continue
		score -= _path_cost(path, eyes)
		if score > best_score:
			best_score = score
			best = point

	if best != INVALID_POINT:
		_set_target(best)

## Where everybody in the house is looking from: one point per hunter, at chest
## height, which is what the sight checks are drawn to.
##
## It is the hunters flattened into bare positions on purpose. What the scoring
## does with them is geometry and nothing else, and a list of points can be
## carried down through a search that runs hundreds of checks without going back
## to the tree for a node that has not moved in the meantime.
func _hunter_eyes() -> Array[Vector3]:
	var eyes: Array[Vector3] = []
	for hunter in _hunters():
		eyes.append(hunter.global_position + Vector3.UP * PLAYER_HEIGHT)
	return eyes

## The destinations it considers in this search, all already snapped to the mesh.
##
## `eyes` is everybody, and it is what the blind spots are measured against: a
## hiding place has to be behind cover from *every* pair of eyes, not just the
## nearest. The fan of points needs no such argument — it is thrown in the
## direction the rat is already running, which `_away_from_hunters()` works out
## from the same crew.
func _candidates(eyes: Array[Vector3]) -> Array[Vector3]:
	var points: Array[Vector3] = []

	_cover_query.transform = Transform3D(Basis(), global_position)
	for found in get_world_3d().direct_space_state.intersect_shape(_cover_query, MAX_COVERS):
		var body := found.get("collider") as Node3D
		if body == null:
			continue
		# Cover is something that stands up in front of the player: the floor and
		# the ramps show up in the query, but they hide nobody.
		if body.global_position.y < global_position.y + 0.5:
			continue
		if _flat_distance(body.global_position, global_position) > COVER_RADIUS:
			continue
		var point := _blind_spot_behind(body.global_position, eyes)
		if point != INVALID_POINT:
			points.append(point)

	var flight := _away_from_hunters()
	for i in CANDIDATES:
		var direction := flight.rotated(Vector3.UP, randf_range(-FAN_SPREAD, FAN_SPREAD))
		var raw := global_position + direction * randf_range(MIN_SEARCH_DISTANCE, MAX_SEARCH_DISTANCE)
		var point := _navigable_point(raw)
		if point != INVALID_POINT:
			points.append(point)

	return points

## Walks behind the obstacle, moving away from the hunters, until it leaves their
## sight.
##
## Which way "behind" is comes from the nearest man — an obstacle has a different
## far side for each person looking at it, and the one worth putting a crate
## between yourself and is the one closing in. But the *arrival* is checked
## against everybody: a spot hidden from him and open to his colleague is not a
## hideout, and the animal that trusted it is caught standing still.
func _blind_spot_behind(center: Vector3, eyes: Array[Vector3]) -> Vector3:
	if eyes.is_empty():
		return INVALID_POINT
	var nearest := eyes[0]
	var best := INF
	for eye in eyes:
		var distance := _flat_distance(eye, global_position)
		if distance < best:
			best = distance
			nearest = eye

	var direction := center - nearest
	direction.y = 0.0
	if direction.is_zero_approx():
		return INVALID_POINT
	direction = direction.normalized()
	# It starts from the rat's height, not from the obstacle's centre, which may
	# be quite high up.
	var base := Vector3(center.x, global_position.y, center.z)

	for i in COVER_STEPS:
		var point := _navigable_point(base + direction * (COVER_STEP * (i + 1)))
		if point == INVALID_POINT:
			continue
		if _flat_distance(point, global_position) > MAX_SEARCH_DISTANCE:
			continue
		if _hidden_from_all(point, eyes):
			return point
	return INVALID_POINT

## Whether a spot is out of sight of every last person in the house. One pair of
## eyes with a clear line to it is enough to make it no hiding place at all.
func _hidden_from_all(point: Vector3, eyes: Array[Vector3]) -> bool:
	var head := point + Vector3.UP * EYE_HEIGHT
	for eye in eyes:
		if not _blocked(eye, head):
			return false
	return true

## The candidate's score before looking at the path: far from the hunters is
## good, out of their sight is better still, and a dead end loses points.
##
## The distance that counts is to the *nearest* man, and the sight check is
## against *all* of them. Both are the cautious reading: a spot ten metres from
## one hunter and two from another is a spot two metres from a hunter, and one
## hidden from three men and open to the fourth is not hidden.
func _score_point(point: Vector3, eyes: Array[Vector3]) -> float:
	var distance := INF
	for eye in eyes:
		distance = minf(distance, _flat_distance(point, eye))
	if distance < panic_radius:
		return -INF
	var score := distance
	if _hidden_from_all(point, eyes):
		score += HIDDEN_BONUS
	# A blind spot with a dead rat in it is no blind spot at all. The penalty is
	# steep but finite: cornered, with the player on one side and the smell on
	# the other, a rat still picks the smell over standing still.
	score -= _fear_at(point, _fear_cache) * FEAR_PENALTY
	return score + _exits_from_point(point) * EXIT_BONUS

## How many of the four directions around the point are clear. A closed corner
## returns zero or one: it hides well while the player stays away, and turns into
## a trap when he arrives.
func _exits_from_point(point: Vector3) -> int:
	var origin := point + Vector3.UP * EYE_HEIGHT
	var clear := 0
	for i in 4:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 4.0)
		if not _blocked(origin, origin + direction * EXIT_RANGE):
			clear += 1
	return clear

## How much the path subtracts from the score: its length, plus a heavy penalty
## if it grazes anybody — a great hideout is no use if the rat has to walk past
## one of the men hunting it to reach it.
##
## Anybody, and not merely the nearest: the whole trouble with a route measured
## against one hunter is that it happily threads the rat straight past a second
## one standing in the corridor. The penalty lands once however many it brushes,
## which is the same rule the foul ground below is scored by — a path is either
## a bad idea or it is not.
func _path_cost(path: PackedVector3Array, eyes: Array[Vector3]) -> float:
	var flat_hunters: Array[Vector3] = []
	for eye in eyes:
		flat_hunters.append(Vector3(eye.x, 0.0, eye.z))
	var length := 0.0
	var closest := INF

	# The worst any one foul spot gets brushed along the way, and not the sum of
	# them: a walk that grazes the same corpse across five stretches of path was
	# punished once by the map, not five times by the mesh's tessellation.
	var foul := 0.0

	for i in range(1, path.size()):
		var from := Vector3(path[i - 1].x, 0.0, path[i - 1].z)
		var to := Vector3(path[i].x, 0.0, path[i].z)
		length += from.distance_to(to)
		for flat_hunter in flat_hunters:
			var graze := Geometry3D.get_closest_point_to_segment(flat_hunter, from, to)
			closest = minf(closest, graze.distance_to(flat_hunter))
		for spot in _fear_cache:
			var reach := spot.w
			if reach <= 0.0:
				continue
			var centre := Vector3(spot.x, 0.0, spot.z)
			var brush := Geometry3D.get_closest_point_to_segment(centre, from, to)
			var distance := brush.distance_to(centre)
			if distance < reach:
				foul = maxf(foul, 1.0 - distance / reach)

	var cost := length * PATH_WEIGHT
	if closest < panic_radius:
		cost += NEAR_MISS_PENALTY
	return cost + foul * FEAR_CROSSING_PENALTY

## The current hideout keeps working as long as nobody reaches it with his eyes
## and nobody has come too close to it. One man walking round the crate is enough
## to send the rat looking again, even with the others still shut out.
func _hideout_still_works(eyes: Array[Vector3]) -> bool:
	if not _has_target:
		return false
	for eye in eyes:
		if _flat_distance(_target, eye) < panic_radius:
			return false
	return _hidden_from_all(_target, eyes)

func _pick_wander_target() -> void:
	# The food first, when there is any. A baited heap of rubbish is the one
	# thing in the house that draws a calm rat somewhere in particular — every
	# other destination it has is a die roll — and it is what makes the tub the
	# crew emptied during the survey worth what it cost.
	if randf() < LURE_PULL:
		var food := _nearest_lure()
		if food != null:
			var spread := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			if spread.is_zero_approx():
				spread = Vector3.FORWARD
			var at := _navigable_point(
				food.global_position + spread.normalized() * randf() * LURE_SPREAD)
			if at != INVALID_POINT and _fear_at(at, _fear_cache) <= 0.0:
				_set_target(at)
				return

	for attempt in WANDER_TRIES:
		var direction := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
		var point := _navigable_point(global_position + direction.normalized() * randf_range(4.0, 12.0))
		if point == INVALID_POINT:
			continue
		# It will not stroll into a corner that smells of a dead rat. It rolls
		# again rather than give up on the spot: a rat with no destination is a
		# rat standing still, and standing still is what it is trying to stop
		# doing.
		if _fear_at(point, _fear_cache) > 0.0:
			continue
		_set_target(point)
		return
	_clear_target()

# --- Navigation ------------------------------------------------------------

## The mesh is baked when the map opens and only starts answering queries after
## the navigation server's first sync. Until then the rat has nowhere to go, and
## asking before that is an error.
func _map_ready() -> bool:
	var map := agent.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0

func _set_target(point: Vector3) -> void:
	_target = point
	_has_target = true
	_target_time = 0.0
	agent.target_position = point

func _clear_target() -> void:
	_has_target = false
	# A target on top of its own body: the agent considers itself arrived and
	# stops asking for a path until the next decision.
	agent.target_position = global_position

## Where to walk now: the next step of the path to the target. While an emergency
## dodge lasts, it overrides the path.
func _path_direction() -> Vector3:
	if _dodge_time > 0.0:
		return _dodge_direction
	if not _has_target or agent.is_navigation_finished():
		return Vector3.ZERO
	var step := agent.get_next_path_position() - global_position
	step.y = 0.0
	return Vector3.ZERO if step.is_zero_approx() else step.normalized()

## Snaps a loose point onto the navigation mesh. Returns `INVALID_POINT` when it
## falls far from it — inside a crate, stuck in a wall, off the map — or on a
## level the rat cannot reach.
func _navigable_point(point: Vector3) -> Vector3:
	if not _map_ready():
		return INVALID_POINT
	# `on_mesh` and not `snapped`, which is a built-in method name that a local
	# of that name hides for the rest of the function.
	var on_mesh := NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), point)
	if _flat_distance(on_mesh, point) > MESH_TOLERANCE:
		return INVALID_POINT
	if absf(on_mesh.y - point.y) > MAX_HEIGHT_DROP:
		return INVALID_POINT
	return on_mesh

## Path to the point through the mesh. It comes back empty when the destination
## is on a separate island — on top of a platform, on the other side of a wall —
## and the path dies before getting there.
func _path_to(point: Vector3) -> PackedVector3Array:
	var map := agent.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map, global_position, point, true)
	if path.size() < 2 or _flat_distance(path[-1], point) > MESH_TOLERANCE:
		return PackedVector3Array()
	if absf(path[-1].y - point.y) > MAX_HEIGHT_DROP:
		return PackedVector3Array()
	return path

# --- Perception ------------------------------------------------------------
#
# **A rat is afraid of everybody in the house, and not only of whoever happens to
# be standing on the machine that thinks for it.**
#
# That distinction is the whole of this section, and it used to be missed. The
# hunt is played on several machines and a rat thinks on one of them — the
# host's — but a hunter is a hunter on every screen, and the man the host cannot
# see is still a man walking up behind the animal. Before this, a guest could
# stand on a rat and it would go on grooming itself: the rat asked for "the
# player", got the one character standing on the host's machine, and measured
# its whole fear against him.
#
# There are two kinds of body to ask about, and they are not the same kind of
# node:
#
# - The character on *this* machine, `player.tscn`, in the group `player`. There
#   is exactly one, always, solo hunt included.
# - Everybody else, as `PlayerAvatar` in the group `player_avatars` — including,
#   awkwardly, a body standing for the very character above. Every peer gets an
#   avatar, our own among them (`player_avatars.gd`), so the two groups overlap
#   by exactly one and the overlap has to be dropped or the local hunter is
#   counted twice.
#
# Everything below is built on `_hunters()`, the two lists put together with that
# overlap removed. On top of it sit the two questions the fear machine actually
# asks: who is *nearest* (`_get_player`, kept under its old name because a dozen
# callers ask it for "the threat"), and whether *anybody at all* can see the rat.
# The second is not the first one's line of sight: a rat with a crate between it
# and the nearest man, and a second man standing in the open beside it, has been
# seen.
#
# Solo none of this costs anything worth measuring: the avatar group is empty,
# the list is one node long, and every answer is what it always was.

## Everybody hunting in this house, however many machines they are sitting at.
##
## Rebuilt on each call rather than cached: bodies come and go with the wire — a
## peer drops, a man joins mid-shift — and a cached list is a rat afraid of
## somebody who has left the game. It is a handful of nodes asked for a few times
## a frame, which is a cost the profile does not notice.
func _hunters() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var tree := get_tree()
	if tree == null:
		return found

	# Ours first, so that when two men are the same distance away the one this
	# machine can say most about is the one that wins.
	var local := tree.get_first_node_in_group("player") as Node3D
	if local != null:
		found.append(local)

	var us := multiplayer.get_unique_id() if multiplayer != null else 0
	for node in tree.get_nodes_in_group("player_avatars"):
		var avatar := node as PlayerAvatar
		if avatar == null:
			continue
		# Our own body is in this group too, and stands exactly where the
		# character above stands. Counting it again would not change which man is
		# nearest, but it would double the sight rays and read as a bug to the
		# next person through here.
		if avatar.peer_id == us:
			continue
		# A body that has never had a packet is not standing anywhere yet: it
		# waits at the origin to be told where it is (`player_avatar.gd: _seen`),
		# and a rat fleeing the origin is a rat fleeing nobody.
		if not avatar.visible:
			continue
		found.append(avatar)

	return found

## The nearest hunter, and so the one the flight is measured against: where to
## run from, whose eyes to get out of, whose path not to cross.
##
## Nearest and not "the most dangerous", because at a rat's scale those are the
## same thing — everybody in this game kills it in one go, so the only question
## a rat has about a man is how far away he is.
func _get_player() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for hunter in _hunters():
		var distance := _flat_distance(global_position, hunter.global_position)
		if distance < best_distance:
			best_distance = distance
			best = hunter
	_player = best
	return _player

func _player_position() -> Vector3:
	var player := _get_player()
	return player.global_position if player != null else INVALID_POINT

func _player_distance() -> float:
	var player := _get_player()
	if player == null:
		return INF
	return _flat_distance(global_position, player.global_position)

## The rat notices someone running past from further off than someone strolling.
##
## Asked of the nearest man, who is the one the flight is about. A sprinter
## further away is caught by `_sees_player`, which asks everybody at his own
## radius.
func _current_alert_radius() -> float:
	return _alert_radius_for(_get_player())

## How far away this particular man is noticed from. Split out of
## `_current_alert_radius` because the sight check now asks it of everybody in
## turn, and each of them is moving at his own speed.
##
## The two kinds of body answer differently and neither can answer for the other:
## the character knows its own `velocity`, while an avatar has none — it is a
## `Node3D` eased towards wherever the wire last put it, so its speed is worked
## out from the packets instead (`player_avatar.gd: speed`).
func _alert_radius_for(hunter: Node3D) -> float:
	if hunter == null:
		return alert_radius
	var speed := 0.0
	var body := hunter as CharacterBody3D
	if body != null:
		speed = Vector2(body.velocity.x, body.velocity.z).length()
	else:
		var avatar := hunter as PlayerAvatar
		if avatar != null:
			speed = avatar.speed
	if speed > RUNNING_SPEED:
		return alert_radius * 1.4
	return alert_radius

## Whether *anybody* has this rat in view, each of them from his own distance.
##
## Everybody rather than just the nearest, and that is the point of it: a man
## crouched behind a crate three metres away does not see the rat, and his
## colleague standing in the open across the room does. Asking only the nearest
## would leave the animal sitting still in plain sight of somebody walking
## straight at it.
func _sees_player() -> bool:
	for hunter in _hunters():
		if _sees(hunter):
			return true
	return false

## One man's line of sight, at his own alert radius. The distance is checked
## first because it is arithmetic and the sight check is a ray: a man on the far
## side of the house is dismissed without troubling the physics server about him.
func _sees(hunter: Node3D) -> bool:
	if hunter == null:
		return false
	if _flat_distance(global_position, hunter.global_position) > _alert_radius_for(hunter):
		return false
	return not _blocked(
		global_position + Vector3.UP * EYE_HEIGHT,
		hunter.global_position + Vector3.UP * PLAYER_HEIGHT
	)

## True if there is scenery between the two points.
func _blocked(from: Vector3, to: Vector3) -> bool:
	var params := PhysicsRayQueryParameters3D.create(from, to, SCENERY_LAYER, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()

# --- Movement --------------------------------------------------------------

## Deflects the requested direction when there is a wall ahead, trying wider and
## wider openings to both sides. It is plan B for a rat with no path through the
## mesh; one that has a path already comes routed around the scenery.
func _dodge(direction: Vector3) -> Vector3:
	if direction.is_zero_approx():
		return direction
	var origin := global_position + Vector3.UP * EYE_HEIGHT
	if not _whisker_hit(origin, direction):
		return direction
	for degrees: float in DODGE_ANGLES:
		var attempt := direction.rotated(Vector3.UP, deg_to_rad(degrees))
		if not _whisker_hit(origin, attempt):
			return attempt
	return -direction

func _whisker_hit(origin: Vector3, direction: Vector3) -> bool:
	return _blocked(origin, origin + direction.normalized() * WHISKER_RANGE)

func _move(direction: Vector3, speed: float, delta: float) -> void:
	direction.y = 0.0
	var standing := direction.is_zero_approx()
	_desired_speed = 0.0 if standing else speed
	var target := Vector3.ZERO if standing else direction.normalized() * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	_turn_to(Vector3(velocity.x, 0.0, velocity.z), delta)
	model.scale = model.scale.lerp(Vector3.ONE, minf(delta * 8.0, 1.0))


func _update_steps() -> void:
	var walked := _flat_distance(global_position, _previous_position)
	if not is_on_floor() or _desired_speed <= IDLE_SPEED:
		_step_distance = 0.0
		return
	_step_distance += walked
	while _step_distance >= STEP_DISTANCE:
		_step_distance -= STEP_DISTANCE
		AudioManager.play_networked_3d("step_grass", global_position, -8.0, 1.0, self)

func _turn_to(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.2:
		return
	var angle := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, angle, 1.0 - exp(-turn_speed * delta))

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= gravity * delta

## The rat can still get wedged into a corner: pushed by the player, thrown off
## the mesh or squeezed against another rat. If it spends too long wanting to
## walk without going anywhere, it takes a step sideways and looks for another
## path.
func _check_stuck(delta: float) -> void:
	if _dodge_time > 0.0:
		_dodge_time -= delta

	# The maths uses the speed it *asked for*, not `velocity`: something running
	# head-on into a wall has its velocity zeroed by `move_and_slide` and would
	# pass for something that stopped on purpose.
	var expected := _desired_speed * delta * 0.3
	var walked := _flat_distance(global_position, _previous_position)
	if _desired_speed > IDLE_SPEED and walked < expected:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_previous_position = global_position

	if _stuck_time > STUCK_TIME:
		_stuck_time = 0.0
		_shake_sideways()
		_clear_target()
		_search_time = 0.0
		if _state == State.WANDERING:
			_pick_wander_target()

## Picks a clear side and runs that way for a moment, just long enough to come
## loose from the corner before going back to following the path.
func _shake_sideways() -> void:
	var forward := _direction_to(_target) if _has_target else -global_basis.z
	var origin := global_position + Vector3.UP * EYE_HEIGHT
	# Roll which side to start on, otherwise ten rats stuck in the same corner
	# all leave to the right.
	var sides := [1.0, -1.0] if randf() < 0.5 else [-1.0, 1.0]
	_dodge_time = DODGE_TIME
	for side: float in sides:
		_dodge_direction = forward.rotated(Vector3.UP, side * PI * 0.5)
		if not _whisker_hit(origin, _dodge_direction):
			return
	_dodge_direction = -forward

# --- The wire ---------------------------------------------------------------
#
# One direction only. The host writes the `sync_*` variables at the end of every
# physics frame and the `Sync` node in `rat.tscn` carries them; a guest reads
# them and draws. Nothing here sends a packet by hand, and no guest ever writes
# back — a rat has exactly one machine thinking for it, and that is what keeps
# ten rats from being ten different animals on two screens.

## The host's frame, packed for everybody else. Called at the end of every
## `_physics_process` — including the ones that return early, so that a rat that
## is dead, pinned or falling goes on reporting rather than freezing at the last
## place it was fully alive.
##
## Solo it writes six variables nobody reads, which is a few floats a frame and
## the price of having no second code path to keep in step.
func _publish() -> void:
	sync_position = global_position
	sync_yaw = rotation.y
	sync_speed = Vector2(velocity.x, velocity.z).length()
	sync_state = _state
	sync_crouched = model.scale != Vector3.ONE
	sync_holder = _holder_peer

## Somebody else's rat, drawn from the last packet. Runs on the screen's beat,
## which is where easing belongs: what arrives twenty times a second has to be
## spread across however many frames the watcher's machine draws in between.
##
## The animation is picked from the speed that crossed rather than from this
## body's own `velocity`, which is zero here and always will be — a puppet has
## its physics switched off and never moves itself.
func _draw_remote(delta: float) -> void:
	if not _seen:
		return

	# In somebody's hand it is not walking about the map, and easing it towards a
	# position on the floor is not what should happen to it. Where it belongs is
	# against the man holding it — his camera if that man is us, his chest if he
	# is somebody across the wire — and that is a different sum entirely.
	if sync_state == State.CAPTURED and sync_holder != 0:
		_draw_remote_capture(delta)
		return
	_release_remote_capture()

	var weight := 1.0 - exp(-SMOOTHING * delta)
	# Further off than this is not a rat running: it is one that respawned, or a
	# hole in the wire. Sliding across the room to it would read as flying.
	if global_position.distance_to(sync_position) > SNAP_DISTANCE:
		global_position = sync_position
	else:
		global_position = global_position.lerp(sync_position, weight)
	rotation.y = lerp_angle(rotation.y, sync_yaw, weight)

	# The crouch it does in its hideout: a scale on the model, eased the same way
	# the body is so that it squeezes down rather than snapping flat.
	var wanted: Vector3 = CROUCH_SCALE if sync_crouched else Vector3.ONE
	model.scale = model.scale.lerp(wanted, weight)

	if _pinned and sync_state != State.DEAD:
		_struggle_in_place(delta)
		return
	_draw_remote_animation()

## The animation a watched rat plays. It follows the same rule the host's does
## (`_update_animation`) — the speed decides, not the state — with the one
## addition that a rat the host has killed topples where it stands.
func _draw_remote_animation() -> void:
	# Same trap as `_update_animation`, from the other side of the wire: a watched
	# sprayer is publishing a speed of zero, so it would be drawn standing about
	# while it is actually winding up to spray somebody.
	if sync_state == State.SPRAYING:
		if animator.current_animation != ANIM_ATTACK:
			animator.speed_scale = 1.0
			animator.play(ANIM_ATTACK, BLEND)
		return
	if sync_state == State.DEAD:
		if animator.current_animation != ANIM_DEATH:
			animator.speed_scale = 1.0
			animator.play(ANIM_DEATH, BLEND)
		return
	if sync_speed < IDLE_SPEED:
		_play_idle()
		return
	if animator.current_animation != ANIM_RUN:
		animator.play(ANIM_RUN, BLEND)
	animator.speed_scale = clampf(sync_speed / CYCLE_SPEED, MIN_CADENCE, MAX_CADENCE)

## A rat in somebody's hand, drawn on a machine that is not thinking for it.
##
## The whole of the difference between this and the host's own capture is *where*
## the animal hangs, and the answer depends on who is holding it:
##
## - **Us.** It goes in the middle of our screen, exactly where our own catch
##   would go: a child of `Head/CapturePoint`, filling the frame. This is the
##   case that makes a guest's catch feel like a catch at all — without it he
##   would watch his rat being held by a body he is standing inside.
## - **Somebody else.** It hangs at his avatar's chest, and we watch a man
##   carrying a rat.
##
## Either way it is *parented* rather than chased, which is the same trick the
## host's capture turns and for the same reason: a rat glued to a moving camera
## by its transform lags a frame behind every swing, and a rat that is a child of
## it cannot lag at all.
##
## The struggle is not replicated and is not meant to be. What crosses is that
## the animal is held and whether it is dead; the trembling and the kicking are
## rolled locally from the same functions the host rolls them from, so the two
## machines show the same animal doing the same *kind* of thing without a packet
## per twitch. Nobody can tell one thrash from another, and it is not worth the
## wire.
func _draw_remote_capture(delta: float) -> void:
	var point := _capture_point_of(sync_holder)
	if point == null:
		# The body it should hang off is not up yet — an avatar still waiting for
		# its first packet, or a player who has just dropped. It is left where it
		# was rather than snapped to the floor: the holder is a moment away, and
		# a rat that flickers onto the ground and back into a hand reads worse
		# than one that hangs still for a frame.
		return

	# **Nothing is ever reparented here, our own catch included.** A node's path
	# is its address on the wire, and this rat's is the host's to write to: moved
	# under our camera it becomes `Player/Head/CapturePoint/Rat_1`, a path that
	# exists on no other machine. The host's packets stop landing — and, worse,
	# so do ours going the other way, because a guest's `_request_escape`,
	# `_request_kill` and `_request_squeeze` are all addressed by that same path.
	# Reparenting our own catch is what used to leave a guest unable to let go of
	# a rat at all: he stopped clicking, the hand opened on his side, the request
	# never arrived, and the animal stayed in his fist for the rest of the hunt.
	#
	# So a watched rat is *always* carried by its transform (`_place_in_hand`),
	# whoever is holding it. It costs a frame of chasing on our own camera and it
	# keeps the rat reachable, which is not a trade worth thinking about twice.
	if not _held_remotely:
		# The first frame we have heard of this catch. The rat arrives in the
		# hand rather than flying to it: the rise is the holder's own gesture,
		# played out on the machine that thinks for the rat, and by the time a
		# watcher hears about the catch at all the animal is usually already up.
		# Animating a second, later rise would only put the rat in two places.
		_capture_time = 0.0
		_struggle = 1.0
		_kick_time = randf_range(KICK_INTERVAL.x, KICK_INTERVAL.y)
		var pose := Basis.from_euler(_radians(HELD_POSE))
		_place_in_hand(point, Transform3D(pose, _anchor(pose)))
	_held_remotely = true
	visible = true

	_capture_time += delta
	if sync_state == State.DEAD or _remote_limp:
		# Dead in the hand: it stops fighting and hangs. The crushing itself is
		# the holder's own gesture and is not drawn here — what a watcher sees is
		# the animal go limp in his fist and then burst, which is what happens
		# and which arrives as its own message (`_burst_elsewhere`).
		_remote_limp = true
		_damp_jolt(delta)
		var hanging := Basis.from_euler(_radians(LIMP_POSE))
		var here := _remote_held_transform(point)
		var limp := Basis(here.basis.get_rotation_quaternion().slerp(
			hanging.get_rotation_quaternion(), minf(delta * 9.0, 1.0)))
		var offset := here.origin.lerp(_anchor(limp) + Vector3(0.0, -0.12, 0.05),
			minf(delta * 6.0, 1.0))
		_place_in_hand(point, Transform3D(limp, offset))
		if animator.current_animation != ANIM_DEATH:
			animator.speed_scale = 1.0
			animator.play(ANIM_DEATH, BLEND)
		return

	# Alive and fighting: the same thrash the host draws, rolled here.
	if animator.current_animation != ANIM_RUN and animator.current_animation != ANIM_ATTACK:
		animator.play(ANIM_RUN, BLEND)
		animator.speed_scale = STRUGGLE_CADENCE
	_struggle = lerpf(BASE_STRUGGLE, _struggle, pow(STRUGGLE_DAMPING, delta))
	_damp_jolt(delta)
	_kick_time -= delta
	if _kick_time <= 0.0:
		_kick_time = randf_range(KICK_INTERVAL.x, KICK_INTERVAL.y)
		_kick(1.0)
	var t := _capture_time
	var tremor := Vector3(
		sin(t * 27.0) * 0.6 + sin(t * 41.0) * 0.4,
		sin(t * 33.0 + 1.3) * 0.5 + sin(t * 19.0) * 0.5,
		sin(t * 23.0 + 2.1)
	) * TREMOR * _struggle
	var spin := Vector3(
		sin(t * 21.0) * 0.5,
		sin(t * 17.0 + 0.7),
		sin(t * 29.0 + 2.2) * 0.7
	) * deg_to_rad(TREMOR_ANGLE) * _struggle
	var held := Basis.from_euler(_radians(HELD_POSE) + spin + _jolt_spin)
	_place_in_hand(point, Transform3D(held, _anchor(held) + tremor + _jolt))
	model.scale = model.scale.lerp(Vector3.ONE, minf(delta * 9.0, 1.0))

## Puts a watched rat in a hand, in that hand's coordinates. It is left where it
## is in the tree and placed in the world instead — for every hand, our own
## included; see `_draw_remote_capture` for why nothing here may be reparented.
func _place_in_hand(point: Node3D, local_transform: Transform3D) -> void:
	global_transform = point.global_transform \
		* local_transform.scaled_local(_held_scale(sync_holder))

## Where a watched rat sits in the coordinates of the hand holding it, whichever
## way it is being held. The watcher's counterpart to `_held_transform`.
func _remote_held_transform(point: Node3D) -> Transform3D:
	return point.global_transform.affine_inverse() * global_transform

## Back out of a hand, on a machine that was only watching. It undoes exactly
## what `_draw_remote_capture` did — the pose and the limp latch — so that a rat
## which got loose goes back to being eased across the floor like any other.
##
## There is no parent to put back: a watched rat is never reparented into a hand,
## whoever is holding it (`_draw_remote_capture`), so it has been hanging where
## it always hung and only its transform was being written.
func _release_remote_capture() -> void:
	if not _held_remotely:
		return
	_held_remotely = false
	_remote_limp = false
	# Back on its feet, and back to its own size: it was hanging nose-down in
	# somebody's fist a frame ago, drawn at `HELD_SCALE`.
	rotation = Vector3(0.0, rotation.y, 0.0)
	scale = Vector3.ONE
	global_position = sync_position

## The first packet: the rat stops being a rumour and becomes a body. Snapped
## rather than eased, because there is nothing yet to ease from — and this is
## also where the coat is painted, the fur index having crossed on the spawn.
func _on_synchronized() -> void:
	if _seen:
		return
	_seen = true
	global_position = sync_position
	rotation.y = sync_yaw
	# The breed first, then the coat off the breed's own list of furs. A guest
	# that painted before adopting would read the index into whatever species the
	# scene happened to be dressed with.
	if sync_species >= 0 and sync_species < SPECIES.size():
		species = SPECIES[sync_species]
	_apply_fur(sync_fur)
	visible = true

# --- Looks and animation ---------------------------------------------------

## Gives this rat one of its species' furs, without touching the material the
## others share. A species with no fur at all keeps the model's material.
##
## The material it starts from is whatever is in place: the model's, or the PS1
## one if there is a `PS1MaterialApplier` on the `Mesh`. Since the applier runs
## in its own `_ready` — a child, therefore before the rat's `_ready` — the fur
## swap always happens afterwards, and it is the one that sticks.
## Which of the species' furs this animal was born with, as an index. The roll
## is the host's and the index is what crosses the wire (`sync_fur`): the texture
## itself could not cross, and rolling again on each machine would give the same
## rat a different coat on every screen.
##
## `-1` for a species with no furs, which leaves the model's own material alone.
func _roll_fur_index() -> int:
	if species == null or species.furs.is_empty():
		return -1
	return randi() % species.furs.size()

## Paints the coat picked by `_roll_fur_index`, wherever the index came from —
## our own roll on the host, or the wire on a guest.
func _apply_fur(index: int) -> void:
	if index < 0 or species == null or index >= species.furs.size():
		return
	var fur: Texture2D = species.furs[index]
	if fur == null:
		return

	var current := mesh.get_surface_override_material(0)
	if current == null:
		current = mesh.mesh.surface_get_material(0)

	var material := current.duplicate()
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("albedo", fur)
	elif material is BaseMaterial3D:
		(material as BaseMaterial3D).albedo_texture = fur

	mesh.set_surface_override_material(0, material)

## The animation follows the speed, not the state: wandering it trots, fleeing it
## bolts, and standing still or hidden it goes back to the idle.
func _update_animation() -> void:
	# A spraying rat is standing perfectly still, and the clip is picked below off
	# how fast it is going — so without this the attack it was told to play is
	# swapped for the idle on the very next frame and the wind-up the player is
	# supposed to read never appears. `_change_state` owns the animation while the
	# animal is planted.
	if _state == State.SPRAYING:
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed < IDLE_SPEED:
		_play_idle()
		return
	if animator.current_animation != ANIM_RUN:
		animator.play(ANIM_RUN, BLEND)
	animator.speed_scale = clampf(flat_speed / CYCLE_SPEED, MIN_CADENCE, MAX_CADENCE)

## Idle and sniff count as the same thing: while either of the two is playing the
## animation is not swapped. That way the sniff finishes in peace and runs
## straight back into the idle.
func _play_idle() -> void:
	if animator.current_animation == ANIM_IDLE or animator.current_animation == ANIM_SNIFF:
		return
	animator.speed_scale = 1.0
	if randf() < SNIFF_CHANCE:
		animator.play(ANIM_SNIFF, BLEND)
		animator.queue(ANIM_IDLE)
	else:
		animator.play(ANIM_IDLE, BLEND)

# --- Death -----------------------------------------------------------------

## Death on the game's books, whether it happens on the ground or in the player's
## hand: the rat leaves the tally of the living, stops being able to take a hit,
## records what it died of and tells whoever is listening. It pays nothing —
## paying belongs to `_pay_reward`.
func _record_death(type: Death.Type) -> void:
	_death_type = type
	# A rat that dies in somebody's hand was killed by whoever is holding it, and
	# there is no blow to carry a name. It is latched here rather than read at
	# paying time because the two are a whole gesture apart — the body still has
	# to be crushed and come apart — and by then there is no hand on it.
	if _holder_peer != 0:
		_killer_peer = _holder_peer
	remove_from_group("rats")
	# It leaves the rats' layer so it cannot be hit again. The mask stays: the
	# carcass still needs to find the ground.
	set_deferred("collision_layer", 0)
	died.emit(self, type)

## Closes this rat's account, once and only once. It applies when its hunt has
## ended, and each death ends somewhere: strangled, at the player's waist; killed
## from a distance, where the body fell. Escaping the hand closes no account at
## all.
##
## **The money goes to whoever earned it, and that need not be this machine.**
## Every rat is thought for by the host, so every death is decided there — but a
## rat strangled by a guest was that guest's work, and paying the host for it
## would be the plainest kind of wrong. `_killer_peer` is who it was, carried
## from the blow that landed (`_die`) or from the hand that held it
## (`_holder_peer`), and `Wallet.credit` is what puts it in the right pocket.
func _pay_reward() -> void:
	if _paid:
		return
	_paid = true
	Wallet.credit(_killer_peer, species, _death_type, _size)

## Drops dead where it stood, upright in the world. `leap` is the little hop the
## body makes as it takes the hit. Whatever dies strangled does not come through
## here: it vanishes at the player's waist, leaving no carcass.
func _die(origin: Vector3, leap := 3.0, type := Death.Type.UNKNOWN,
		killer := 0) -> void:
	# Whose kill it was, as the wire counts people. Zero is nobody in particular
	# — a rat that fell down a hole, or one killed by something that does not
	# belong to a player — and `_pay_reward` reads it as "the machine that is
	# deciding", which for anything without an owner is the right answer.
	if killer != 0:
		_killer_peer = killer
	unpin()
	_state = State.DEAD
	_record_death(type)
	# Killed from a distance, the body falls and the job ended right there: it
	# pays on the spot.
	_pay_reward()

	velocity = Vector3.UP * leap
	if origin != INVALID_POINT:
		velocity += _away_from(origin) * knockback_force

	# The splash of the blow landing, thrown back the way the blow came from —
	# which is what blood does when something is hit, and what puts the spray
	# between the animal and whoever swung. A fraction of the burst that goes off
	# in the fist (`HIT_SPRAY`): the body is still a body here.
	var splash := Vector3.UP if origin == INVALID_POINT else _away_from(origin) * -1.0 + Vector3.UP
	var at := global_position + Vector3.UP * BODY_CENTER.y
	_spray(at, splash, HIT_SPRAY)
	if _is_authority():
		_burst_elsewhere.rpc(at, splash, HIT_SPRAY)

	animator.speed_scale = 1.0
	# The death animation does not repeat: it topples the rat and holds the last
	# frame.
	animator.play(ANIM_DEATH, BLEND)

	# Undoes the hideout crouch, if it died hidden.
	var tween := create_tween()
	tween.tween_property(model, "scale", Vector3.ONE, 0.2)

	# A body somebody has a claim on does not go anywhere. It lies in the thing
	# that killed it until whoever owns it is done — which, for a mousetrap, is
	# the day the player comes and cleans it out (`release_carcass`).
	if is_held():
		return
	_vanish()

## The carcass going: it holds the ground a moment longer and then shrinks away.
## Every rat killed at a distance ends here — the ones nobody claimed, on their
## own clock, and the ones somebody did, on his.
func _vanish() -> void:
	var tween := create_tween()
	tween.tween_interval(CARCASS_TIME)
	tween.tween_property(model, "scale", Vector3(0.02, 0.02, 0.02), 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

# --- Utilities -------------------------------------------------------------

func _direction_to(point: Vector3) -> Vector3:
	var direction := point - global_position
	direction.y = 0.0
	return direction.normalized()

func _away_from(point: Vector3) -> Vector3:
	if point == INVALID_POINT:
		return -global_basis.z
	var direction := global_position - point
	direction.y = 0.0
	if direction.is_zero_approx():
		return -global_basis.z
	return direction.normalized()

## The way out with everybody in the house taken into account: each hunter pushes
## the rat away from himself, and the nearer he is the harder he pushes.
##
## The weight is the inverse of the distance, which is what makes a man at arm's
## length count for more than one across the room without either of them being
## ignored. Cornered between two, the sum points at the gap between them — which
## is the only way out there is, and the one a rat takes.
##
## With one hunter it comes out as `_away_from` did and always will: one term in
## the sum, normalised, is the direction away from him. So a solo hunt is not a
## different code path, it is this one with a list of length one.
func _away_from_hunters() -> Vector3:
	var push := Vector3.ZERO
	for hunter in _hunters():
		var away := global_position - hunter.global_position
		away.y = 0.0
		var distance := away.length()
		if distance < 0.01:
			# Standing on top of the rat: there is no direction to be had from
			# him, and normalising this would be a division by nothing. Whoever
			# else is about decides, and if nobody is, the fallback below does.
			continue
		push += away / (distance * distance)
	if push.is_zero_approx():
		# Nobody to run from, or everybody standing on it. Straight ahead, which
		# is what `_away_from` answers in the same corner.
		return -global_basis.z
	return push.normalized()

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
