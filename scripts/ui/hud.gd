extends CanvasLayer
class_name HUD

## In-game heads-up display: health, ammo, and the current weapon.
##
## Purely a view. It owns no game state and never reaches into the player or the
## weapon - everything arrives through signals, so the HUD can be removed or
## replaced without touching gameplay, and a future spectator or second local
## player can bind its own instance to a different source.

## How long the weapon name stays up after a switch before fading out.
const WEAPON_TOAST_SECONDS := 1.6
const WEAPON_TOAST_FADE := 0.4

## Ammo turns amber under this fraction of a magazine, and red when the magazine
## is empty, so the state is readable without counting digits.
const AMMO_LOW_FRACTION := 0.3
const AMMO_NORMAL_COLOUR := Color(0.94, 0.95, 0.98)
const AMMO_LOW_COLOUR := Color(1.0, 0.78, 0.35)
const AMMO_EMPTY_COLOUR := Color(1.0, 0.42, 0.38)

const HEALTH_HIGH_COLOUR := Color(0.55, 0.82, 0.5)
const HEALTH_LOW_COLOUR := Color(0.9, 0.32, 0.3)

## Loadout strip: dim for a carried-but-not-held weapon, bright for the one
## actually in hand - the same relationship WeaponName/Ammo already draw full
## bright versus this being a secondary readout.
const LOADOUT_SLOT_COLOUR := Color(0.68, 0.72, 0.78, 0.55)
const LOADOUT_SLOT_ACTIVE_COLOUR := Color(0.96, 0.97, 1.0, 1.0)

## Short display names for scripts/economy/perk_machine.gd's six keys - kept
## here rather than read off the machine that granted the perk, since
## grant_perk() only ever carries the key and the set of keys is a closed,
## fixed table (see scripts/economy/CLAUDE.md), not something a machine could
## introduce a new one of at runtime.
const PERK_DISPLAY := {
	&"jugg": "JUGGERNOG",
	&"speed": "SPEED COLA",
	&"dtap": "DOUBLE TAP",
	&"stamin": "STAMIN-UP",
	&"mule": "MULE KICK",
	&"revive": "QUICK REVIVE",
}
const PERK_CHIP_COLOUR := Color(0.55, 0.82, 0.5, 1.0)

@onready var crosshair: Crosshair = $Crosshair
@onready var hitmarker: Hitmarker = $Hitmarker
@onready var ammo_label: Label = $AmmoPanel/Ammo
@onready var weapon_label: Label = $AmmoPanel/WeaponName
@onready var loadout_strip: HBoxContainer = $LoadoutStrip
@onready var health_bar: ProgressBar = $HealthPanel/HealthBar
@onready var health_label: Label = $HealthPanel/HealthValue
@onready var weapon_toast: Label = $WeaponToast
@onready var round_number_label: Label = $RoundPanel/RoundNumber
@onready var round_status_label: Label = $RoundPanel/RoundStatus
@onready var points_label: Label = $PointsPanel/PointsValue
@onready var points_caption: Label = $PointsPanel/PointsCaption
@onready var perk_strip: HBoxContainer = $PerkStrip
@onready var interact_prompt: Label = $InteractPrompt
@onready var downed_overlay: ColorRect = $DownedOverlay
@onready var downed_countdown: Label = $DownedOverlay/Countdown
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_stats: Label = $GameOverOverlay/GameOverStats
@onready var retry_button: Button = $GameOverOverlay/RetryButton
@onready var main_menu_button: Button = $GameOverOverlay/MainMenuButton
@onready var pause_overlay: ColorRect = $PauseOverlay
@onready var pause_resume_button: Button = $PauseOverlay/ResumeButton
@onready var pause_main_menu_button: Button = $PauseOverlay/PauseMainMenuButton

var _toast_remaining := 0.0
## Magazine size of the held weapon, so the ammo readout knows what "low" means.
var _current_magazine := 0
## Last population reported by the director, kept so the status line can be
## rebuilt when only the countdown ticks.
var _remaining_zombies := 0
var _seconds_to_next_round := 0.0
## Counts down while downed_overlay is visible - see _on_downed()/_process().
var _revive_remaining := 0.0
## Read at death for the game-over stats line - see _on_died(). Not used for
## anything else; the HUD otherwise stays signal-driven.
var _bound_player: Node = null
## Read only for its loadout array, and only in reaction to weapon_changed -
## see _refresh_loadout_strip(). Everything else about the HUD stays reactive
## to signals rather than reaching into game state on its own.
var _bound_weapon_controller: WeaponController = null


func _ready() -> void:
	weapon_toast.modulate.a = 0.0
	retry_button.pressed.connect(_on_retry_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	pause_resume_button.pressed.connect(_on_pause_resume_pressed)
	pause_main_menu_button.pressed.connect(_on_pause_main_menu_pressed)


## Wires the HUD to a player. Called by the player itself, so the HUD stays a
## passive view that never has to go looking for its data source.
func bind_player(player: Node, weapon_controller: WeaponController) -> void:
	_bound_player = player
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("points_changed"):
		player.points_changed.connect(_on_points_changed)
	if player.has_signal("interactable_changed"):
		player.interactable_changed.connect(_on_interactable_changed)
	if player.has_signal("downed"):
		player.downed.connect(_on_downed)
	if player.has_signal("revived"):
		player.revived.connect(_on_revived)
	if player.has_signal("died"):
		player.died.connect(_on_died)
	if player.has_signal("paused_changed"):
		player.paused_changed.connect(_on_paused_changed)
	if player.has_signal("perk_granted"):
		player.perk_granted.connect(_on_perk_granted)
	if player.has_signal("perspective_changed"):
		player.perspective_changed.connect(crosshair.set_first_person)
		crosshair.set_first_person(player.is_first_person)
	# Catch-up, matching the weapon/ammo catch-up below - perks start empty in
	# normal play (bind_player runs from the player's own _ready, before any
	# perk machine could have been used), but nothing here assumes that.
	for key in player.perks.keys():
		if player.perks[key]:
			_on_perk_granted(key)
	_bind_round_director(player)
	if weapon_controller == null:
		return
	_bound_weapon_controller = weapon_controller
	weapon_controller.ammo_changed.connect(_on_ammo_changed)
	weapon_controller.weapon_changed.connect(_on_weapon_changed)
	weapon_controller.aim_changed.connect(crosshair.set_aiming)
	weapon_controller.fired.connect(crosshair.pulse)
	weapon_controller.hit_confirmed.connect(_on_hit_confirmed)
	crosshair.set_aiming(weapon_controller.is_aiming)

	# Caught up by hand, because the starting weapon is equipped in the
	# controller's own _ready - which runs before this, since children are readied
	# before their parent. Without this the readouts sit on whatever placeholder
	# text the scene was saved with until the first switch.
	if weapon_controller.current_weapon != null:
		_on_weapon_changed(weapon_controller.current_weapon, weapon_controller.current_slot)
		_on_ammo_changed(weapon_controller.ammo_in_mag, weapon_controller.reserve_ammo)
		_toast_remaining = 0.0
		weapon_toast.modulate.a = 0.0


## Finds the level's round director and subscribes to it.
##
## Deferred because the director is a sibling up in the level while this HUD is
## nested inside the player scene, and which of the two is ready first depends on
## the order they happen to sit in the level's tree - a detail no one should have
## to preserve when arranging a scene. Waiting a frame makes it not matter.
##
## A level with no director is legitimate (the weapon test scenes have none), so
## the round readout just hides itself rather than warning.
func _bind_round_director(_player: Node) -> void:
	await get_tree().process_frame
	var director := get_tree().get_first_node_in_group("round_director") as RoundDirector
	if director == null:
		round_number_label.visible = false
		round_status_label.visible = false
		return
	director.round_started.connect(_on_round_started)
	director.population_changed.connect(_on_population_changed)
	director.round_timer_changed.connect(_on_round_timer_changed)
	# Catch up, in case the round started during the frame this waited out.
	if director.current_round > 0:
		_on_round_started(director.current_round, director.pending_spawns)
		_on_population_changed(director.alive_count(), director.pending_spawns)


func _process(delta: float) -> void:
	if _toast_remaining > 0.0:
		_toast_remaining -= delta
		weapon_toast.modulate.a = clampf(_toast_remaining / WEAPON_TOAST_FADE, 0.0, 1.0)
	if downed_overlay.visible:
		_revive_remaining = maxf(0.0, _revive_remaining - delta)
		downed_countdown.text = "REVIVING IN %.1fs" % _revive_remaining


func _on_interactable_changed(prompt_text: String) -> void:
	interact_prompt.visible = prompt_text != ""
	interact_prompt.text = "Press E - %s" % prompt_text if prompt_text != "" else ""


func _on_downed(duration: float) -> void:
	downed_overlay.visible = true
	_revive_remaining = duration


func _on_revived() -> void:
	downed_overlay.visible = false


## The only listener on Player.died anywhere in the project - without this the
## player just sat there, frozen, forever (that was the actual state of the
## game before this). Looks the director up fresh by group rather than caching
## it, matching how _bind_round_director()/player.gd's own _on_hit_confirmed()
## already do this lookup.
func _on_died() -> void:
	var director := get_tree().get_first_node_in_group("round_director") as RoundDirector
	var round_reached: int = director.current_round if director else 0
	var kills: int = director.kills if director else 0
	var points: int = _bound_player.points if _bound_player else 0
	GameState.record_run_end(round_reached, points, kills)
	game_over_stats.text = "Round %d  ·  %s points  ·  %d kills" % [
		round_reached, _group_digits(points), kills
	]
	game_over_overlay.visible = true
	# Gameplay captures the mouse for camera look; the buttons above aren't
	# clickable until that's released.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_paused_changed(is_paused: bool) -> void:
	pause_overlay.visible = is_paused


## Perks are only ever granted, never lost mid-round (see Player.grant_perk),
## so this only ever adds a chip - no rebuild-from-scratch needed the way the
## loadout strip's does.
func _on_perk_granted(key: StringName) -> void:
	var label := Label.new()
	label.text = PERK_DISPLAY.get(key, String(key).to_upper())
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.85))
	label.add_theme_color_override("font_color", PERK_CHIP_COLOUR)
	perk_strip.add_theme_constant_override("separation", 12)
	perk_strip.add_child(label)


## Calls back into the player rather than unpausing directly - _set_paused
## also has to release/recapture the mouse and re-emit paused_changed, and
## player.gd already owns that logic for the ui_cancel keypress that opens
## this menu in the first place.
func _on_pause_resume_pressed() -> void:
	if _bound_player:
		_bound_player.resume()


func _on_pause_main_menu_pressed() -> void:
	# Unpaused first - changing scenes while the tree is still paused would
	# hand main_menu.tscn a frozen SceneTree before it's had a chance to
	# release it itself.
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/levels/main_menu.tscn")


func _on_retry_pressed() -> void:
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/main_menu.tscn")


func _on_round_started(round_number: int, total: int) -> void:
	round_number_label.visible = true
	round_status_label.visible = true
	round_number_label.text = "ROUND %02d" % round_number
	# points_for_hit() already bakes this multiplier into every award - this is
	# purely readback, so it can't drift from what a kill is actually worth.
	var multiplier := RoundDirector.round_multiplier(round_number)
	points_caption.text = "POINTS  ·  x%.2f" % multiplier
	_remaining_zombies = total
	_refresh_round_status()


func _on_population_changed(alive: int, pending: int) -> void:
	_remaining_zombies = alive + pending
	_refresh_round_status()


func _on_round_timer_changed(seconds_left: float) -> void:
	_seconds_to_next_round = seconds_left
	_refresh_round_status()


## Reads "12 remaining" while there's work left, and switches to the countdown
## once the round is clear - which is the only time the countdown is the thing
## the player is actually waiting on.
func _refresh_round_status() -> void:
	if _remaining_zombies > 0:
		round_status_label.text = "%d remaining" % _remaining_zombies
	else:
		round_status_label.text = "clear  ·  next in %ds" % ceili(maxf(_seconds_to_next_round, 0.0))


func _on_points_changed(total: int, _delta: int) -> void:
	points_label.text = _group_digits(total)


## 12,450 rather than 12450. Points climb into five figures by the mid rounds and
## unseparated digits stop being readable in a glance at that size.
func _group_digits(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-" if value < 0 else "") + grouped


func _on_hit_confirmed(_part: StringName, killed: bool) -> void:
	hitmarker.flash(killed)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d" % roundi(maxf(current, 0.0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = HEALTH_LOW_COLOUR.lerp(
		HEALTH_HIGH_COLOUR,
		clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	)
	fill.set_corner_radius_all(2)
	health_bar.add_theme_stylebox_override("fill", fill)


func _on_ammo_changed(ammo_in_mag: int, reserve_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [ammo_in_mag, reserve_ammo]
	ammo_label.add_theme_color_override("font_color", _ammo_colour(ammo_in_mag))


func _ammo_colour(ammo_in_mag: int) -> Color:
	if ammo_in_mag <= 0:
		return AMMO_EMPTY_COLOUR
	var magazine: int = (
		1 if _current_magazine <= 0 else _current_magazine
	)
	if float(ammo_in_mag) / float(magazine) <= AMMO_LOW_FRACTION:
		return AMMO_LOW_COLOUR
	return AMMO_NORMAL_COLOUR


func _on_weapon_changed(weapon: WeaponData, slot: int) -> void:
	_current_magazine = weapon.mag_size
	weapon_label.text = weapon.display_name.to_upper()
	weapon_toast.text = "%d  %s" % [slot + 1, weapon.display_name.to_upper()]
	_toast_remaining = WEAPON_TOAST_SECONDS
	weapon_toast.modulate.a = 1.0
	_refresh_loadout_strip(slot)


## Rebuilt from scratch on every weapon_changed rather than diffed, since a
## switch is the only time the loadout can have changed too (grant_weapon()
## always equips what it just granted) and this is a handful of labels, not a
## per-frame cost. Only carried (non-null) slots show - an empty strip entry
## for every uncarried slot up to weapon_cap read as clutter more than as
## useful "you have room for one more" information.
func _refresh_loadout_strip(active_slot: int) -> void:
	for child in loadout_strip.get_children():
		child.queue_free()
	if _bound_weapon_controller == null:
		return
	loadout_strip.add_theme_constant_override("separation", 14)
	for slot in _bound_weapon_controller.loadout.size():
		var weapon: WeaponData = _bound_weapon_controller.loadout[slot]
		if weapon == null:
			continue
		var label := Label.new()
		label.text = "%d %s" % [slot + 1, weapon.display_name.to_upper()]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.035, 0.85))
		label.add_theme_color_override(
			"font_color",
			LOADOUT_SLOT_ACTIVE_COLOUR if slot == active_slot else LOADOUT_SLOT_COLOUR
		)
		loadout_strip.add_child(label)
