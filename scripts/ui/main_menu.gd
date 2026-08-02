extends Control
class_name MainMenu

## The only screen you reach on launch (`project.godot`'s run/main_scene) and
## the only place "Retry"/"Main Menu" from the game-over screen (`hud.gd`)
## return to. No host/join flow yet - scripts/networking isn't built - so
## "Start" always begins a fresh solo run.

const LEVEL_PATH := "res://scenes/levels/town.tscn"

@onready var start_button: Button = $StartButton
@onready var last_run_label: Label = $LastRunLabel


func _ready() -> void:
	# A run that just ended left the mouse captured for gameplay - the button
	# below isn't clickable until that's undone.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_button.pressed.connect(_on_start_pressed)
	start_button.grab_focus()
	if GameState.has_last_run:
		last_run_label.visible = true
		last_run_label.text = "Last run: Round %d  ·  %s points  ·  %d kills" % [
			GameState.last_round_reached,
			_group_digits(GameState.last_points),
			GameState.last_kills,
		]
	else:
		last_run_label.visible = false


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_PATH)


## Matches HUD._group_digits() - kept as its own copy rather than a shared
## util for two call sites this small.
func _group_digits(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-" if value < 0 else "") + grouped
