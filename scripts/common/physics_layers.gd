class_name PhysicsLayers
extends RefCounted

## Bit values (not layer numbers - these are already shifted) for Godot's
## 32-bit collision_layer/collision_mask. Layer 1 (ground/static level
## geometry) is Godot's default for everything, so it's never set explicitly
## here - only the layers actors and ragdolls opt into.
const WORLD := 1 ## bit for layer 1 - default layer, ground/static geometry
const ACTORS := 2 ## bit for layer 2 - player + living zombie capsules
const RAGDOLL := 4 ## bit for layer 3 - zombie corpse physical bones
const HITBOX := 8 ## bit for layer 4 - wider hitscan-only target, see below

## Why ragdolls need their own layer: a dead zombie's PhysicalBone3D shapes
## spawn at whatever pose the zombie died in, which is often overlapping the
## player or another zombie's capsule (mid-attack range). If they shared a
## layer, the physics engine would see that overlap as a sudden collision and
## violently shove the bones apart to resolve it - corpses launching into the
## sky on death. Keeping ragdoll bones on their own layer, colliding only with
## WORLD, means they still fall and rest on the ground normally but can never
## explode against a living actor.

## Why hitboxes need their own layer too: a zombie's movement capsule (ACTORS)
## has to stay tight to the torso, or crowds of zombies would shove each other
## and the player around even harder than they already do (see the "Zombies
## shove the player" known gap in scripts/ai/CLAUDE.md). But a tight capsule
## means shots landing on an outstretched, reaching arm - most of a zombie's
## actual silhouette - sail through empty collision space and never register.
## HITBOX is worn by a separate, wider Area3D (scripts/ai/zombie.gd's
## _setup_hitbox()) that only weapon hitscans query (see
## WeaponController._hitscan()'s collide_with_areas), so it can be generous
## without affecting how zombies physically push against anything.
