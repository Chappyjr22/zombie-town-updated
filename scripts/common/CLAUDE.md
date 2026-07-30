# scripts/common

Small shared helpers with no gameplay opinions of their own, used by more than one system (currently `scripts/player` and `scripts/ai`).

- `node_utils.gd` (`class_name NodeUtils`) — `find_first_of_type()` / `find_all_of_type()` walk an instanced scene looking for descendants by class name (e.g. `"AnimationPlayer"`, `"Skeleton3D"`, `"MeshInstance3D"`). Used instead of hardcoded node paths because the imported model scenes' internal hierarchy wasn't confirmed in-editor when this code was written (no Godot editor access from the authoring session).

Keep this folder for genuinely cross-system utilities only — if something is specific to one system, it belongs in that system's own folder instead.
