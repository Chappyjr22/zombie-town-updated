class_name FireLight
extends OmniLight3D
## Flickering point light for fire props (fountain, fire barrels). Formula
## ported from zombie-town-online's per-frame flame update: intensity is the
## base energy modulated by two out-of-phase sine waves, which reads as an
## irregular flicker rather than a uniform pulse.

@export var base_energy: float = 1.0
@export var flicker_speed: float = 13.0
@export var flicker_amount: float = 0.14

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	light_energy = base_energy * (0.82 + sin(_t * flicker_speed) * flicker_amount + sin(_t * 7.1) * 0.08)
