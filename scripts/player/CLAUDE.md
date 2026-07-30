# scripts/player

Owns: first-person movement (walk/sprint/crouch/jump), mouse-look camera, local player input handling, health/damage state for the local player.

Depends on: `scripts/weapons` (equips/fires weapons — wired up), `scripts/common` (`NodeUtils`, for reaching into the imported model), `scripts/networking` (broadcasts local state to peers — not yet wired up).

## Status

`player.gd` (`scenes/player/player.tscn`) implements:

- Movement: WASD walk, Shift sprint (forward-only), Ctrl crouch (smoothly resizes the capsule + camera height), Space jump, mouse-look (yaw on the body, pitch on `Head`, clamped ±89°). Mouse is captured on `_ready()`; `ui_cancel` (Esc) toggles capture.
- `soldier.glb` attached as the visible body (`Model` node) — see `ASSET_MANIFEST.md` for its animation clip names.
- `scripts/weapons/weapon_controller.gd` wired up under `Head/Camera3D` — see `scripts/weapons/CLAUDE.md`.
- `health` / `take_damage(amount)` / `died` signal, and joins the `"player"` group so `scripts/ai/zombie.gd` can find and target it.
- **Own body hidden from the local camera.** `_hide_own_body_from_camera()` moves every `MeshInstance3D` under `Model` onto visual layer `BODY_VISUAL_LAYER` (2) and excludes that layer from the local `Camera3D`'s `cull_mask`. The body stays visible to other players (multiplayer isn't wired up yet, but this is layer-based, not a `visible = false`, so it'll still render for anyone else's camera once networking exists) and still casts shadows (shadow rendering isn't controlled by `Camera3D.cull_mask`).
- **Animation driven by movement state.** `_update_animation()` picks a clip based on `is_on_floor()` / landing-this-frame / crouching / horizontal speed: `Jump_Idle`/`Jump` while airborne, `Jump_Land` on landing, `Duck` while crouched, `Run_Gun`/`Run` while moving, `Idle_Shoot`/`Idle` otherwise (soldier.glb's actual clip names — see `ASSET_MANIFEST.md`).
- **`model_yaw_offset_degrees` (default 180)** rotates the `Model` node's local Y to correct for the same authored-front-axis mismatch found on the zombie models (see `scripts/ai/CLAUDE.md`) — applied pre-emptively here since it's the same Quaternius asset family, even though this session never actually saw the player's own body (it's hidden from the local camera). Matters for other players' views once multiplayer exists, or a future third-person mode.

## Known gaps

- **No animation blending or one-shot completion tracking.** `Jump_Land` gets requested for exactly one physics frame before the next frame's state (idle/run) overrides it — it may barely play, or not visibly finish, depending on clip length vs. frame timing. Fine as a first pass; revisit with `AnimationTree`/blending if it looks bad.
- **Everything here is unverified beyond careful reading** — this session has no Godot editor access to actually run it. Report back what breaks after testing locally.

Manual test scene: `scenes/levels/test_arena.tscn` (flat ground + player spawn + 3 zombies) — open it in Godot and press F6 to run just that scene.
