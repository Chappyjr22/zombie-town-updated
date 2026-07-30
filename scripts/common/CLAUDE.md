# scripts/common

Small shared helpers with no gameplay opinions of their own, used by more than one system (currently `scripts/player` and `scripts/ai`).

- `node_utils.gd` (`class_name NodeUtils`) — `find_first_of_type()` / `find_all_of_type()` walk an instanced scene looking for descendants by class name (e.g. `"AnimationPlayer"`, `"Skeleton3D"`, `"MeshInstance3D"`). Used instead of hardcoded node paths because the imported model scenes' internal hierarchy wasn't confirmed in-editor when this code was written (no Godot editor access from the authoring session).
- `physics_layers.gd` (`class_name PhysicsLayers`) — named constants for the collision layer bit values (`WORLD`, `ACTORS`, `RAGDOLL`). Both `scripts/player/player.gd` and `scripts/ai/zombie.gd` set their `collision_layer`/`collision_mask` from these instead of hardcoding the numbers, so the three layers stay consistent project-wide. See the file's own comments for why ragdolls specifically need a separate layer from living actors.

Keep this folder for genuinely cross-system utilities only — if something is specific to one system, it belongs in that system's own folder instead.
