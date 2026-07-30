extends Resource
class_name WeaponData

@export var display_name: String = ""
@export var model_scene: PackedScene
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var damage: float = 25.0
@export var fire_rate: float = 8.0 ## rounds per second
@export var is_automatic: bool = true
@export var mag_size: int = 30
@export var reload_time: float = 2.0
@export var range: float = 120.0
@export var starting_reserve_ammo: int = 90
