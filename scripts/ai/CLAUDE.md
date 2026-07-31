# scripts/ai

Owns: zombie behavior (pathfinding/chase/attack), spawner logic, wave/round progression. Runs authoritatively on the host only (see `docs/MULTIPLAYER.md`); results are relayed to clients, not simulated locally on clients — networking sync itself isn't wired up yet, this still runs purely local/single-player.

Depends on: `scripts/networking` (to relay authoritative state — not yet wired up).

## Status

`round_director.gd` (`class_name RoundDirector`) runs the round loop. It lives **in the level**, not in an autoload — the project has none, and rounds belong to a match rather than to the app. `test_arena.tscn` has one with 12 `Marker3D` spawn points; any `Marker3D` child is used as a spawn, and a director with none falls back to a ring so a level still runs instead of silently spawning nothing.

**The tuning is ported wholesale from the browser build** (`zombie-town-online`), where it was play-tested over a lot of rounds. Re-deriving these curves would have thrown away the one thing that was already known-good:

| | Formula | Round 1 | Round 10 |
|---|---|---|---|
| Zombies | `10 + (r-1)*2` | 10 | 28 |
| Health | `100 + (r-1)*30 + max(0, r-9)*45` | 100 | 415 |
| Speed | `clamp(1.5 + (r-1)*0.07, 1.4, 4.0)` × `rand(0.85, 1.15)` | ~1.5 | ~2.1 |
| Melee | `13 + r*0.7` | 13.7 | 20 |
| Points × | `1 + (r-1)*0.15` | 1.0 | 2.35 |

Awards are `10` for any hit that connects, plus `50` body / `90` head on the kill — so a killing headshot is 100, all before the round multiplier. The chip award is the floor of the economy: it's what keeps a weak gun on a high round earning.

- **Population is capped at 30 alive.** The rest of the round queues behind it, so a high round is a difficulty problem rather than a framerate one. Spawns trickle in on a `0.7–1.6s` timer.
- **Spawns favour distance.** `_pick_spawn_point()` samples 7 markers and takes the furthest from the player, so zombies don't materialise at your shoulder. Sampling rather than sorting keeps it unpredictable.
- **Rounds advance two ways**: `ROUND_LENGTH` (150s) caps a round the player hasn't finished, and `ROUND_BREATHER` (8s) is what you actually get after clearing one. The browser build made you wait out the full 150s or press a key to skip; that key doesn't exist here and standing in an empty map for two minutes isn't a mechanic worth porting.
- **Bug found by testing: every spawn launched the player off the map at 4,800 m/s.** `add_child()` puts a body at its parent's origin, and the physics solver resolves that frame's overlaps *before* the next line moves it to its marker. With the director at the middle of the map that origin is exactly where the player stands, so each spawn briefly shared a capsule with them. Fixed by setting `position` (local — `global_position` needs a node already in the tree) **before** `add_child()`. This is the same class of bug as ragdoll rounds 1–2 below, and the third time it's bitten this project: *a body must be placed before it enters the tree, not after.*

`zombie.gd` (`class_name Zombie`, used by `scenes/zombies/zombie.tscn`) implements:

- `died(zombie)` — emitted exactly once, guarded by the `DEAD` state. `RoundDirector` counts rounds off it, so a double-emit would end rounds early.
- `is_dead()` and `classify_hit(world_position)`. The latter returns `&"head"` or `&"body"` by measuring against the **live head bone**, not a height threshold — so a crouched, lunging or mid-animation zombie is scored on where its head actually is. Rigs with no recognisable head bone fall back to `body`, which costs the player a bonus rather than handing them one for a miss.
- **Pathfinding via a `NavigationAgent3D` added in code**, not to each of the three zombie scenes — that way the variants can't drift apart on it. Whether it's used is decided per frame by `_has_navigation_mesh()`: levels without a baked navmesh (the flat test arena) get the old straight-line chase, so a level is never broken by lacking one. Zombies face where they're *going* rather than at the player, or one routing round a building walks sideways with its head turned.

- A simple state machine: `IDLE` → `CHASE` (moves straight toward the nearest node in the `"player"` group, no pathfinding/obstacle avoidance yet) → `ATTACK` (in range, deals `attack_damage` on a cooldown via `target.take_damage()`) → `DEAD`.
- `take_damage(amount, hit_impulse)` — same interface `weapon_controller.gd`'s hitscan calls. Below zero health triggers `die()`.
- `die()` stops the AI, disables the capsule collider, and plays the model's own `Death` animation clip (holds on its last frame once finished — see round 7 below for why this replaced physics ragdoll). Corpses `queue_free()` after `corpse_lifetime` seconds (default 20).
  - **Bug found and fixed by testing (round 1):** stopping the `AnimationPlayer` with plain `anim_player.stop()` resets the skeleton to its rest/bind pose first (that's `stop()`'s default behavior unless told otherwise). Physical-bone simulation then captured *that* pose instead of whatever pose the zombie actually died in, so every bone suddenly overlapped its neighbor and the physics engine violently shoved them apart — zombies went flying on death. Fixed by calling `anim_player.stop(true)` instead, which preserves the current pose.
  - **Bug found and fixed by testing (round 2):** zombies still launched after the round-1 fix — but *immediately on scene start*, before any shooting/death at all. Turned out the round-1 theory was right but incomplete: `_isolate_ragdoll_bones()` (see below) was only called from `die()`, but "Create Physical Skeleton" in the editor creates the `PhysicalBone3D` nodes immediately, on the default collision layer, whether or not `physical_bones_start_simulation()` has ever run. Those bones sat there overlapping the zombie's own standing capsule collider from frame one and got violently shoved apart with no death involved. Fixed by calling `_isolate_ragdoll_bones()` (and `physical_bones_stop_simulation()`, as a belt-and-suspenders guard against the editor step somehow leaving simulation active) in `_ready()` too, not just `die()`.
  - `_isolate_ragdoll_bones()` (shared by `_ready()` and `die()`) moves every `PhysicalBone3D` under the skeleton onto `PhysicsLayers.RAGDOLL` (mask `WORLD` only — see `scripts/common/physics_layers.gd`), so they can never collide with a living actor (this zombie's own capsule or anyone else's), only rest on the ground.
- Animation playback resolves plain Mixamo clip names and the `CharacterArmature|Name` naming used by the legacy Quaternius model. Locomotion loops do not restart every physics frame. Attack, bite, hit/scream, and death clips lock out locomotion until `AnimationPlayer.animation_finished`, so a one-shot cannot be replaced on the next frame.
- Three scene variants share the same AI contract: `zombie.tscn` (legacy Quaternius), `scary_zombie.tscn` (Mixamo Scary Zombie Pack), and `cop_zombie.tscn` (Mixamo Copzombie L Actisdato). The two Mixamo runtime GLBs each contain the same named 12-clip library, with the scary pack retargeted onto the cop by normalized Mixamo bone names.
- `NodeUtils.find_first_of_type()` (see `scripts/common/CLAUDE.md`) walks the instanced model looking for its `AnimationPlayer`/`Skeleton3D` by class name rather than a hardcoded node path, since this session couldn't open the Godot editor to confirm the exact import hierarchy.
- **Bug found and fixed by testing (round 3): zombies chased with their backs to the player.** `look_at()` correctly points the `CharacterBody3D`'s -Z at the target, but the model's own authored front axis doesn't match that convention (same underlying issue as the weapon view-model rotation - see `scripts/weapons/CLAUDE.md`). Fixed with `model_yaw_offset_degrees` (exported, default 180 - the mismatch looked like an exact backward flip in testing, not an arbitrary angle) applied to the `Model` node's local rotation in `_ready()`. If it's still wrong, adjust the `Model` node's Y rotation directly in `zombie.tscn`'s Inspector.
- **Bug found and fixed by testing (round 4, superseded by the Mixamo integration): zombies appeared to freeze or barely attack up close.** The old implementation either held a completed attack pose or replaced the swing with `Idle_Attack` on the following frame. One-shots now set `locked_animation`; `_update_animation()` leaves them alone until `animation_finished`, then resumes the matching locomotion/idle loop. Mixamo zombies cycle through `Attack`, `Bite`, `BiteAlt`, and `NeckBite`; legacy models fall back to their available `Attack`/`Punch` clips.
- **Bug found and fixed by testing (round 5): killed zombies stood frozen in a T-pose instead of ragdolling.** The Debugger's Errors tab showed nothing thrown from `die()` at all — `skeleton.physical_bones_start_simulation()` ran without error, but the bones never actually moved or fell, staying inert. Root cause: "Create Physical Skeleton" creates a `PhysicalBoneSimulator3D` node as a child of `Skeleton3D`, and *that* node is the real, current owner of `physical_bones_start/stop_simulation()` in this Godot version — `Skeleton3D` still exposes same-named convenience methods, but they silently did nothing here rather than forwarding to the simulator. Fixed by finding the `PhysicalBoneSimulator3D` directly (`NodeUtils.find_first_of_type(model, "PhysicalBoneSimulator3D")`) and calling start/stop on it instead of on `skeleton`.
- **Bug found and fixed by testing (round 6): corpses stretched into long spikes instead of ragdolling naturally.** This zombie's rig has small detail bones beyond the main body skeleton — individual finger bones (`Pinky3`/`Middle3`/`Index3`/`Thumb2`, both hands), `Tongue5`, `Eyelid_L`/`Eyelid_R`, and IK `PoleTarget_L`/`PoleTarget_R` helpers. Simulating physics on *all* of them (the default when `physical_bones_start_simulation()` is called with no argument) let lightweight bones like the tongue segment get flung around, dragging their narrow skin weighting into long stretched spikes. Fixed with `_ragdoll_bone_names()`, which enumerates `skeleton.get_bone_count()`/`get_bone_name()` and excludes anything matching `RAGDOLL_EXCLUDE_PATTERNS` (case-insensitive substring match: `tongue`, `eyelid`, `pinky`, `middle`, `index`, `thumb`, `poletarget`, `_end`), then passes that filtered list to `physical_bones_start_simulation(bones)`.
- **Round 7 — gave up on physics ragdoll for now, switched to a canned death animation.** Round 6's fix wasn't enough either: even with detail bones excluded, the *main* limb bones (arms/legs) still stretched into spikes on testing. This points at a deeper joint/shape mismatch between Godot's auto-generated `PhysicalBone3D` setup and this particular stylized rig's proportions/skin weighting — the kind of thing that needs hands-on per-joint tuning in the editor (tightening rotation limits, adjusting shape sizes) rather than something fixable blind from outside the editor. Six rounds in, diminishing returns. `die()` now just plays the model's own `Death` animation clip instead — professionally authored, guaranteed to look right, zero physics tuning needed. The ragdoll infrastructure (`PhysicsLayers.RAGDOLL`, `_isolate_ragdoll_bones()`, `_ragdoll_bone_names()`, `physical_bone_simulator`) is still in the file, just unused by `die()` — worth revisiting later as a polish pass, likely starting from manually tuning joint limits in the editor rather than more code changes.

## Optional: ragdoll physical bones (not currently used)

`die()` doesn't need this anymore (see round 7 above) — it plays a canned animation instead. This section is kept for whenever physics ragdoll is worth revisiting:

1. Open `scenes/zombies/zombie.tscn`.
2. Select the `Skeleton3D` node inside `Model` (expand the instanced `zombie-alt.glb`).
3. Skeleton3D's toolbar menu → **Create Physical Skeleton**. This generates a `PhysicalBoneSimulator3D` with one `PhysicalBone3D` + joint per bone, shapes sized from the actual mesh.
4. Save the scene.

If revisiting this, expect to need per-bone joint tuning (rotation limits, shape sizes) on top of the existing `_ragdoll_bone_names()` filtering — that alone wasn't sufficient on this rig.

## Verifying it

`tools/probe_round_loop.gd` drives the whole loop headless and checks the things that would otherwise fail silently — rounds starting, zombies arriving from the markers, the cap holding, the ramp actually reaching spawned zombies, shooting paying out, and regen respecting its delay:

```
godot --headless --path . --script tools/probe_round_loop.gd
```

It compresses time with `Engine.time_scale`, **and raises `physics_ticks_per_second` to match** — without that, each physics step covers 0.2s and a falling body clears the arena's 1m floor between two steps, which had the probe reporting the player 559m below the map for reasons that had nothing to do with the code under test.

`tools/probe_player_drift.gd` is the narrower regression check for the spawn-overlap bug: a standing player with no input must not move while a round spawns around them.

## Known gaps

- **Zombies shove the player.** Both are on `ACTORS` and collide, so a crowd pushes the player across the map — measured at 167m over one probe run. Needs either a one-way mask, or push-back resolved in code with a cap.
- **No pathfinding without a baked navmesh.** The agent is wired and falls back cleanly, but no level has a `NavigationRegion3D` yet, so today every zombie still walks in a straight line. The town map will need one baked.
- **No boss rounds.** The browser build ran one every 10th round (`6000 + max(0, r-10)*550` health, 1.48× scale, one boss plus ten escorts). Not ported — there's no boss model wired up here yet, though the old repo's is CC0 and has provenance written.
- **No downed/bleed-out state.** Death is currently just `is_dead`. Bleed-out only means something alongside co-op revives or a Quick Revive perk, and building it now would be an empty dial.
- **Crawl clips are imported but not state-driven yet.** `Crawl` and `CrawlRun` are available on both Mixamo variants; the state machine has no crawling/injury state that selects them.
- **Crawl clips are imported but not state-driven yet.** `Crawl` and `CrawlRun` are available on both Mixamo variants; the current state machine has no crawling/injury state that selects them.
