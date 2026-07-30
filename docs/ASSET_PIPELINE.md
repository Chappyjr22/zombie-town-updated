# Asset Pipeline

## Sourcing

Free assets only, license-checked before use. Preferred sources, roughly in order of use:

| Need | Best source |
|---|---|
| Soldier / human character + animations | Mixamo |
| Zombie base model + animations | Mixamo (retarget a humanoid, reskin) or Sketchfab |
| Guns | Kenney.nl weapon packs, Sketchfab (CC) |
| Vehicles | Kenney.nl, Quaternius |
| Environment props | Kenney.nl, OpenGameArt.org |
| Textures / PBR materials | Poly Haven |

## Adding a new asset — checklist

1. Download, confirm the license permits use in a free, non-commercial, friends-only project (CC0 and CC-BY are both fine; note attribution requirement for CC-BY).
2. Drop the file under the matching `assets/<category>/<subfolder>/` directory.
3. Add a row to `ASSET_MANIFEST.md` (path, source URL, license, notes).
4. If it needs attribution, also add it to the "Credits" section of the root `README.md`.
5. Import into Godot, set reasonable import settings (see below), commit.

## Import settings baseline

- Characters/zombies: import as glTF, keep skeleton, generate collision only where needed (usually not — capsule/box colliders are hand-authored in the scene instead).
- Textures: let Godot generate mipmaps; compress with VRAM compression (already enabled in `project.godot`).
- Keep source files (`.blend`, `.fbx`) out of the repo where possible — commit the exported `.glb`/`.gltf` only, to keep the repo lean.

## Realism/quality bar

Aiming for "decent, semi-realistic" — not stylized low-poly, not AAA. Prioritize models with:
- PBR textures (albedo/normal/roughness) rather than flat-shaded low-poly.
- Reasonable poly counts for real-time (characters ~10-30k tris, weapons ~5-15k tris) — Godot's Forward+ renderer handles this comfortably on modern hardware.
