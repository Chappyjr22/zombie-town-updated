extends Area3D
class_name PowerUpDrop

## A power-up dropped by a killed zombie - ported from zombie-town-online's
## DROPS/buffs/maybeDrop() (see scripts/ai/CLAUDE.md for the drop-chance roll,
## owned by RoundDirector since it needs the shared kill counter). Unlike
## every other economy fixture, this is walked into rather than pressed E on -
## matches the source's own contact pickup - so it doesn't extend
## Interactable at all.
##
## Visuals are a plain glowing primitive + a text label, not a port of the
## source's own per-kind sculpted models (a skull for Insta-Kill, an ammo
## crate for Max Ammo, etc.) - that's the same "no visual feedback while
## building it" problem the wonder-weapon models had, and the user's call
## there was to skip it. Color and label are enough to read at a glance from
## across a room, which is the only job this actually has.

const LIFETIME := 26.0
const PICKUP_RADIUS := 1.9
const BOB_HEIGHT := 0.15
const BOB_SPEED := 3.0
const SPIN_SPEED := 1.55

const KIND_DATA := {
	&"maxammo": {"label": "MAX\nAMMO", "color": Color(0.847, 0.847, 0.290)},
	&"instakill": {"label": "INSTA\nKILL", "color": Color(0.847, 0.227, 0.227)},
	&"doublepoints": {"label": "2x\nPOINTS", "color": Color(0.290, 0.541, 0.847)},
	&"nuke": {"label": "NUKE", "color": Color(0.541, 0.290, 0.847)},
	&"firesale": {"label": "FIRE\nSALE", "color": Color(0.290, 0.847, 0.541)},
}

@export var kind: StringName = &"maxammo"

var _life := LIFETIME
var _phase := 0.0
var _base_y := 0.0
var _collected := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.ACTORS
	body_entered.connect(_on_body_entered)
	_phase = randf() * TAU
	_base_y = position.y

	var data: Dictionary = KIND_DATA.get(kind, KIND_DATA[&"maxammo"])
	var color: Color = data.color

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.56
	mesh.mesh = sphere
	mesh.material_override = material
	add_child(mesh)

	var label := Label3D.new()
	label.text = data.label
	label.pixel_size = 0.006
	label.modulate = Color(1, 1, 1, 1)
	label.outline_size = 6
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0.5, 0)
	add_child(label)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.4
	light.omni_range = 6.0
	light.shadow_enabled = false
	add_child(light)

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = PICKUP_RADIUS
	shape.shape = sphere_shape
	add_child(shape)


func _process(delta: float) -> void:
	_life -= delta
	rotate_y(delta * SPIN_SPEED)
	position.y = _base_y + sin(Time.get_ticks_msec() / 1000.0 * BOB_SPEED + _phase) * BOB_HEIGHT
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	_apply(body)
	queue_free()


func _apply(player: Node) -> void:
	match kind:
		&"maxammo":
			var controller: WeaponController = player.weapon_controller
			if controller:
				controller.refill_all_ammo()
		&"instakill":
			player.instakill_remaining = player.POWER_UP_DURATION
		&"doublepoints":
			player.doublepoints_remaining = player.POWER_UP_DURATION
		&"firesale":
			player.firesale_remaining = player.POWER_UP_DURATION
		&"nuke":
			var killed_any := false
			for zombie in get_tree().get_nodes_in_group("zombies"):
				if zombie.has_method("is_dead") and zombie.is_dead():
					continue
				if zombie.has_method("take_damage"):
					zombie.take_damage(999999.0)
					killed_any = true
			if killed_any:
				player.award_points(400)
