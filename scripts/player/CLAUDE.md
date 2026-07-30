# scripts/player

Owns: first-person movement (walk/sprint/crouch/jump), mouse-look camera, local player input handling, health/damage state for the local player.

Depends on: `scripts/weapons` (equips/fires weapons — not yet wired up), `scripts/networking` (broadcasts local state to peers — not yet wired up).

## Status

`player.gd` (`scenes/player/player.tscn`) implements movement: WASD walk, Shift sprint (forward-only), Ctrl crouch (smoothly resizes the capsule + camera height), Space jump, mouse-look (yaw on the body, pitch on `Head`, clamped ±89°). Mouse is captured on `_ready()`; `ui_cancel` (Esc) toggles capture.

No visual mesh attached yet — the capsule is invisible. Next steps: attach `assets/models/characters/soldier.glb` or `swat.glb` as a child (see `ASSET_MANIFEST.md` for their animation clip names), hide the head/first-person-blocking geometry from the local camera's view, and wire `scripts/weapons` for equip/fire.

Manual test scene: `scenes/levels/test_arena.tscn` (flat ground + player spawn, no zombies yet) — open it in Godot and press F6 to run just that scene.
