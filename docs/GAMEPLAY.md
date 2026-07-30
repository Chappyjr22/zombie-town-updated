# Gameplay Scope

## Current target: core loop first

Build and get fun before adding meta-progression:

1. First-person movement + camera
2. Weapon equip/fire/reload, hooked to the models and sounds already in `assets/`
3. Zombie AI: chase, attack, die (with ragdoll — see below)
4. Basic round-based waves (zombies spawn in increasing numbers/difficulty per round)

## Deferred (not in scope yet)

Explicitly out of scope until the core loop is fun on its own — revisit after playtesting:

- Points economy
- Mystery box / weapon randomization
- Pack-a-Punch weapon upgrades
- Perks
- Power-ups
- Boss rounds (e.g. a "Brute"-style heavy enemy)

These were all present in the earlier three.js prototype (`chappyjr22/zombie-town-online`) and are worth revisiting as design references later, but are not being ported now.

## Zombie ragdoll on death

The old three.js prototype implemented ragdolls from scratch: a hand-rolled 15-point Verlet-integration skeleton with distance constraints, because three.js has no built-in skeletal physics. That complexity doesn't carry over — Godot has ragdolls built in:

- Zombie models (`assets/models/zombies/*.glb`) are rigged with a `Skeleton3D`.
- On death: stop the `AnimationPlayer`, call `Skeleton3D.physical_bones_start_simulation()` (requires `PhysicalBone3D` nodes configured under the skeleton — set up once per zombie scene, not per instance), and apply an impulse to the hit bone in the direction/force of the killing shot.
- Godot's physics engine takes it from there — no custom simulation code needed. (Jolt Physics is available as of 4.3 and became the default in 4.4; either it or the built-in GodotPhysics3D handles PhysicalBone3D ragdolls fine.)
- `physical_bones_stop_simulation()` + blending back to animation is NOT needed for zombies (they stay dead), unlike a game that revives ragdolled characters.

Implementation lives in `scripts/ai/` once the zombie scene exists.
