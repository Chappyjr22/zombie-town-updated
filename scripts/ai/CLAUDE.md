# scripts/ai

Owns: zombie behavior (pathfinding/chase/attack), spawner logic, wave/round progression. Runs authoritatively on the host only (see `docs/MULTIPLAYER.md`); results are relayed to clients, not simulated locally on clients — networking sync itself isn't wired up yet, this still runs purely local/single-player.

Depends on: `scripts/networking` (to relay authoritative state — not yet wired up).

## Status

`zombie.gd` (`class_name Zombie`, used by `scenes/zombies/zombie.tscn`) implements:

- A simple state machine: `IDLE` → `CHASE` (moves straight toward the nearest node in the `"player"` group, no pathfinding/obstacle avoidance yet) → `ATTACK` (in range, deals `attack_damage` on a cooldown via `target.take_damage()`) → `DEAD`.
- `take_damage(amount, hit_impulse)` — same interface `weapon_controller.gd`'s hitscan calls. Below zero health triggers `die()`.
- `die()` stops the AI and animation, disables the capsule collider, and calls `skeleton.physical_bones_start_simulation()` on whatever `Skeleton3D` it finds inside the model. Applies the killing hit's impulse to whichever `PhysicalBone3D` looks like the torso/hips (falls back to the first one found). Corpses `queue_free()` after `corpse_lifetime` seconds (default 20).
  - **Bug found and fixed by testing (round 1):** stopping the `AnimationPlayer` with plain `anim_player.stop()` resets the skeleton to its rest/bind pose first (that's `stop()`'s default behavior unless told otherwise). Physical-bone simulation then captured *that* pose instead of whatever pose the zombie actually died in, so every bone suddenly overlapped its neighbor and the physics engine violently shoved them apart — zombies went flying on death. Fixed by calling `anim_player.stop(true)` instead, which preserves the current pose.
  - **Bug found and fixed by testing (round 2):** zombies still launched after the round-1 fix — but *immediately on scene start*, before any shooting/death at all. Turned out the round-1 theory was right but incomplete: `_isolate_ragdoll_bones()` (see below) was only called from `die()`, but "Create Physical Skeleton" in the editor creates the `PhysicalBone3D` nodes immediately, on the default collision layer, whether or not `physical_bones_start_simulation()` has ever run. Those bones sat there overlapping the zombie's own standing capsule collider from frame one and got violently shoved apart with no death involved. Fixed by calling `_isolate_ragdoll_bones()` (and `physical_bones_stop_simulation()`, as a belt-and-suspenders guard against the editor step somehow leaving simulation active) in `_ready()` too, not just `die()`.
  - `_isolate_ragdoll_bones()` (shared by `_ready()` and `die()`) moves every `PhysicalBone3D` under the skeleton onto `PhysicsLayers.RAGDOLL` (mask `WORLD` only — see `scripts/common/physics_layers.gd`), so they can never collide with a living actor (this zombie's own capsule or anyone else's), only rest on the ground.
- Animation playback (`_play_anim`) tries a plain clip name first, then falls back to the `CharacterArmature|Name` baked-clip naming the Quaternius models actually use (see `ASSET_MANIFEST.md`).
- `_find_first_of_type()` walks the instanced model looking for its `AnimationPlayer`/`Skeleton3D` by class name rather than a hardcoded node path, since this session couldn't open the Godot editor to confirm the exact import hierarchy.

## Required manual step: ragdoll physical bones

Godot's ragdoll (`PhysicalBone3D` per bone, with auto-sized collision shapes and joints matching the skeleton's actual pose) has to be generated once per zombie model **in the Godot editor** — it's not something that can be hand-authored correctly from outside the editor, and this session has no editor access to do it:

1. Open `scenes/zombies/zombie.tscn`.
2. Select the `Skeleton3D` node inside `Model` (expand the instanced `zombie-alt.glb`).
3. Skeleton3D's toolbar menu → **Create Physical Skeleton**. This generates a `PhysicalBoneSimulator3D` with one `PhysicalBone3D` + joint per bone, shapes sized from the actual mesh.
4. Save the scene.

Until this is done, `die()` still runs without erroring (`physical_bones_start_simulation()` on a skeleton with zero physical bones is a safe no-op) — the corpse will just disappear via `queue_free()` after `corpse_lifetime` instead of ragdolling.

Do this once and it's inherited by every `Zombie` instance sharing that scene — not a per-spawn cost.

## Known gaps

- **Straight-line chase, no pathfinding.** Zombies will walk into obstacles/walls instead of routing around them. Fine for the flat `test_arena.tscn`; will need `NavigationAgent3D` + a baked `NavigationRegion3D` once real levels have geometry.
- **No round/wave spawner yet** — `test_arena.tscn` just hand-places 3 zombies.
- **Single zombie model wired up** (`zombie-alt.glb`, the one with the richest animation set). `zombie.glb` and `zombie-crawler.glb` exist for variety but aren't used by any scene yet.
