# scripts/environment

Owns: reusable environmental effects that dress a level but aren't part of any specific system (player/ai/weapons/ui). Currently just fire.

- `fire_light.gd` (`class_name FireLight`) — flickering `OmniLight3D`. Attached to the light half of every fire prop `tools/build_town_level.gd` places (fountain, fire barrels); the particles/embers/smoke/scorch decal are plain nodes built directly in the generator, not scripted, since they don't need per-frame behavior beyond what `GPUParticles3D` already animates on its own.

Before adding a new environmental behavior here, check whether it's actually generator-time (belongs in `tools/build_*.gd` as static node setup) versus genuinely needing a running script - most level dressing doesn't.
