# scripts/player

Owns: first-person movement (walk/sprint/crouch/jump), mouse-look camera, local player input handling, health/damage state for the local player.

Depends on: `scripts/weapons` (equips/fires weapons — not yet wired up), `scripts/networking` (broadcasts local state to peers — not yet wired up).

## Status

`player.gd` (`scenes/player/player.tscn`) implements movement: WASD walk, Shift sprint (forward-only), Ctrl crouch (smoothly resizes the capsule + camera height), Space jump, mouse-look (yaw on the body, pitch on `Head`, clamped ±89°). Mouse is captured on `_ready()`; `ui_cancel` (Esc) toggles capture.

`soldier.glb` (see `ASSET_MANIFEST.md` for its animation clip names) is attached as the visible body (`Model` node), and `scripts/weapons/weapon_controller.gd` is wired up under `Head/Camera3D` — see `scripts/weapons/CLAUDE.md` for what that does.

## Known gaps

- **No animation wiring.** The `Model` instance's `AnimationPlayer` (nested inside the imported `soldier.glb` scene — exact node path unconfirmed, this session can't open the Godot editor to check) isn't driven by movement state yet. Idle/run/jump should play based on `velocity` and `is_on_floor()`.
- **Own body isn't hidden from the first-person camera.** Right now the local player's `Model` mesh sits in front of the camera at close range — this needs either a cull-mask split (camera excludes the third-person body layer, a separate arms-only view model renders on top) or at minimum hiding the head. Not done yet.

Manual test scene: `scenes/levels/test_arena.tscn` (flat ground + player spawn, no zombies yet) — open it in Godot and press F6 to run just that scene.
