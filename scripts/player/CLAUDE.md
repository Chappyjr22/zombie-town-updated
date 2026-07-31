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
- `health` / `take_damage(amount)` / `died` signal, and joins the `"player"` group so `scripts/ai/zombie.gd` can find and target it.
- **Third-person camera.** `CameraRig → SpringArm3D → Camera3D`. The rig is offset on X to keep the character out of the middle of the screen, and rides the capsule's height so crouching lowers the view. The spring arm collides with `WORLD` only — including actors would slam the camera forward every time a zombie walked behind the player. Aiming shortens the arm (`camera_aim_distance`) to pull in over the shoulder.
- **Mouse yaw turns the body, not the camera.** Pitch goes on the spring arm. The character therefore always faces where the camera looks, which is what makes the directional walk/strafe blend space meaningful and keeps shots landing on the crosshair.
- `_apply_spine_pitch()` leans the torso with the camera pitch so the held weapon visibly tracks up and down. Runs in `_process` because the `AnimationTree` rewrites bone poses every frame — see the `process_priority` note in `_ready()`.
- **Two clips are replaced at runtime** by `_install_extra_clips()` from loose `Animation` resources (`EXTRA_CLIPS`): `idle` gets Mixamo's aiming idle instead of the chest-carry patrol, and `sprint` gets a real sprint — the consolidated model ships **no sprint clip**, so sprinting used to play `run` and looked identical to jogging. Regenerate with `tools/build_clips.gd`.
- **Locomotion is three tiers**: idle → jog (`run`) → sprint (`sprint`). Normal movement is a jog; `walk` is no longer used by the standing blend space.
- **Animation driven by movement and weapon state.** A runtime `AnimationTree` uses 2D blend spaces for forward, backward, left, right, and interpolated diagonal movement, blending jog to sprint and standing to crouching. Weapon fire/reload signals drive spine-and-arms-only one-shots over locomotion, while jump, landing, hit, and death remain prioritized full-body animations.
- **`model_yaw_offset_degrees` (default 180)** rotates the `Model` node's local Y to correct Mixamo's authored-front-axis mismatch with Godot's forward direction.

## Known gaps

- **Crouching is not directionally authored yet.** The crouch blend space reuses `crouch_walk` for forward, backward, and strafing movement. Replace those points when directional crouch clips are available.
- **Strafes and backpedals share one source cadence per gait.** Custom timelines stretch the same directional source clips to the jog or sprint cycle length; the raw Mixamo folder has `Sprint Left/Right` and `Rifle Backward Run To Stop` that would improve foot timing — extract them with `tools/build_clips.gd` the same way `sprint` was.
- **Sprint uses an empty-handed clip.** Mixamo's "Sprint Forward" swings both arms, so the weapon swings with the hand rather than being carried. Reads fine, but "Rifle Run" is the alternative if a weapon-carried sprint is wanted.

Manual test scene: `scenes/levels/test_arena.tscn` (flat ground + player spawn + 3 zombies) — open it in Godot and press F6 to run just that scene.
