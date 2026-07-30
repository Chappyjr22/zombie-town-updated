# scripts/weapons

Owns: weapon base class, per-weapon stats/behavior (fire rate, damage, reload, hitscan/projectile), muzzle flash and impact effects.

Depends on: `assets/models/weapons` (see `ASSET_MANIFEST.md` for which models exist), `resources/weapons/*.tres` (per-weapon data).

## Status

- `weapon_data.gd` — a `Resource` (`class_name WeaponData`) holding one weapon's stats + asset references (model scene, fire/reload sounds, damage, fire rate, mag size, reload time, range). No behavior, pure data.
- `weapon_controller.gd` — a `Node3D` (`class_name WeaponController`) that equips a `WeaponData`, instantiates its model as a child, and owns fire/reload logic: cooldown from `fire_rate`, semi-auto vs automatic via `is_automatic`, hitscan raycast from the parent `Camera3D` that calls `take_damage(amount)` on anything hit that has that method, reload timer that refills from reserve ammo. Emits `ammo_changed` / `reload_started` signals for future HUD wiring. The hitscan excludes the shooter's own physics body (`owner.get_rid()` — `owner` is the `Player` scene root since `WeaponController` is a direct in-scene child of `player.tscn`, not a separately instanced sub-scene) so aiming close to your own feet can't self-hit.
- `resources/weapons/*.tres` — one `WeaponData` instance per weapon model in `assets/models/weapons/`, mapped to the closest-matching fire/reload sound in `assets/audio/weapons/` (see that file's header comment or `ASSET_MANIFEST.md` for the mapping).
- Wired into `scenes/player/player.tscn` as `Head/Camera3D/WeaponController`, defaulting to `resources/weapons/assault_rifle.tres`.

## Known gaps / simplifications

- **Shotguns fire a single hitscan ray**, not a pellet spread. `shotgun.tres` and `shotgun_sawedoff.tres` compensate with a higher flat `damage`, but a real multi-pellet cone (several raycasts per trigger pull) would feel more shotgun-like. Worth revisiting.
- **No weapon switching yet** — the player always starts with (and is stuck on) the assault rifle. Swapping `WeaponController.equip()` to a different `WeaponData` at runtime already works; there's just no input/UI wired to trigger it.
- **View-model rotation needs an eyes-on tuning pass.** `_fit_view_model()` (in `equip()`) measures each model's actual mesh bounds and scales/positions it to a sane on-screen size automatically — this fixed the first real bug found (a fixed guessed scale made the gun fill the entire screen, since the FBX was real-world-meter-sized and the guess put it 0.5m from the camera at 1:1 scale). First playtest showed the gun lying on its side; `view_model_rotation_degrees` (exported, default `(0, 90, 0)`) now rotates the model before positioning it, but the right value is a guess pending confirmation — adjust it directly on the `WeaponController` node's Inspector properties in `player.tscn` if it's still wrong (try the Y value at -90 or 180 next).
- **No muzzle flash / tracer / impact VFX yet.**
- `take_damage(amount)` is called on raycast hits and is implemented by `scripts/ai/zombie.gd`.
