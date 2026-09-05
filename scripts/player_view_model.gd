class_name PlayerViewModel
extends Node3D
## The player's own arms, hanging off his camera: the only part of his body he
## is allowed to see.
##
## He is standing inside `PlayerModel` and looking out of it, so that model is
## drawn as a shadow and nothing else (`PlayerModel.set_shadows_only`). Without
## something to put in its place his hands are not in the world at all — and
## every gesture the game grows from here, a trap going down, a rat being
## squeezed, an arm going out, would happen off screen on the one machine that
## most needs to see it.
##
## This is that something: `models/hazmat_hand.glb` held up in the corner of the
## frame. There are two of them in the scene, the left being the right one
## mirrored, and only the right is drawn — see `show_left` for why, and for what
## turning the other one back on costs.
##
## ## Why a model of its own rather than the body's arms
##
## Because the body's arms were never arms. What stood here before was
## `player_model.tscn` — the same suit everybody else sees — pushed up against
## the lens with everything that was not a forearm cut out of the mesh at load,
## triangle by triangle, by skin weight. It worked, and it cost a rig-shaped
## dependency for every part of it: the cut was keyed to Mixamo bone names, the
## pose that bent the hands into frame was a `SkeletonModifier3D` fighting five
## third-person clips for control of the same bones, and the crouch needed a
## correction on top because the clip lowered arms the camera had already
## lowered. Three mechanisms, all of them there to undo an animation meant for
## somebody else's screen.
##
## The hand model is the arm alone, exported from Blender at the length it
## should read at, pointing down its own +Z. Nothing has to be cut off it and
## nothing has to be bent back into frame, so there is no rig to match and no
## clip to argue with — which is the whole reason it replaced the cut.
##
## ## Where the movement comes from
##
## From this file, and from nowhere else. The model carries no skeleton and no
## animation, so the arms are moved the way a first-person game moves them: as
## rigid objects, offset from a rest pose by what the player is doing.
##
## - **The walk** rides the same phase `player.gd` swings the camera on, handed
##   over rather than re-derived, so a hand rises on the step the view rises on
##   instead of a beat off it (`bob`).
## - **The turn** swings them behind the camera (`sway`), which is what makes
##   them read as arms attached to a man rather than as a decal on the screen.
## - **The crouch** pulls them back and down a little, on the same fraction the
##   capsule shrinks by (`set_crouch`).
## - **The grip** takes the right arm out of the corner and puts its fist on a
##   rat being strangled (`set_gripping`), with each squeeze driving it forward
##   (`punch`).
##
## The grip is the one that is a second *pose* rather than a movement, and it is
## worth saying what it is not. The hand does not close: `hazmat_hand.glb` is 56
## rigid triangles with no skeleton and no blend shapes, so there are no fingers
## to curl and no second mesh to swap to. What the arm can do is travel, and a
## fist that arrives inside the animal's silhouette reads as a grip even though
## the geometry never changed shape — which is the whole trick, and the reason
## the pose had to be photographed rather than calculated.
##
## What is deliberately *not* here is a pose per animation state. `set_state` is
## still taken and still ignored, because the player has one to give and the day
## there are first-person clips is the day it becomes useful — see there.
##
## ## Where it is drawn
##
## In the world, by the player's own camera, and not in a viewport of its own.
## That keeps the PS1 shader and the full-screen post-process working on the
## arms exactly as they work on everything else — a second camera compositing
## over the first would have to be taught both. The price is that an arm can
## clip into a wall the player is pressed against, which is what nearly every
## game of this vintage did too.

## Where each arm rests relative to the camera, before anything moves it: the
## right one's offset, with the left one taking it mirrored in `x`.
##
## `z` is negative because the camera looks down its own -Z, so this is how far
## in front of the lens the arm's origin sits. The model runs from its elbow at
## -Z to its fingertips at +Z over about 70 centimetres, and it is turned to face
## the camera's forward by `ARM_FACING` — so the origin being *behind* the lens
## is right: what is in the frame is the far half of the arm, and the near half
## is off screen behind the near plane where an elbow this close to a lens
## belongs.
@export var rest_offset := Vector3(0.26, -0.22, -0.20):
	set(value):
		rest_offset = value
		_apply()

## How each arm is turned at rest, in degrees, before the mirror.
##
## `x` tips the fingertips down towards the floor, `y` swings the arm in
## towards the middle of the frame, `z` rolls it about its own length. They are
## added to `ARM_FACING`, which is the fixed half-turn that takes the model's
## own +Z onto the camera's forward — so these read as a pose rather than as a
## coordinate correction.
@export var rest_rotation := Vector3(-12.0, 20.0, 0.0):
	set(value):
		rest_rotation = value
		_apply()

## The hand's size relative to the model's own.
##
## Under one, and it is the model rather than the taste: the arm was exported at
## the length it has on the body, about seventy centimetres from the shoulder's
## cut to the fingertips, and at eighty degrees of field of view the whole of
## that length is more arm than a man sees of his own.
##
## This and `rest_offset.z` are one setting in two numbers, and pulling them the
## same way is what fixes the arm reading as *long*: a hand further off has to
## be drawn bigger to stay legible, and a bigger hand further off is exactly the
## silhouette of a stretched arm. Bringing it in and growing it together keeps
## the hand the size it was on screen while the sleeve behind it shortens, which
## is the whole difference between a hand held up and an arm reaching out.
##
## Found by photographing the sweep rather than by arithmetic, because what is
## being judged is whether it reads as a hand.
@export_range(0.1, 2.0, 0.01) var scale_factor := 0.74:
	set(value):
		scale_factor = value
		_apply()

## The half-turn that takes the model's own forward onto the camera's.
##
## The mesh points down +Z — elbow at the back, fingers at the front, measured
## off the exported bounds — and a Godot camera looks down -Z. Without this the
## player would be shown the backs of two arms walking away from him.
##
## It is a constant rather than baked into `rest_rotation` so that the exported
## angles stay readable as a pose: dragging `rest_rotation.y` in the editor
## swings the arm in and out from the body, and it would read as neither if it
## were 180 degrees away from where it looked.
const ARM_FACING := Vector3(0.0, 180.0, 0.0)

## Whether the left hand is drawn *all the time*.
##
## Off, and the player walks around with one hand, which is what the game asks
## for while nothing is happening: a trap goes down with one hand and a corner
## of the screen is enough for it, and two gloves this close crowd the bottom of
## the frame between them with nothing to do.
##
## It is not what decides whether the second hand exists in the strangling. That
## one comes up on its own with the grip — see `_apply`, where the left is shown
## for any `_grip` above nothing. Strangling is the gesture that wants both
## hands, it is the only one the game has, and the hand arrives with the animal
## and leaves with it.
##
## So this is the knob for *always*, and turning it on is how the day comes that
## a second gesture wants a left hand at rest.
@export var show_left := false:
	set(value):
		show_left = value
		_apply()

## How far the arms swing on a step, in metres, at a full run.
##
## The vertical is twice the horizontal because that is what a walk looks like
## from inside it: an arm rises and falls with the shoulder it hangs off far
## more than it crosses the body. Both are small — this is a sway to walk to,
## not a shake, and it is drawn on top of a camera that is already swaying by
## `player.gd:bob_amount`.
@export var bob_amount := Vector2(0.012, 0.024):
	set(value):
		bob_amount = value
		_apply()

## How far the arms roll on a step, in degrees at a full run. It is what stops
## the bob reading as the whole rig being winched up and down: a real arm tips
## as it rises.
@export_range(0.0, 20.0, 0.5) var bob_roll := 3.5:
	set(value):
		bob_roll = value
		_apply()

## How far the arms lag behind the camera when the player turns, in seconds to
## cover the gap. It is the one thing here that is not a still pose: a rig
## welded to the camera reads as a decal on the screen, while one that swings a
## little behind a fast turn reads as arms attached to a man.
##
## Zero switches it off entirely, which is what the benches use — a pose that is
## still settling cannot be measured.
@export_range(0.0, 0.3, 0.005) var sway_lag := 0.06

## How far the arms are allowed to swing out on a turn, in radians. Without a
## ceiling a spin on the spot would throw them across the whole frame.
const MAX_SWAY := 0.09

## How far a turn moves the arms sideways as well as turning them, in metres per
## radian of swing. Rotation alone pivots them about the camera, which from
## inside the camera is barely visible; the slide is what actually reads.
const SWAY_SLIDE := 0.5

## Where the arms are pulled to when the player is all the way down on his
## knees, in metres — in towards his chest, and *up*.
##
## Up is the part that reads wrong until it is measured. The camera has already
## come down with the head, so an offset that is a fixed distance below the lens
## comes down with it and nothing needs correcting — except that crouching also
## brings the head forward over the knees, which shortens the arms' reach and
## drops the hands towards the bottom edge. Measured, they leave the frame
## entirely: standing they sit at 0.85 of the way down the picture, and crouched
## the same offset puts them at 1.01, which is off the bottom of it.
##
## So they are lifted by what the crouch takes off them, and pulled back towards
## the chest, which is what a man does with his arms when he folds up.
const CROUCH_PULL := Vector3(0.0, 0.05, 0.09)

## Where the right arm goes while it is holding a rat, and how it is turned
## there — the same two numbers as `rest_offset` and `rest_rotation`, for the one
## other pose the arm has.
##
## It is a second rest rather than a nudge on the first because the two are not
## the same gesture: at rest the arm hangs in the corner of the frame with the
## hand well short of anything, and holding, the fist has to sit *on* the
## animal in the middle of the screen. Interpolating between two named poses is
## what lets the hand travel there and back without either end being written as
## an offset from the other.
##
## Solved rather than eyeballed, against the geometry of the model and of the
## hold. The narrow part of the mesh — the hand, as opposed to the sleeve — runs
## from about +0.10 to +0.20 down the model's own +Z, and this puts the middle
## of that stretch up at the rat's nape: well above the capture point, because
## the animal is held head-up and the capture point is the middle of its body,
## and in front of it, because a fist round a neck is nearer the camera than the
## body hanging behind it. At `Hands.hands_distance` that lands the palm about
## twenty centimetres from the middle of the held body and a little above the
## centre of the picture, which `_test_grip.gd` measures.
##
## The palm is put *in front of* the animal rather than level with it, and that
## is the difference between a hand on a rat and a hand behind one. Level, the
## fist sits at the same distance as the body it is meant to be holding and
## perspective draws it a shade smaller than the rat is wide — so the animal
## reads as floating in front of a small far-off hand. A few centimetres nearer
## the lens and it is unmistakably the near object, which is what a fist round a
## neck is.
##
## ## In front of the rat, and above it: the two ways this goes wrong
##
## The depth was once solved by comparing two points — the palm against the
## capture point — which said the palm was seven centimetres nearer and that
## everything was well. Neither of those points is a body. The rat is nearly a
## metre of animal hung around the capture point and reaches some fifteen
## centimetres nearer the lens than the point it hangs from; the arm is seventy
## centimetres of sleeve swung across the frame at `grip_rotation`. The two
## solids interpenetrated while both points measured correct, and the renderer
## drew the animal *over* the sleeve: a rat sunk into the player's hand.
##
## The obvious repair is to push the hand forward until it clears, and it is a
## trap. It does clear — and what it buys is a fist planted square in front of
## the animal, hiding a fifth of it, with the player strangling something he can
## barely see. That reads worse than the bug it fixes, and every check in the
## bench passed it.
##
## The real constraint is that the hand cannot close. `hazmat_hand.glb` is a
## rigid block with no fingers, so it can be in front of the animal or behind it
## but never around it, and any pose that wins the depth test by sheer distance
## wins it by covering. What breaks the deadlock is not depth at all but
## *height*: put the fist up at the nape rather than across the middle of the
## body, and it holds the one part of the animal a hand closes on while the body
## hangs free below it. Same clearance, a third of the covering — eight per cent
## of the rat rather than twenty.
##
## So both halves are measured now, and they pull against each other:
## `_test_grip.gd: MAX_BEHIND` says the hand must not be drawn behind the animal,
## `MAX_HIDDEN` says it must not be drawn over it either, and each of them
## rejects the pose the other one would drift towards.
##
## Moving the *rat* forward instead was tried and is the wrong way round: it
## makes the animal larger and nearer, so it overlaps more of the sleeve and by a
## wider margin — the average went from eight centimetres of the rat in front to
## nineteen.
##
## ## The height is not a free number, and the depth paid for it
##
## `y` is not chosen at all: it is read off `Hands.hands_height`, which says how
## low the animal hangs. The rat was raised out of the bottom of the frame and
## this came up with it, because what reads as a grip is the *gap between the two
## on screen* — the fist a sixth of a frame above the point the body hangs from,
## which is where a neck is — and that gap survives either of them moving only if
## both move. It is not the same number of metres, either: the fist is a third of
## a metre from the lens and the rat is at `Hands.hands_distance`, so the same
## distance on screen is fewer centimetres for the nearer of the two.
##
## Raising the arm is what cost the depth. Both bodies went up by the same amount
## of *picture*, so nothing about the fist and the neck changed — but the sleeve
## runs from the fist back past the lens, nearly end-on, and swinging that line up
## drags a longer stretch of it across the animal. The overlap went half again as
## large and the rat came through the glove on four to six per cent of it, from
## three (`_test_grip.gd: MAX_BEHIND`), which is the failure this pose exists to
## prevent creeping back.
##
## So `z` came in from 0.395 to here — two and a half centimetres nearer the lens
## — which is the move the section above calls a trap, bought deliberately and at
## the stated price. Being nearer, the glove is drawn larger and covers more: the
## rat comes through it on under one per cent of the overlap now, and the hand
## hides eleven or twelve per cent of the animal where it used to hide eight.
## `MAX_HIDDEN` allows fourteen, so the room this spends is real and there is not
## much of it left.
##
## It is bound to `grip_rotation`, `grip_scale`, `Hands.hands_distance` and
## `Hands.hands_height`, and they were solved together: change any one of them and
## the fist comes off the animal. The bench is what says whether it is still on.
@export var grip_offset := Vector3(0.245, 0.016, -0.370):
	set(value):
		grip_offset = value
		_apply()

## How the arm is turned while it holds, in degrees, before `ARM_FACING` and the
## mirror — read the same way as `rest_rotation`.
##
## The yaw is the whole lesson of this pose, and it is nowhere near the resting
## twenty degrees. The obvious grip — reach straight down the sights and put the
## fist on the animal — was tried first and looks wrong in a way no measurement
## of the *hand* catches: the arm then points almost at the lens, so the sleeve
## is drawn end-on and foreshortens into a wide flat wedge that fills the corner
## of the screen and covers the rat the hand is supposed to be holding. Swinging
## the arm across instead, at sixty-five, shows the forearm from the side. It is
## the same fist in the same place with the sleeve now reading as a limb.
##
## It also buys the elbow: across the view it lands about 36 centimetres out,
## past the depth where the foreshortening stops mattering
## (`_test_grip.gd: ELBOW_DEPTH`), where a forearm crossing a corner is simply a
## forearm. Reaching straight ahead put it at 18 and inside the picture.
##
## Photographed rather than calculated, like `scale_factor` and for the same
## reason: the arithmetic said both poses put the hand on the rat, and only the
## pictures said which one looked like a hand.
@export var grip_rotation := Vector3(-26.0, 65.0, 0.0):
	set(value):
		grip_rotation = value
		_apply()

## How big the arm is drawn while it grips, relative to the model's own size —
## the holding counterpart of `scale_factor`.
##
## Bigger than the resting arm, and that is not a liberty. `scale_factor` is
## under one because at rest the whole length of the forearm is in shot and a
## man does not see that much of his own arm. Gripping, the sleeve mostly leaves
## the frame and what is left in it is the fist, which has to hold its own
## against an animal filling two thirds of the picture. At the resting size it
## does not: the glove comes out narrower than the rat is wide, and a hand
## smaller than the thing it is squeezing reads as a hand somewhere behind it.
##
## Measured against the animal rather than picked, and it is a ceiling as much as
## a floor. Too small and the glove comes out narrower than the rat is wide,
## which reads as a hand behind the animal — `_test_grip.gd: MIN_GLOVE_WIDTH`
## refuses that. Too large and the fist simply covers the thing it is holding,
## which `MAX_HIDDEN` refuses. Between them there is not much room: at this the
## glove is about half again the rat's width and hides an eighth of it.
##
## It came down from 1.17 when the rat was brought nearer the lens
## (`Hands.hands_distance`). Perspective grows whichever object is closer, and
## the hand is the closer one, so holding this fixed while the animal came in
## would have handed the glove more of the frame than the rat gained.
##
## It only means anything because `_apply` divides the change in size back out
## of the offset. Scaling this node moves the arm as well as growing it, and
## apparent size is width over distance — so without that division the two
## cancel exactly and this knob does nothing whatsoever, at any value. It read
## as the pose being wrong for a whole round of tuning. See `_apply`.
@export_range(0.1, 3.0, 0.01) var grip_scale := 1.05:
	set(value):
		grip_scale = value
		_apply()

## How far the far fist is held off the near one while they grip, in the same
## units as `grip_offset`.
##
## It is what keeps the two hands from being one. `_place` draws the left as the
## right mirrored, and the grip's yaw of sixty-five degrees is what brings a
## fist whose arm starts out at `grip_offset.x` back to the centre of the screen
## — so mirrored without this, both fists arrive at the *same point*, sink into
## each other and read as a single lump with two sleeves.
##
## The whole of it is spent on the far hand and none of it on the near one, for
## the reason written out in `_apply`: the near hand's pose is solved against the
## animal and moving it off the animal to make room is not a trade, it is the
## pose being given up. So this reads as *where the second hand goes*, and the
## first stays where it was photographed.
##
## It is the first-person reading of `PlayerArms.SPREAD`, and small for the same
## reason: the two hands are on either side of one neck. Bigger and the man is
## holding the rat at arm's length between two flat palms; smaller and he is
## holding it in one fist that happens to have two sleeves.
##
## Photographed rather than solved, like every other number in this pose, and it
## is the one that trades against `_test_grip.gd: MAX_HIDDEN` — two gloves cover
## more of the animal than one, and moving them apart is what buys that back.
@export_range(0.0, 0.2, 0.005) var grip_spread := 0.065:
	set(value):
		grip_spread = value
		_apply()

## Where the *far* hand sits, measured from where the mirror would put it, in
## the units of `grip_offset`. Only `y` and `z` mean anything here: the two
## hands are on either side of one neck and `grip_spread` is what says how far
## apart, so a sideways nudge on top of it would be the same knob twice.
##
## It exists because a mirror is not a second hand. Mirrored exactly, the far
## fist is drawn at the same distance from the lens as the near one, and two
## fists at the same depth either side of a neck read as one V-shaped lump with
## a sleeve running out of each end — the animal's head comes up between them
## rather than being held by them. Sending it back into the picture, and a
## little down, is what makes it the hand on the *other side* of the rat:
## partly hidden by the animal, which is what being behind something looks like
## and what tells the eye there are two of them.
##
## Small, and the depth is the half that matters. Too far back and the far hand
## disappears behind the rat entirely, which costs the second hand the whole of
## its job; too little and it is the lump again.
@export var grip_far_offset := Vector3(0.0, -0.012, 0.040):
	set(value):
		grip_far_offset = value
		_apply()

## How long the hand takes to travel between hanging and gripping, in seconds.
##
## Fast, because the grab it follows is fast: the rat is off the ground and at
## the hand in `Capture.POUNCE` plus `Capture.RISING`, a third of a second all
## told (`rat.gd`), and a hand that arrived after the animal did would read as
## the rat hauling the arm up rather than the other way about.
@export_range(0.0, 1.0, 0.01) var grip_time := 0.18

@export_group("Held item")
## Where a carried weapon sits in the hand, in the forearm's own coordinates.
##
## The forearm runs from its elbow at -Z to its fingertips at +Z over about
## seventy centimetres of model, so this is measured *along the arm*: `z` walks
## out towards the fingers and is where the fist closes, and the other two nudge
## the grip off the bone's centre line to where a hand actually wraps something.
##
## It is written here rather than on the weapon because the fist is the arm's,
## not the bat's. Every club the game grows holds at the same place in the same
## hand; what changes between one and the next is the model's own origin, and
## that is the model's business to export right.
##
## **It stays small, and the pose comes from `hold_rotation`.** The obvious way
## to get a bat out of the middle of the screen is to push it there with this,
## and it does not work: the offset moves the model's *origin*, which is the
## handle, so a bat shoved far enough out to clear the sights is a bat whose
## grip has left the hand — it hangs in the air beside a fist holding nothing.
## Measured rather than argued: 55 centimetres down the arm put the bat where it
## needed to be on screen and left the handle 32 centimetres from the glove, and
## the bench is what said so (`_test_bat.gd: HELD_REACH`). Turning it instead
## costs nothing, because a rotation pivots about the grip and the grip is
## already in the hand.
@export var hold_offset := Vector3(-0.04, 0.0, 0.26):
	set(value):
		hold_offset = value
		_place_held()

## How a carried weapon is turned in the hand, in degrees, in the forearm's own
## coordinates.
##
## The bat is modelled standing up its own +Y with the handle at the bottom, and
## the arm points down its own +Z. This is what does the whole of the carrying
## pose, and each of the three angles buys something the others cannot:
##
## - **Pitch** stands the bat up out of the arm rather than laying it along it,
##   which is the difference between carrying a club and carrying a torch.
## - **Yaw** turns it side-on to the lens, and it is the one that is easy to
##   leave out. Without it the bat points nearly down the line of sight and is
##   drawn end-on: 4% of the frame wide, a stick seen down its own length, which
##   reads as a smear rather than as a bat. At this it spans a third of the frame
##   and has a silhouette.
## - **Roll** leans the head over to the right, which is what makes the diagonal
##   a diagonal instead of a bat standing straight up in the middle of the view.
##
## Solved by measuring where the model lands in the frame rather than by eye. The
## sign of the roll was simply backwards to begin with — the bat crossed up and
## to the *left*, through the crosshair, which is the one place a carried weapon
## must never sit. Where it sits now: the handle low on the right at about two
## thirds across the frame, the head up and further right still, out past the
## edge, and nothing of it within reach of the sights.
@export var hold_rotation := Vector3(20.0, -55.0, 35.0):
	set(value):
		hold_rotation = value
		_place_held()

## How big a carried weapon is drawn relative to the model's own size.
##
## It is under one for the same reason `scale_factor` is, and it multiplies on
## top of that one: the whole rig is already scaled, and a bat exported at the
## eighty centimetres a real bat is would fill the frame from corner to corner
## at this distance from the lens. At this it covers about two fifths of the
## frame's height, cornerwise, which is a weapon the player can see he is holding
## without it being the thing he is looking at.
@export_range(0.1, 3.0, 0.01) var hold_scale := 0.50:
	set(value):
		hold_scale = value
		_place_held()

@export_group("Swing")
## How far back the arm cocks before a blow and how far through it follows, in
## degrees about the three axes of the forearm.
##
## The two are one gesture in two halves and they are not mirrors of each other:
## the wind-up is small and up, the follow-through is large and across. A swing
## that went as far back as it went forward would read as a pendulum rather than
## as a man hitting something — the weight is all in the second half.
@export var swing_wind := Vector3(24.0, -14.0, 10.0)
@export var swing_follow := Vector3(-18.0, 40.0, -34.0)
## How far the fist drives out along the arm at the end of the follow-through,
## in metres. It is what stops the swing reading as a wrist flick: the whole arm
## goes into the blow, not just the angle of it.
@export_range(0.0, 0.5, 0.005) var swing_reach := 0.12
## How long each half of the swing takes, in seconds. The wind-up is the shorter
## of the two by a good margin — a club is snatched back and then swung, and a
## slow wind-up is a swing the player has already seen coming.
@export_range(0.01, 1.0, 0.01) var swing_wind_time := 0.07
@export_range(0.01, 1.0, 0.01) var swing_follow_time := 0.13
## How long the arm takes to settle back out of the follow-through. Longer than
## either half of the blow, because it is the only part of the gesture with
## nothing chasing it — the same reason `Hands.RISE_TIME` is slower than the
## descent it undoes.
@export_range(0.01, 1.5, 0.01) var swing_recover_time := 0.26

## Where the arm takes the dead rat, and how it is turned on the way — the third
## and last of the named poses, read the same way as `rest_offset` and
## `grip_offset`.
##
## It is where the gesture the player asked for lives: the animal does not stop
## being held the moment it stops moving. It dies in the fist, the arm carries
## it down past the bottom of the frame, and comes back up without it. What used
## to happen is that the fist let go on the killing squeeze and travelled back to
## its resting corner in `grip_time` while the body took a whole second longer to
## drop to the waist under its own steam — so the last thing the player saw of a
## rat he had just strangled was it falling out of shot on its own, with his hand
## already back where it started, nowhere near it.
##
## Solved against the rat rather than picked, and that is why it is not simply
## "down": the body travels to `Rat.WAIST`, which is off to the hand's own side
## and in towards the belt, so this puts the fist where the fist was relative to
## the animal — a little in front of and above the body's middle, as in
## `grip_offset` — after the animal has arrived there. Getting it merely low
## enough reads as the arm dropping and the rat sinking through it.
##
## Below the frame, which is the point of the whole gesture: at this the glove is
## well past the bottom edge before the travel ends, so the hand that comes back
## up is unmistakably a hand that put something away rather than one that opened.
@export var stow_offset := Vector3(0.30, -0.72, -0.36):
	set(value):
		stow_offset = value
		_apply()

## How the arm is turned as it stows, in degrees, before `ARM_FACING` and the
## mirror — the same reading as `grip_rotation`.
##
## It is the grip's yaw with the pitch rolled over: the wrist turns down and in
## as the arm goes, which is what a hand does putting something at its own belt,
## and it keeps the sleeve reading as a forearm on the way out of shot the same
## way the sixty-five degrees does on the way in. The yaw is left where the grip
## had it on purpose — swinging it back towards the sights mid-descent would show
## the cut end of the mesh at the exact moment the arm is nearest the lens.
@export var stow_rotation := Vector3(26.0, 65.0, 0.0):
	set(value):
		stow_rotation = value
		_apply()

## How far the fist drives forward on a squeeze, in metres, and how long the
## thrust takes to fall away.
##
## It is the arm's half of what `SQUEEZE_RECOIL` does to the camera: the shake
## says the player felt the squeeze, and this says the hand did it. Small on
## purpose — the fist is already buried in the animal, so a big shove would take
## it out the other side.
##
## It came down from 0.035 when `SQUEEZE_CLOSE` was written. The two are one
## gesture in two directions and the forward one is the weaker of them: a man
## tightening on an animal closes his hands on it where it is, he does not
## punch it away from himself once per click.
const SQUEEZE_PUNCH := 0.025
const SQUEEZE_DAMPING := 0.0004

## How far the two fists come together at the peak of a squeeze, in the units of
## `grip_spread` — which is what it is taken off.
##
## This is the half of the squeeze that reads. The thrust above says the arm
## did something; this says *what*, because hands closing on a neck is the only
## shape a strangling has. It rides the same `_punch` that the thrust does, so
## one click is one gesture with one decay and there is no second clock to keep
## in step (`_apply`).
##
## It is `PlayerArms.SQUEEZE_CLOSE` read in first person, and it has a ceiling
## the body's version does not: it cannot be larger than `grip_spread`, or the
## fists cross over each other at the peak.
const SQUEEZE_CLOSE := 0.018

## The upper arm: a second copy of the same mesh, carrying the sleeve on from
## the forearm's cut back towards the shoulder.
##
## It exists because `hazmat_hand.glb` is a forearm and nothing else — it ends
## in a flat, open cross-section about seventy centimetres from the fingertips,
## which is a cut and not a shoulder. At rest that never showed: the arm points
## away from the camera and the cut is behind the lens, off screen, which is
## exactly where `rest_offset` puts it. Swung across the view to grip, the same
## cut turns to face the camera and is drawn as what it is — an arm ending in
## mid-air, sliced off.
##
## So the fix is not to hide the cut but to continue past it. These three put a
## second instance of the mesh with its *fingertip* end at the elbow and its own
## cut running back towards the body, which is where a real upper arm goes and
## where the frame's edge covers it.
##
## `UPPER_ROTATION` is in the forearm's own coordinates, so it is a bend at the
## elbow rather than a pose in the camera's: the upper arm follows wherever the
## forearm goes, and the joint stays a joint through the whole travel between
## hanging and gripping. It is why this is a child node rather than a third pose
## solved against the camera.
const UPPER_ROTATION := Vector3(0.0, 152.0, 0.0)
## Where the upper arm's own origin sits relative to the forearm's, in the
## forearm's coordinates: back down the length, so the two meet at the elbow
## rather than overlapping along the sleeve.
const UPPER_OFFSET := Vector3(0.0, -0.02, -0.34)
## How long the upper arm is next to the forearm. Shorter, because the part of
## it that is not off the edge of the frame is the few centimetres just past the
## elbow — drawing the whole of a second seventy-centimetre limb buys nothing
## and costs the far end poking back through the camera.
const UPPER_SCALE := 0.85

## How much of the walk's swing reaches an arm that is holding a rat.
##
## Cut down rather than switched off. A man carrying something in one fist does
## not hold it perfectly still while he walks, so nothing here would read as
## wrong for the arm alone — but the rat is drawn against the middle of the
## screen by its own capture point (`hands.gd: hands_distance`), and a hand
## swinging its full amplitude around an animal that is not swinging with it
## slides visibly through it on every step. Damping the arm is the cheaper half
## of keeping the two together.
const HELD_TRAVEL := 0.35

## The two arms, right and left. The left one is the right one with its `x`
## mirrored — offset, rotation and mesh alike — which the hand model allows
## because it was exported as one arm rather than as a pair.
@onready var _right: Node3D = $Right
@onready var _left: Node3D = $Left
## The upper arms, one under each forearm. Children of the arm they continue, so
## they inherit the whole pose and the bend at the elbow stays put through it.
@onready var _right_upper: Node3D = $Right/Upper
@onready var _left_upper: Node3D = $Left/Upper
## Where a carried weapon hangs: a child of the right forearm, so the thing in
## the fist inherits the whole pose — the grip, the stow, the bob, the sway and
## the swing alike — without any of them being solved a second time for it.
##
## Only the right arm has one. The left is the right one mirrored through a
## negative `x` scale (`_place`), and a bat carried through that mirror would be
## a bat with its grain running backwards and its winding inside out. The day a
## gesture needs both hands on the same club, it is one model spanning the two
## fists rather than two mirrored copies of it.
@onready var _hold: Node3D = $Right/Hold

## How far down the player is, from 0 standing to 1 on his knees.
var _crouch := 0.0
## Where the camera was pointing last frame, for the sway: yaw in `x`, pitch in
## `y`, in radians.
var _sway := Vector2.ZERO
## Where the player is in his walking cycle, in radians, and how much of the
## step is being applied — both handed over by `player.gd` rather than counted
## again in here. See `bob`.
var _bob_phase := 0.0
var _bob_weight := 0.0
## How far the arm is into the holding pose, from 0 hanging to 1 gripping. It is
## a fraction rather than a flag so that the hand travels to the rat instead of
## appearing on it.
var _grip := 0.0
## Which end that fraction is heading for: 1 while a rat is in the hand, 0 once
## it is out of it.
var _grip_target := 0.0
## What is left of the last squeeze's thrust, in metres along the arm.
var _punch := 0.0
## How far the hands are carried off the pose by the animal fighting them, in
## the camera's own coordinates. Handed over by `player.gd` rather than rolled
## here — see `set_grip_drift`.
var _drift := Vector3.ZERO
## How far the arm is into carrying a dead rat away, from 0 holding it in the
## middle of the screen to 1 with the fist below the frame at the belt. It rides
## on top of `_grip` rather than replacing it: the arm goes on being an arm that
## holds something for the whole of the descent, and stowing is what it does
## *with* the thing it holds.
var _stow := 0.0
## The stowing, in three counts: how long the body still hangs dead in the fist
## before the arm starts down, how long the arm takes to go, and how long it
## takes to come back up empty. All handed over by whoever killed the rat, so
## that the arm follows the body's own timing without this file learning what a
## body is (`hands.gd: stow_hand`).
var _stow_wait := 0.0
var _stow_fall := 0.0
var _stow_rise := 0.0
## Where the stowing is, in seconds from the kill. Negative when there is none.
var _stow_time := -1.0
## Where the swing is, in seconds from the click: through the wind-up, then the
## follow-through, then the settle back. Negative when the arm is not swinging.
var _swing_time := -1.0
## What the swing is doing to the arm right now, worked out from that clock: an
## angle in degrees added to whatever pose the arm is in, and a reach in metres
## along it. They are kept rather than recomputed in `_apply` because `_apply`
## runs on every sway and every step, and the swing has its own clock that only
## `advance` moves.
var _swing_angles := Vector3.ZERO
var _swing_reach := 0.0
## The weapon in the hand right now, or null with an empty fist. It is a node
## under `_hold`, taken from the models dressed there and shown one at a time —
## see `set_held_item`.
var _held: Node3D


func _ready() -> void:
	# The mesh flags are set here rather than in the scene because both arms are
	# instances of an imported GLB, whose inner nodes the editor cannot reach.
	for mesh in _meshes():
		# Nothing in here casts a shadow. The body still standing in the world is
		# the one that throws the player's shadow on the floor (`player.gd`), and
		# a second pair of arms an arm's length from the camera would throw a
		# second one across everything he looks at.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The arms sit inches from the near plane, where the engine's own culling
		# has little to work with once the rig swings on a turn. The margin is
		# generous because the whole thing is 56 triangles an arm — cheaper to
		# always draw than to ever wrongly cull.
		mesh.extra_cull_margin = 4.0
	# The bend at the elbow, set once. It is written in the forearm's own
	# coordinates and the upper arm is a child of it, so the joint holds through
	# every pose the arm takes without being recomputed on any of them.
	for upper in [_right_upper, _left_upper]:
		if upper == null:
			continue
		upper.position = UPPER_OFFSET
		upper.rotation_degrees = UPPER_ROTATION
		upper.scale = Vector3.ONE * UPPER_SCALE
	# Everything the player could ever hold is dressed in the fist at once and
	# all of it starts hidden, the way the belt starts every weapon unequipped
	# (`inventory.gd`). What comes out is whatever the weapon in hand asks for.
	_place_held()
	set_held_item(&"")
	_apply()


## What the body is doing. Taken and ignored, and it is worth saying why rather
## than dropping the call: the player has exactly one state for the body and the
## arms, and handing it to both of them is what will make a first-person clip
## line up with the third-person one the day there is art for either. Until then
## the arms are moved by what the player is doing rather than by what he looks
## like doing, and there is nothing here for a state to change.
func set_state(_state: PlayerAvatar.State) -> void:
	pass


## The suit's colour, so a man's own sleeves match the ones the others see on
## him.
##
## It has to cope with two different materials for the same reason
## `PlayerModel.set_tint` does — `PS1MaterialApplier` may have swapped the
## imported `StandardMaterial3D` for the shader by now, and on that one the
## colour is a shader parameter rather than a property. Writing to the wrong one
## fails silently and looks like a bug in `ColorManager`.
func set_tint(color: Color) -> void:
	for mesh in _sleeve_meshes():
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.get_active_material(surface)
			if material is ShaderMaterial:
				var shader_material := material as ShaderMaterial
				shader_material.set_shader_parameter(&"recolor_target", color)
				shader_material.set_shader_parameter(&"recolor_strength", 1.0)
			elif material is BaseMaterial3D:
				# The imported material is baked into the mesh, which both arms
				# share with every other instance of the model: painting it in
				# place would dress the whole van in one man's colour.
				var own := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				own.albedo_color = color.lerp(Color.WHITE, PlayerModel.TINT_WHITENING)
				mesh.set_surface_override_material(surface, own)


## The animation now running, by name. There is none — the arms are posed rather
## than animated — and the empty name is the honest answer rather than a lie
## about a clip that is not playing.
##
## It stays because the benches ask it of both bodies, and because the day the
## hands carry clips of their own this is where the answer comes from.
func current_animation() -> StringName:
	return &""


## How far down the player is, from 0 standing to 1 on his knees. Called every
## frame by the player, whose crouch this follows.
##
## It is set rather than read because the crouch is his: he is the one who works
## out whether there is room to stand up, and a second reading of the same
## question in here could disagree with his by a frame.
func set_crouch(fraction: float) -> void:
	if is_equal_approx(_crouch, fraction):
		return
	_crouch = fraction
	_apply()


## Where the player is in his step, handed over by `player.gd`.
##
## `phase` is the same angle his camera rides its sine on and `weight` the same
## fraction of a full run it is scaled by. Both are taken rather than worked out
## again in here, and that is the point of the call: an arm counting its own
## steps off the velocity would drift a frame from the view it is drawn in
## front of, and the two would visibly beat against each other.
func bob(phase: float, weight: float) -> void:
	if is_equal_approx(_bob_phase, phase) and is_equal_approx(_bob_weight, weight):
		return
	_bob_phase = phase
	_bob_weight = weight
	_apply()


## The arms, swung a little behind where the camera is pointing.
##
## `delta` is the frame, and `look` is how far the head turned this frame in
## radians — yaw in `x`, pitch in `y`. The player hands it over because he is the
## one who moved the head; reading it back off the camera here would be a frame
## late and, with the head under a body that also turns, would have to
## reconstruct which half of the turn was his.
func sway(delta: float, look: Vector2) -> void:
	if is_zero_approx(sway_lag):
		if not _sway.is_zero_approx():
			_sway = Vector2.ZERO
			_apply()
		return
	# The turn pushes the arms out, and they come back on their own. Written as a
	# rate rather than a spring because a spring would overshoot, and arms that
	# overshoot a mouse flick read as a camera fault rather than as weight.
	var wanted := Vector2(
		clampf(-look.x, -MAX_SWAY, MAX_SWAY),
		clampf(-look.y, -MAX_SWAY, MAX_SWAY)
	)
	var weight := clampf(delta / sway_lag, 0.0, 1.0)
	_sway = _sway.lerp(wanted, weight)
	if absf(_sway.x) < 0.0005 and absf(_sway.y) < 0.0005:
		_sway = Vector2.ZERO
	_apply()


## The hand closes on a rat, or opens off one.
##
## Called by the player off the weapon's own `caught` and `finished` — the hands
## are the ones that know whether there is an animal in them, and the arm is
## told rather than left to look for one. That keeps this file free of any
## notion of what a rat is, which is what it has been from the start: the arm
## knows two poses and a fraction between them, and nothing about why.
func set_gripping(gripping: bool) -> void:
	var wanted := 1.0 if gripping else 0.0
	if is_equal_approx(_grip_target, wanted):
		return
	_grip_target = wanted
	if gripping:
		# A fresh grab cancels any stowing still running. It only happens when a
		# rat is grabbed inside the second the last one takes to go down — the
		# hands hold their own click off for exactly that reason
		# (`hands.gd: _release`) — but the arm is not the place to assume it, and
		# an arm left half-stowed under a new grip would hold the next rat at the
		# belt.
		_stow_time = -1.0
		_stow = 0.0
		return
	# Whatever was left of the last squeeze goes with the rat. Without this the
	# hand would carry the thrust back to its resting place and twitch there,
	# over nothing.
	_punch = 0.0


## Carry the dead rat out of the frame: the fist waits `wait` seconds with the
## limp body in it, takes `fall` to go down to the belt, and `rise` to come back
## up empty.
##
## It is the one gesture the arm makes that outlives the thing it was made for.
## Everywhere else the hand opens the moment the rat is out of it — that is what
## `set_gripping(false)` is — and for a rat that got loose that is exactly right,
## because it left under its own power and there is nothing to carry. A rat
## strangled does not leave: it is dead in the fist, and the player is the one who
## puts it away. So this keeps the arm in its holding pose past the kill and takes
## it down along the same path the body travels, rather than opening the hand and
## letting the corpse fall out of shot beside it.
##
## The three counts are taken rather than written down here because they are the
## body's, not the arm's — the rat is the one that knows how long it goes limp for
## and how long it takes to reach the waist (`rat.gd: LIMP_TIME`, `STOW_TIME`) —
## and a second copy of them in this file is two numbers that would drift apart
## the first time either was tuned. This file still knows nothing about rats: it
## is told how long to hold, how long to go down and how long to come back.
##
## Calling it with the hand empty does nothing. The kill is announced by the
## weapon and the weapon is the only thing that can be holding a rat, but the arm
## is asked either way rather than made to trust it.
func stow_hand(wait: float, fall: float, rise: float) -> void:
	if is_zero_approx(_grip_target) and is_zero_approx(_grip):
		return
	_stow_wait = maxf(wait, 0.0)
	_stow_fall = maxf(fall, 0.0)
	_stow_rise = maxf(rise, 0.0)
	_stow_time = 0.0
	# The fist keeps the rat for the whole descent, so the holding pose stays on
	# until the arm is on its way back up. `_stow` is what carries it down.
	_grip_target = 1.0
	_grip = 1.0
	# The thrust of the killing squeeze does not ride down with the body: the arm
	# is carrying now, not squeezing.
	_punch = 0.0


## Puts a weapon in the fist, or empties it when `item` is blank.
##
## The name is the model's node under `Hold`, which is where every carriable
## weapon is dressed at once (`scenes/player_view_model.tscn`). Showing one of
## several rather than instancing what is asked for is deliberate: the models are
## a handful of PSX-era triangles apiece, they are wanted the instant the belt
## swaps and never at any other time, and a scene built on the click is a hitch
## in the middle of the one frame the player is watching the swap happen.
##
## It is the arm's business and not the weapon's because the fist is the arm's.
## The weapon says *what* it is carrying (`MeleeWeapon.held_item`) and this file
## decides where a hand holds something, which is the same decision for every
## club the game grows.
##
## Asking for a model that is not dressed empties the hand rather than failing:
## a bench running the player scene without one of the models is a bench with an
## empty fist, not a broken one.
func set_held_item(item: StringName) -> void:
	if _hold == null:
		return
	_held = null
	for child in _hold.get_children():
		var model := child as Node3D
		if model == null:
			continue
		var wanted := model.name == item
		model.visible = wanted
		if wanted:
			_held = model


## What is in the fist right now, or an empty name with nothing in it. Nothing in
## the game reads it; the bench does, which is why it is here.
func held_item() -> StringName:
	return _held.name if _held != null else &""


## One blow: the arm cocks back, swings through and settles.
##
## Taken as a call rather than read off anything, for the same reason `punch` is:
## the swing is a gesture that happens on the click, and a click that found
## nothing to hit swings exactly as far as one that did (`melee_weapon.gd`). An
## arm driven by the hit would tell the player he had missed before he had swung.
##
## A second click part way through starts the gesture over rather than queueing
## behind it. The weapon's own cadence is what stops that happening often
## (`Weapon.cooldown`), and when it does happen — a cadence shorter than the
## swing — restarting is what a man swinging fast actually looks like.
func swing() -> void:
	_swing_time = 0.0


## One squeeze, felt in the arm: the fist drives forward and settles back.
##
## Taken as a call rather than read off the pressure, because pressure also
## falls on its own while the player is not clicking (`hands.gd: decay`) and an
## arm driven by it would creep backwards through the whole hold.
func punch() -> void:
	_punch = SQUEEZE_PUNCH


## How far the animal has pulled the hands off the pose: `x` across the picture,
## `y` up it, `z` towards the lens, and in the units the rest of the pose is
## written in rather than in finished metres — the division at the end of
## `_apply` is what turns those into what the camera sees, and it has to reach
## this the same way it reaches `grip_offset`.
##
## The third-person body has the opposite arrangement and it is worth saying why
## this is not it. There, the *hold* wanders (`PlayerArms.STRUGGLE_SWING`) and
## the rat hangs off it, because the animal is drawn wherever the hands put it.
## Here the rat is the one with a mind of its own: it trembles and kicks against
## the capture point on its own account (`rat.gd: TREMOR`, `_kick`), and it does
## it in the middle of the screen where every centimetre is visible. Adding a
## second wander on top of that would be two animals fighting.
##
## So the hands follow instead. What arrives here is a fraction of the distance
## the animal has actually travelled, damped and capped by `player.gd`, and the
## fraction is the point: at nothing the fists sit still while the rat thrashes
## between them, which is what makes them read as a decal; at the whole of it
## they are welded to the animal and nobody is holding anything difficult.
##
## Zero is the resting answer and the one to hand over the moment the hands are
## empty, so that the pose does not keep the last twitch of a rat that is gone.
func set_grip_drift(drift: Vector3) -> void:
	if _drift.is_equal_approx(drift):
		return
	_drift = drift
	_apply()


## Advances the arm's own movement — the travel between hanging and gripping,
## and what is left of the last squeeze.
##
## It is its own call rather than a `_process` for the same reason everything
## else here is: the arm is posed by the player, in the player's order, after
## the body has moved and before the frame is drawn. A `_process` would run at
## some unrelated point in the frame and could pose the hand off a camera that
## had not been moved yet.
##
## It is kept out of `sway` because that one is switched off entirely when
## `sway_lag` is zero — which is what the benches do, and a bench that turns off
## the sway should still be able to watch a hand close.
func advance(delta: float) -> void:
	var moved := false

	if _stow_time >= 0.0:
		_stow_time += delta
		_stow = _stow_fraction()
		moved = true
		if _stow_time >= _stow_wait + _stow_fall + _stow_rise:
			# Back up and empty. The hand only lets go here, at the top of the
			# rise, and not at the kill: everything between the two was the arm
			# still carrying something.
			_stow_time = -1.0
			_stow = 0.0
			_grip_target = 0.0

	if not is_equal_approx(_grip, _grip_target):
		if is_zero_approx(grip_time):
			_grip = _grip_target
		else:
			_grip = move_toward(_grip, _grip_target, delta / grip_time)
		moved = true

	if not is_zero_approx(_punch):
		_punch *= pow(SQUEEZE_DAMPING, delta)
		if absf(_punch) < 0.0005:
			_punch = 0.0
		moved = true

	if _swing_time >= 0.0:
		_swing_time += delta
		_advance_swing()
		moved = true

	if moved:
		_apply()


## How far the hand is into its holding pose, from 0 hanging to 1 closed on a
## rat. Nothing in the game reads it; the bench does, which is the whole reason
## the travel is a fraction it can watch rather than a tween it cannot.
func grip() -> float:
	return _grip


## How far the arm is into carrying a dead rat away, from 0 in the middle of the
## screen to 1 below the frame. Read by the bench for the same reason `grip` is:
## the descent is a fraction it can watch rather than a tween it cannot.
func stow() -> float:
	return _stow


## How far the arm is through a blow, from 0 not swinging to 1 at the far end of
## the follow-through. Like `grip` and `stow`, it is a fraction the bench can
## watch rather than a tween it cannot — and it is the only way to ask whether
## the arm swung on a click that hit nothing.
func swing_progress() -> float:
	if _swing_time < 0.0:
		return 0.0
	var total := swing_wind_time + swing_follow_time
	if _swing_time <= total:
		if is_zero_approx(total):
			return 1.0
		return clampf(_swing_time / total, 0.0, 1.0)
	if is_zero_approx(swing_recover_time):
		return 0.0
	return 1.0 - clampf((_swing_time - total) / swing_recover_time, 0.0, 1.0)


## Works the swing's clock out into what it does to the arm: an angle to add to
## the pose and a reach to add along it.
##
## The three beats are eased apart rather than as one curve, because they are
## three different movements. The wind-up is a snatch back and it eases *in* — it
## starts slow and gathers, which is the weight of the club being taken up. The
## follow-through eases out: all of the speed is at the front, where the blow is.
## The settle is a smoothstep both ends, which is the only one of the three that
## is not a man doing something but a man having finished.
##
## The reach rides the follow-through alone. There is nothing to drive out on a
## wind-up — the fist is coming back — and the settle carries it home with the
## rest of the pose.
func _advance_swing() -> void:
	var wind := swing_wind_time
	var follow := swing_follow_time
	if _swing_time < wind:
		var t := 1.0 if is_zero_approx(wind) else _swing_time / wind
		# Eased in: the club is heavy at the start of being picked up.
		_swing_angles = swing_wind * (t * t)
		_swing_reach = 0.0
		return
	var through := _swing_time - wind
	if through < follow:
		var t := 1.0 if is_zero_approx(follow) else through / follow
		# Eased out: the speed is at the front, where the bat meets the rat.
		var eased := 1.0 - pow(1.0 - t, 3.0)
		_swing_angles = swing_wind.lerp(swing_follow, eased)
		_swing_reach = swing_reach * eased
		return
	var settling := through - follow
	if settling >= swing_recover_time:
		# Home. The clock is stopped rather than left running, so `_apply` goes
		# back to being driven by the sway and the step alone.
		_swing_time = -1.0
		_swing_angles = Vector3.ZERO
		_swing_reach = 0.0
		return
	var t := 1.0 if is_zero_approx(swing_recover_time) else settling / swing_recover_time
	var eased := smoothstep(0.0, 1.0, t)
	_swing_angles = swing_follow.lerp(Vector3.ZERO, eased)
	_swing_reach = swing_reach * (1.0 - eased)


## Puts whatever hangs in the fist where the three `hold_*` knobs say, in the
## forearm's own coordinates.
##
## It is done to the `Hold` node once rather than to each model, so a second club
## dressed beside the bat needs nothing here — and so the knobs can be dragged in
## the editor and show their answer without the scene being reloaded, which is
## why they call this from their setters.
func _place_held() -> void:
	if _hold == null:
		return
	_hold.position = hold_offset
	_hold.rotation_degrees = hold_rotation
	_hold.scale = Vector3.ONE * hold_scale


## Where the stowing is right now, from its clock: still holding through the
## wait, going down through the fall, coming back up through the rise.
##
## The two halves are eased separately and not as one curve over the whole
## gesture, because they are not one movement. Going down is a hand putting
## something away and it settles at the bottom; coming back up is a hand
## returning to where it lives, and it is the arm that leads rather than the
## weight it no longer carries.
func _stow_fraction() -> float:
	if _stow_time < _stow_wait:
		# Dead in the fist and not going anywhere yet. The rat is going limp for
		# exactly this long, and an arm that started down while the body was still
		# slumping would pull it out of the frame before the player saw it die.
		return 0.0
	var falling := _stow_time - _stow_wait
	if falling < _stow_fall:
		if is_zero_approx(_stow_fall):
			return 1.0
		return smoothstep(0.0, 1.0, falling / _stow_fall)
	var rising := falling - _stow_fall
	if is_zero_approx(_stow_rise):
		return 0.0
	return 1.0 - smoothstep(0.0, 1.0, clampf(rising / _stow_rise, 0.0, 1.0))


## Puts both arms where everything above says they are. One place does it so
## that the exported knobs, the sway, the bob, the crouch and `_ready` cannot
## disagree about where the arms are.
##
## The right hand is placed and the left is the same placement mirrored in `x`:
## the offset's `x` flips, and so do the two rotations that read as handedness —
## the yaw that swings a hand in towards the middle and the roll about its own
## length. The pitch does not, because tipping the fingers at the floor is the
## same tip on both hands.
##
## The left is placed whether or not it is drawn (`show_left`), which costs a
## transform on a hidden node and buys the mirror staying correct for free.
func _apply() -> void:
	if _right == null or _left == null:
		return
	# The arm grows as it closes on the rat. It rides the same fraction the pose
	# does, so the hand arrives at its holding size exactly as it arrives at the
	# animal rather than swelling once it is there.
	var size := lerpf(scale_factor, grip_scale, _grip)
	scale = Vector3.ONE * size

	var step := sin(_bob_phase) * _bob_weight
	# The horizontal rides at half the rate, so a full stride is one sideways
	# sweep across two vertical ones — which is what a stride is: two steps.
	var swing := sin(_bob_phase * 0.5) * _bob_weight

	# The two poses first, and everything else on top of whichever the arm is
	# between. Doing it in this order is what keeps a hand that is holding a rat
	# still able to bob, sway and crouch: the grip decides where the arm *is*,
	# and the rest of the file goes on saying how it moves from there.
	var offset := rest_offset.lerp(grip_offset, _grip)
	var pose := rest_rotation.lerp(grip_rotation, _grip)
	# And the third pose on top of the second, not beside it: stowing is
	# something the arm does while it holds, so it starts from wherever the grip
	# has the fist rather than from the resting corner. At `_stow` of zero this
	# is a lerp to itself and the holding pose is left exactly as solved.
	if not is_zero_approx(_stow):
		offset = offset.lerp(stow_offset, _stow)
		pose = pose.lerp(stow_rotation, _stow)

	# The squeeze drives the fist up its own length, which with the arm turned
	# to `pose` is not any one axis of the camera's. Taking it through the
	# rotation is what makes the thrust follow the arm instead of the screen.
	if not is_zero_approx(_punch):
		var forward := Basis.from_euler(_radians(pose + ARM_FACING)) * Vector3.BACK
		offset += forward * _punch * _grip

	# What the animal is doing to the hands. It is added to the pose rather than
	# blended with it: they are where the grip says they are, plus however far
	# the thing they are holding has dragged them (`set_grip_drift`).
	offset += _drift * _grip

	# The walk still reaches a hand that is holding something, but not in full:
	# an arm braced round an animal is a stiffer thing than one swinging free,
	# and at the full amplitude the rat visibly rides the step.
	var travel := lerpf(1.0, HELD_TRAVEL, _grip)

	offset += CROUCH_PULL * _crouch
	offset.y += step * bob_amount.y * travel
	offset.x += swing * bob_amount.x * travel
	# The turn slides the arms as well as turning them. Yaw moves them sideways
	# and pitch moves them up, both against the turn, which is the direction the
	# lag is already rotating them in.
	offset.x += _sway.x * SWAY_SLIDE
	offset.y += _sway.y * SWAY_SLIDE

	# The offsets are written in the camera's metres, but the arms hang under
	# this node and this node is scaled — so an offset handed straight down is
	# multiplied by the size on its way out. At rest that is exactly what is
	# wanted and `rest_offset` was measured with it in place; growing the arm to
	# grip, it is not, because it would carry the hand away from the lens by the
	# very factor it grew by. Apparent size is width over distance, and scaling
	# both leaves it untouched — `grip_scale` would appear to do nothing at all.
	#
	# So only the change in size is divided back out, which holds the hand where
	# the pose puts it while it grows. At `_grip` of zero this is a division by
	# one and the resting arm is left exactly as it was measured.
	offset *= scale_factor / size

	# The blow, driven out along the arm the way the squeeze is and for the same
	# reason: with the arm turned to `pose`, "along its own length" is not any one
	# axis of the camera's, and a reach written in screen coordinates would send
	# the fist somewhere else on every pose the arm is in.
	if not is_zero_approx(_swing_reach):
		var along := Basis.from_euler(_radians(pose + ARM_FACING)) * Vector3.BACK
		offset += along * _swing_reach

	var angles := pose + ARM_FACING
	angles.y += rad_to_deg(_sway.x)
	angles.x += rad_to_deg(_sway.y)
	angles.z += step * bob_roll * travel
	# The swing is added last, on top of whichever pose the arm is in. It is a
	# gesture rather than a pose, so it does not lerp with the others: a man
	# swinging a bat while crouched swings the same bat, lower down.
	angles += _swing_angles

	_place(_right, offset, angles, 1.0)

	# The far hand, which is the near one mirrored and then moved: out to its own
	# side of the neck by `grip_spread`, and back into the picture by
	# `grip_far_offset`. Both ride `_grip`, so the resting pair is an exact
	# mirror and nothing here touches a hand that is not holding anything.
	#
	# All of the spread is spent here and none of it on the near hand, which is
	# the whole reason the two are placed separately. That hand's pose is solved
	# — where the fist sits on the animal, how much of it it covers, how much of
	# it comes through the glove — and pushing it out to make room for its
	# partner takes it off the rat: measured, a few centimetres of it cost a
	# third of the overlap and took what the animal is drawn through from well
	# under one per cent of it to six (`_test_grip.gd: MAX_BEHIND`). The second
	# hand is free to move because nothing was ever solved for it.
	#
	# The closing rides `_punch` rather than a clock of its own, so the thrust
	# above and this are one gesture with one decay: the near fist drives into
	# the animal as the far one comes across to meet it. Clamped at nothing,
	# because a squeeze deeper than the gap would send one fist through the other.
	var far := offset + grip_far_offset * _grip
	far.x += maxf(grip_spread - SQUEEZE_CLOSE * (_punch / SQUEEZE_PUNCH), 0.0) * _grip
	# The left hand is placed even while it is hidden, so that turning it back on
	# shows a hand that is already where it belongs rather than one that snaps
	# into place on the next step.
	_place(_left, far, angles, -1.0)
	# The second hand belongs to the one gesture that wants two. It comes up with
	# the grip and goes down with it, so a man walking about is drawn with the one
	# hand the game is built around and a man strangling something is drawn with
	# both — see `show_left` for the knob that keeps it out at rest as well.
	_left.visible = show_left or not is_zero_approx(_grip)


## One arm, put down at `offset` turned to `angles`, mirrored when `side` is -1.
##
## The mirror is a negative `x` scale on the node rather than a second model:
## the hand was exported once, and scaling it through zero is what turns a right
## arm into a left one without a second file to keep in step with the first.
## It flips the winding of every triangle with it, which is why the imported
## material is double-sided — the exporter wrote it that way, and it has to stay
## that way for this to work.
func _place(arm: Node3D, offset: Vector3, angles: Vector3, side: float) -> void:
	arm.position = Vector3(offset.x * side, offset.y, offset.z)
	arm.rotation_degrees = Vector3(angles.x, angles.y * side, angles.z * side)
	arm.scale = Vector3(side, 1.0, 1.0)


## Every surface the view model draws, the arms and whatever is in the fist
## alike. Small and walked rather than cached because the imported scene's shape
## is the importer's business, and a cached path is a thing that breaks silently
## the day the model is re-exported.
##
## It is what the mesh flags are set off in `_ready` — nothing this close to the
## lens casts a shadow and nothing this close should ever be culled, and that is
## as true of a bat as it is of a sleeve.
func _meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for arm in [_right, _left]:
		if arm != null:
			_collect(arm, found)
	return found


## The surfaces that are the player's *suit*, which is the narrower question the
## tint asks: the arms, and not what they are carrying.
##
## The two used to be one list, and it was wrong the moment there was anything in
## the hand — the recolour walks every mesh under the arms and would have dressed
## the bat in the man's own colour, which is a bat that changes colour with whose
## hand it is in. The sleeve is the crew's uniform; a bat off the shelf is a bat.
func _sleeve_meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for arm in [_right, _left]:
		if arm == null:
			continue
		for child in arm.get_children():
			# `Hold` is the fist's contents and belongs to nobody's uniform.
			if child == _hold:
				continue
			_collect(child, found)
	return found


## A rotation written in degrees, in the radians `Basis.from_euler` wants.
func _radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))


func _collect(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, into)
