extends Control
class_name Hitmarker

## The four-tick X that flashes over the crosshair when a shot connects.
##
## It exists because hitscan gives no other feedback: the shot is instant, the
## zombie is often behind other zombies, and without this the player can't tell a
## hit from a miss. Turning it red on a kill is what makes it worth having twice
## over - it reads as "that one's down" without a kill feed.
##
## Drawn rather than textured so it stays crisp at any resolution, matching how
## crosshair.gd works.

## Ticks sit at 45 degrees so they frame the crosshair's own cross rather than
## overlapping it, which is what makes both readable at once.
const TICK_INNER := 5.0
const TICK_OUTER := 12.0
const TICK_WIDTH := 2.0

const HIT_COLOUR := Color(1.0, 1.0, 1.0)
## The old build's `--blood`. A kill reads differently from a hit at a glance.
const KILL_COLOUR := Color(0.639, 0.137, 0.118)

## Long enough to register at a glance, short enough not to smear across
## automatic fire.
const HIT_DURATION := 0.16
const KILL_DURATION := 0.30

var _remaining := 0.0
var _duration := HIT_DURATION
var _colour := HIT_COLOUR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func flash(killed: bool) -> void:
	_colour = KILL_COLOUR if killed else HIT_COLOUR
	_duration = KILL_DURATION if killed else HIT_DURATION
	_remaining = _duration
	modulate.a = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	# Fades out rather than blinking off, so rapid fire reads as a sustained
	# marker instead of a strobe.
	modulate.a = clampf(_remaining / _duration, 0.0, 1.0)


func _draw() -> void:
	var centre := size * 0.5
	for diagonal in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var direction: Vector2 = diagonal.normalized()
		draw_line(
			centre + direction * TICK_INNER,
			centre + direction * TICK_OUTER,
			_colour,
			TICK_WIDTH,
			true
		)
