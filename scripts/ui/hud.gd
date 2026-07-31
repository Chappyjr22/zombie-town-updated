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

@onready var crosshair: Crosshair = $Crosshair
@onready var ammo_label: Label = $AmmoPanel/Ammo
@onready var weapon_label: Label = $AmmoPanel/WeaponName
@onready var health_bar: ProgressBar = $HealthPanel/HealthBar
@onready var health_label: Label = $HealthPanel/HealthValue
@onready var weapon_toast: Label = $WeaponToast

var _toast_remaining := 0.0
## Magazine size of the held weapon, so the ammo readout knows what "low" means.
var _current_magazine := 0


func _ready() -> void:
	weapon_toast.modulate.a = 0.0


## Wires the HUD to a player. Called by the player itself, so the HUD stays a
## passive view that never has to go looking for its data source.
func bind_player(player: Node, weapon_controller: WeaponController) -> void:
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if weapon_controller == null:
		return
	weapon_controller.ammo_changed.connect(_on_ammo_changed)
	weapon_controller.weapon_changed.connect(_on_weapon_changed)
	weapon_controller.aim_changed.connect(crosshair.set_aiming)
	weapon_controller.fired.connect(crosshair.pulse)
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


func _process(delta: float) -> void:
	if _toast_remaining <= 0.0:
		return
	_toast_remaining -= delta
	weapon_toast.modulate.a = clampf(_toast_remaining / WEAPON_TOAST_FADE, 0.0, 1.0)


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
