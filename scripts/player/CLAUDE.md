# scripts/player

Owns: third-person movement (jog/sprint/crouch/jump), the orbiting camera rig, local player input handling, health/damage state for the local player.

Depends on: `scripts/weapons` (equips/fires weapons — wired up), `scripts/common` (`NodeUtils`, for reaching into the imported model), `scripts/networking` (broadcasts local state to peers — not yet wired up).

## Status

`player.gd` (`scenes/player/player.tscn`) implements:

- Movement: WASD jog, Shift sprint (forward-only), Ctrl crouch (smoothly resizes the capsule and lowers the camera rig), Space jump. Mouse is captured on `_ready()`; `ui_cancel` (Esc) toggles capture.
- Aiming: hold right mouse (`aim`). `WeaponController` narrows the camera FOV and reduces mouse sensitivity while the player pulls the camera in over the shoulder; releasing returns smoothly. Reloading cancels aim.
- `HUD/Crosshair` stays centered, tightens while aiming, expands with movement, and pulses outward on each shot.
- `mixamo_soldier.glb` attached as the visible body (`Model` node) — a consolidated Mixamo Gasmask Soldier model with gameplay clips baked into one runtime asset; see `ASSET_MANIFEST.md` for clip names.
- `scripts/weapons/weapon_controller.gd` wired up under `CameraRig/SpringArm3D/Camera3D` — see `scripts/weapons/CLAUDE.md`.
- `health` / `take_damage(amount)` / `died` signal, and joins the `"player"` group so `scripts/ai/zombie.gd` can find and target it. `class_name Player`.
- **Health regenerates** after `REGEN_DELAY` (5.5s) clear of damage, at 10% of max per second — ported from the browser build. The delay is the whole mechanic: it rewards breaking contact, which is what makes kiting a round the right way to play it rather than trading hits.
- **`points`, and `award_points()`** with a `points_changed(total, delta)` signal. The player converts `WeaponController.hit_confirmed` into points via `RoundDirector.points_for_hit()`, looking the director up by group — so the weapon knows nothing about scoring and the director knows nothing about who is shooting.
- **Third-person camera.** `CameraRig → SpringArm3D → Camera3D`. The rig is offset on X to keep the character out of the middle of the screen, and rides the capsule's height so crouching lowers the view. The spring arm collides with `WORLD` only — including actors would slam the camera forward every time a zombie walked behind the player. Aiming shortens the arm (`camera_aim_distance`) to pull in over the shoulder.
- **Mouse yaw turns the body, not the camera.** Pitch goes on the spring arm. The character therefore always faces where the camera looks, which is what makes the directional walk/strafe blend space meaningful and keeps shots landing on the crosshair.
- `_apply_spine_aim()` turns the torso so the held weapon points where the camera does — pitch straight from the camera angle, yaw from the error actually left between the barrel and the view (`_measure_aim_yaw_error()`). Converges to zero at idle and while jogging; deliberately released during a sprint, where the empty-handed clip would demand ~70° of twist. Runs in `_process` because the `AnimationTree` rewrites bone poses every frame — see the `process_priority` note in `_ready()`.
- **No hit reaction.** `take_damage()` deliberately plays nothing. The clip is a full-body flinch that interrupts aiming and sprinting, and losing control every time a zombie connects felt worse than showing nothing. Damage feedback belongs on the HUD.
- **Locomotion clips come from packs, not from the model.** `_install_extra_clips()` loads every set in `INSTALLED_SETS` as loose `Animation` resources, installed under set-namespaced names (`rifle_run_forward`, `pistol_strafe`) so both live in the library at once. The model's own locomotion is largely empty-handed and is not used. Regenerate with `tools/build_clips.gd -- <set>`; check the tables with `tools/verify_locomotion_sets.gd` and the clips themselves with `tools/probe_locomotion_sets.gd`.
- **The stance follows the weapon.** `locomotion_sets.gd` maps a set name to a clip per tier and direction; `WeaponData.locomotion_set` picks one, and `_on_weapon_changed()` re-points every blend point at the new set. The tree is never rebuilt — a switch is a keypress and shouldn't touch the disk. An unknown set name falls back to `rifle`, and a set missing any clip is refused wholesale rather than applied partially, since a square with dead points is a character who freezes when they strafe.
  Names are built from the tables rather than scanned off disk: exported builds turn loose `.res` into `.remap`, so a directory scan works in the editor and quietly finds nothing in a shipped game.
- **Locomotion is three tiers**: `normal` (a jog — this is the default gait) → `sprint` → `crouch`, each a nine-point blend square. A set with no sprint clips of its own (the pistol pack has none) stays on the normal tier and speeds its stride up by `SPRINT_SPEED / WALK_SPEED` through the `LocomotionSpeed` time scale instead — crossfading a tier into a copy of itself blends a clip against a phase-shifted version of itself and mushes the legs together.
- **Animation driven by movement and weapon state.** A runtime `AnimationTree` uses 2D blend spaces for forward, backward, left, right, and interpolated diagonal movement, blending jog to sprint and standing to crouching. Weapon fire/reload signals drive spine-and-arms-only one-shots over locomotion, while jump, landing, hit, and death remain prioritized full-body animations.
- **`model_yaw_offset_degrees` (default 180)** rotates the `Model` node's local Y to correct Mixamo's authored-front-axis mismatch with Godot's forward direction.

## Known gaps

- **The rifle set's sprint is empty-handed.** Mixamo's sprint clips swing both arms, so the weapon swings with the hand rather than being carried — measured, they hold the hands only `+0.03m` to `+0.13m` above the hips against `+0.24m` to `+0.31m` for the jog tier. That's why `_apply_spine_aim()` releases the torso above `sprint_blend > 0.5` instead of trying to correct it. The pistol set has no such problem, because it has no sprint clips at all and reuses its run.
- **The pistol set doesn't visibly crouch.** The pack ships no crouch-walk, so `crouch` reuses the walk tier: the capsule shrinks and the camera drops, but the body stays standing. `kneeling_idle` is a kneel, not a gait, and is only used for the crouch square's centre.
- **A weapon switch is a hard cut.** Re-pointing an `AnimationNodeAnimation` swaps its clip immediately rather than crossfading, so changing stance snaps. Matches the weapons themselves, which have no draw/holster animation either.

Manual test scene: `scenes/levels/test_arena.tscn` (flat ground + player spawn + 3 zombies) — open it in Godot and press F6 to run just that scene.
