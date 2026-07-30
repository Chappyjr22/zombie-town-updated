class_name PhysicsLayers
extends RefCounted

## Bit values (not layer numbers - these are already shifted) for Godot's
## 32-bit collision_layer/collision_mask. Layer 1 (ground/static level
## geometry) is Godot's default for everything, so it's never set explicitly
## here - only the layers actors and ragdolls opt into.
const WORLD := 1 ## bit for layer 1 - default layer, ground/static geometry
const ACTORS := 2 ## bit for layer 2 - player + living zombie capsules
const RAGDOLL := 4 ## bit for layer 3 - zombie corpse physical bones

## Why ragdolls need their own layer: a dead zombie's PhysicalBone3D shapes
## spawn at whatever pose the zombie died in, which is often overlapping the
## player or another zombie's capsule (mid-attack range). If they shared a
## layer, the physics engine would see that overlap as a sudden collision and
## violently shove the bones apart to resolve it - corpses launching into the
## sky on death. Keeping ragdoll bones on their own layer, colliding only with
## WORLD, means they still fall and rest on the ground normally but can never
## explode against a living actor.
