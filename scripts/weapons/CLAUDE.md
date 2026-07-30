# scripts/weapons

Owns: weapon base class, per-weapon stats/behavior (fire rate, damage, reload, hitscan/projectile), muzzle flash and impact effects.

Depends on: `assets/models/weapons` (see `ASSET_MANIFEST.md` for which models exist), `resources/weapons/*.tres` (per-weapon data).

## Status

- `weapon_data.gd` — a `Resource` (`class_name WeaponData`) holding one weapon's stats + asset references (model scene, fire/reload sounds, damage, fire rate, mag size, reload time, range). No behavior, pure data.
- `weapon_controller.gd` — a `Node3D` (`class_name WeaponController`) that equips a `WeaponData`, instantiates its model as a child, and owns fire/reload logic: cooldown from `fire_rate`, semi-auto vs automatic via `is_automatic`, hitscan raycast from the parent `Camera3D` that calls `take_damage(amount)` on anything hit that has that method, reload timer that refills from reserve ammo. Emits `ammo_changed` / `reload_started` signals for future HUD wiring.
- `resources/weapons/*.tres` — one `WeaponData` instance per weapon model in `assets/models/weapons/`, mapped to the closest-matching fire/reload sound in `assets/audio/weapons/` (see that file's header comment or `ASSET_MANIFEST.md` for the mapping).
- Wired into `scenes/player/player.tscn` as `Head/Camera3D/WeaponController`, defaulting to `resources/weapons/assault_rifle.tres`.

## Known gaps / simplifications

- **Shotguns fire a single hitscan ray**, not a pellet spread. `shotgun.tres` and `shotgun_sawedoff.tres` compensate with a higher flat `damage`, but a real multi-pellet cone (several raycasts per trigger pull) would feel more shotgun-like. Worth revisiting.
- **No weapon switching yet** — the player always starts with (and is stuck on) the assault rifle. Swapping `WeaponController.equip()` to a different `WeaponData` at runtime already works; there's just no input/UI wired to trigger it.
- **View-model placement is unverified.** `view_model_offset`/`view_model_scale` on `WeaponController` are a guess (no grip point authored on the FBX models, and this session can't open the Godot editor to look). Expect to need visual tuning.
- **No muzzle flash / tracer / impact VFX yet.**
- `take_damage(amount)` is called on raycast hits but nothing implements it yet — that's `scripts/ai`'s job once zombies exist.
