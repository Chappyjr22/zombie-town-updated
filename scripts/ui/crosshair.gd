extends Control
class_name Crosshair

@export var color := Color(0.95, 0.97, 1.0, 0.95)
@export var outline_color := Color(0.02, 0.025, 0.035, 0.9)
@export var line_length := 8.0
@export var line_thickness := 2.0
@export var hip_gap := 7.0
@export var ads_gap := 3.0
@export var movement_expansion := 5.0
@export var recoil_expansion := 4.0
@export var transition_speed := 30.0
@export var recoil_recovery_speed := 15.0

var movement_amount := 0.0
var recoil_amount := 0.0
var displayed_gap := hip_gap
var is_aiming := false
## True first person - see Player.toggle_perspective(). Aiming in first
## person lines the camera up with the weapon's own sight
## (WeaponController._update_ads_sight_alignment()), so a screen-centre
## reticle drawn on top of it would be redundant at best and visibly
## misaligned with the actual sight picture at worst - hidden rather than
## drawn alongside it. Third-person ADS still has nothing else to aim by, so
## it keeps the reticle.
var is_first_person := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _process(delta: float) -> void:
	recoil_amount = move_toward(recoil_amount, 0.0, recoil_recovery_speed * delta)
	var base_gap := ads_gap if is_aiming else hip_gap
	var target_gap := base_gap + movement_amount * movement_expansion + recoil_amount
	displayed_gap = move_toward(displayed_gap, target_gap, transition_speed * delta)
	queue_redraw()


func set_movement_amount(value: float) -> void:
	movement_amount = clampf(value, 0.0, 1.0)


func set_aiming(value: bool) -> void:
	is_aiming = value


func set_first_person(value: bool) -> void:
	is_first_person = value


func pulse() -> void:
	recoil_amount = maxf(recoil_amount, recoil_expansion)


func _draw() -> void:
	if is_aiming and is_first_person:
		return
	var center := size * 0.5
	var segments := [
		[
			center + Vector2(-displayed_gap - line_length, 0.0),
			center + Vector2(-displayed_gap, 0.0),
		],
		[
			center + Vector2(displayed_gap, 0.0),
			center + Vector2(displayed_gap + line_length, 0.0),
		],
		[
			center + Vector2(0.0, -displayed_gap - line_length),
			center + Vector2(0.0, -displayed_gap),
		],
		[
			center + Vector2(0.0, displayed_gap),
			center + Vector2(0.0, displayed_gap + line_length),
		],
	]
	for segment in segments:
		draw_line(
			segment[0],
			segment[1],
			outline_color,
			line_thickness + 2.0,
			true
		)
		draw_line(segment[0], segment[1], color, line_thickness, true)
	draw_circle(center, 1.5, outline_color)
	draw_circle(center, 0.75, color)
