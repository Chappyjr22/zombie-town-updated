# scripts/weapons

Owns: weapon base class, per-weapon stats/behavior (fire rate, damage, reload, hitscan/projectile), muzzle flash and impact effects.

Depends on: `assets/models/weapons` (see `ASSET_MANIFEST.md` for which models exist), `resources/weapons/*.tres` (per-weapon data).

## Status

- `weapon_data.gd` — a `Resource` (`class_name WeaponData`) holding one weapon's stats + asset references (model scene, fire/reload sounds, damage, fire rate, mag size, reload time, range). No behavior, pure data.
- `weapon_controller.gd` — a `Node3D` (`class_name WeaponController`) that equips a `WeaponData`, hangs it off the character's hand, and owns the fire/reload logic: cooldown from `fire_rate`, semi-auto vs automatic via `is_automatic`, two-stage hitscan (see below) that calls `take_damage(amount)` on anything hit that has that method, and a reload timer that refills from reserve ammo. It emits `ammo_changed`, `fired`, `reload_started`, and `aim_changed`; the player uses `fired`/`reload_started` for upper-body-only third-person animations layered over locomotion. The hitscan excludes the shooter's own physics body (`owner.get_rid()` — `owner` is the `Player` scene root since `WeaponController` is a direct in-scene child of `player.tscn`, not a separately instanced sub-scene) so aiming close to your own feet can't self-hit.

### There is no viewmodel

The game is **third person**, so there is exactly one weapon in the world. `attach_world_model()` hangs it off the body's `mixamorig_RightHand`, and that single instance is what the player and everyone else sees.

Two parts of the fit are measured rather than authored, so a new weapon usually needs no tuning:

- `_fit_to_grip()` scales the model so its longest dimension is `weapon_length`, turns it barrel-down-`-Z` via `_canonical_weapon_basis()` (which infers the barrel/up/width axes from the bounding box, since the pack's FBXs are authored every which way), and slides it so `grip_anchor` lands where the hand closes.
- `_align_world_model()` then turns it to lie along the line between the body's *own two hands*, sampled from the animated pose one frame after attaching. That's why the weapon points where the animation holds it in any clip, instead of at an angle guessed against Mixamo's arbitrary wrist frame.

Recoil is a spring on the **camera** (`_update_recoil`), not on a weapon model.

**Hitscan is two-stage** (`_hitscan`). The camera sits metres behind the player, so a single ray straight down it would start behind the character and hit whatever stood between them. Instead a first ray from the camera finds what's under the crosshair, then the damaging trace runs from the weapon to that point.

The game was first person for a while, with a conventional viewmodel — arms carved out of the soldier, weapon posed in camera space, hands pinned and IK'd onto it. It's gone. `docs/ASSET_PIPELINE.md` records why, so the same ground isn't covered twice.
- `resources/weapons/*.tres` — one `WeaponData` instance per weapon model in `assets/models/weapons/`, mapped to the closest-matching fire/reload sound in `assets/audio/weapons/` (see that file's header comment or `ASSET_MANIFEST.md` for the mapping).
- Wired into `scenes/player/player.tscn` as `CameraRig/SpringArm3D/Camera3D/WeaponController`, defaulting to `resources/weapons/assault_rifle.tres`.

## Known gaps / simplifications

- **Shotguns fire a single hitscan ray**, not a pellet spread. `shotgun.tres` and `shotgun_sawedoff.tres` compensate with a higher flat `damage`, but a real multi-pellet cone (several raycasts per trigger pull) would feel more shotgun-like. Worth revisiting.
- **No weapon switching yet** — the player always starts with (and is stuck on) the assault rifle. Swapping `WeaponController.equip()` to a different `WeaponData` at runtime already works; there's just no input/UI wired to trigger it.
- **Only the assault rifle has a tuned `grip_anchor`.** Every other weapon uses the default, which is roughly right because the pack is consistently authored, but none have been checked. `tools/probe_weapon_grip.gd` prints a weapon's underside profile — the pistol grip shows as the rearmost dip — which is how the rifle's `Vector2(0.09, 0.27)` was derived. Do that rather than guessing offsets.
- **The support hand's rotation isn't controlled.** `_solve_support_arm_ik()` puts the wrist on `foregrip_anchor` (measured at 0.035m from the socket), but the hand's *orientation* and finger curl still come from the clip, so the palm doesn't wrap the handguard. The last change in flight was locking the hand's basis to the weapon's via `support_hand_rotation_degrees` — that export exists and is untuned.
- **ADS only narrows the FOV and pulls the camera in.** The weapon is posed by the animation, so there's no sight alignment.
- **The weapon doesn't point at the crosshair while sprinting.** `player.gd`'s spine yaw correction converges to zero error at idle and while jogging, but is deliberately released during a sprint: Mixamo's sprint clip swings both arms, so closing the gap would need ~70° of torso twist and the character would run hunched. You aren't aiming mid-sprint, and shots trace from the camera regardless.
  The correction reads the barrel via `get_barrel_direction()`, which derives it from `barrel_in_mesh` — measured at fit time. **Do not** take the model's local `-Z`; `_align_world_model()` post-multiplies a rotation, so that axis stops being the barrel. Getting this wrong is what made the first attempt diverge.
- **No muzzle flash / tracer / impact VFX yet.**
- `take_damage(amount)` is called on raycast hits and is implemented by `scripts/ai/zombie.gd`.
