# Asset Manifest

Index of every binary asset in `assets/`. **Look here instead of scanning `assets/` directly** — binary files are unreadable and expensive to enumerate. Update this file whenever an asset is added, replaced, or removed.

Columns: Path · Source · License · Notes (poly count / rig / usage)

## Characters

| Path | Source | License | Notes |
|---|---|---|---|
| `characters/soldier.glb` | [poly.pizza/m/PpLF4rt4ah](https://poly.pizza/m/PpLF4rt4ah) — "Character Soldier" by Quaternius | CC0 | Rigged humanoid, unarmed pose. Candidate for the player model. |
| `characters/swat.glb` | [poly.pizza/m/Btfn3G5Xv4](https://poly.pizza/m/Btfn3G5Xv4) — "SWAT" by Quaternius | CC0 | Rigged humanoid, tactical outfit. Alt player/teammate model. |

No animations are bundled with these — they're static-pose meshes. See "Still needed" below.

## Zombies

| Path | Source | License | Notes |
|---|---|---|---|
| `zombies/zombie.glb` | [poly.pizza/m/JoBvxIUpZP](https://poly.pizza/m/JoBvxIUpZP) — "Zombie" by Quaternius | CC0 | Primary zombie model, same low-poly style as the soldier/SWAT models. |
| `zombies/zombie-alt.glb` | [poly.pizza/m/VlXjG0N8Eg](https://poly.pizza/m/VlXjG0N8Eg) — "Zombie" by Quaternius | CC0 | Alternate pose/variant for visual variety. |
| `zombies/zombie-crawler.glb` | [poly.pizza/m/Htcsn9OrXJ](https://poly.pizza/m/Htcsn9OrXJ) — "Zombie half" by Quaternius | CC-BY | Legless/crawler variant. **Requires attribution** — credit "Quaternius" — added to README credits. |

No animations bundled. See "Still needed" below.

## Weapons

| Path | Source | License | Notes |
|---|---|---|---|
| `weapons/AssaultRifle_1.fbx` | Quaternius "50+ LowPoly Guns" ([quaternius.itch.io/50-lowpoly-guns](https://quaternius.itch.io/50-lowpoly-guns)) | CC0 | Assault rifle, variant 1 of 9 in the source pack. |
| `weapons/AssaultRifle2_1.fbx` | same pack | CC0 | Second assault rifle family, variant 1 of 4. |
| `weapons/Bullpup_1.fbx` | same pack | CC0 | Bullpup rifle, variant 1 of 3. |
| `weapons/Pistol_1.fbx` | same pack | CC0 | Pistol, variant 1 of 6. |
| `weapons/Revolver_1.fbx` | same pack | CC0 | Revolver, variant 1 of 5. |
| `weapons/Shotgun_1.fbx` | same pack | CC0 | Shotgun, variant 1 of 4. |
| `weapons/Shotgun_SawedOff.fbx` | same pack | CC0 | Sawed-off shotgun. |
| `weapons/SniperRifle_1.fbx` | same pack | CC0 | Sniper rifle, variant 1 of 6. |
| `weapons/SubmachineGun_1.fbx` | same pack | CC0 | SMG, variant 1 of 5. |
| `weapons/Scope_1.fbx` | same pack | CC0 | Attachment: scope. |
| `weapons/Silencer_1.fbx` | same pack | CC0 | Attachment: suppressor. |
| `weapons/Flashlight.fbx` | same pack | CC0 | Attachment: rail-mounted flashlight. |

The source pack has more variants (up to 6 per weapon type) plus bipod/bayonet/stock/tripod/grip attachments not yet pulled in — grab more from the same zip if a wider loadout is needed.

## Vehicles

| Path | Source | License | Notes |
|---|---|---|---|
| `vehicles/Cop.fbx` | Quaternius "Realistic Car Pack" ([quaternius.itch.io/lowpoly-cars](https://quaternius.itch.io/lowpoly-cars)) | CC0 | Police cruiser. |
| `vehicles/SUV.fbx` | same pack | CC0 | SUV. |
| `vehicles/NormalCar1.fbx` | same pack | CC0 | Generic sedan. |
| `vehicles/Taxi.fbx` | same pack | CC0 | Taxi. |
| `vehicles/SportsCar.fbx` | same pack | CC0 | Sports car. |

Static meshes only, no wheel rigging/suspension — fine for background dressing or barricades now, would need rigging for a drivable vehicle later.

## Props

| Path | Source | License | Notes |
|---|---|---|---|
| `props/*.fbx` (81 files) | Kenney "Survival Kit" ([kenney.nl/assets/survival-kit](https://kenney.nl/assets/survival-kit)) | CC0 | Full pack: barrels, boxes, campfires, fences, tents, tools, trees, rocks, workbenches, structure pieces. No attribution required (Kenney never requires it, but credit is appreciated). |
| `props/colormap.png` | same pack | CC0 | Shared texture atlas used by all the above FBX files — required for correct materials, don't delete. |

## Animations

| Path | Source | License | Notes |
|---|---|---|---|
| _(none yet)_ | | | Character/zombie models above are unanimated. Need a walk/run/aim/reload/death animation source — Mixamo (requires an Adobe login this session can't do) or Quaternius's "Universal Animation Library" ([quaternius.itch.io/universal-animation-library-2](https://quaternius.itch.io/universal-animation-library-2), CC0) as a retargetable alternative. |

## Textures

| Path | Source | License | Notes |
|---|---|---|---|

## Audio

| Path | Source | License | Notes |
|---|---|---|---|
| _(none yet)_ | | | Not sourced yet — gunfire/zombie/footstep/ambience SFX still needed. |

---

## Still needed

- **Animations.** None of the character/zombie models above are rigged with usable game animations yet. Next step: pull Quaternius's Universal Animation Library (CC0, retargetable to these models' skeletons) or have Jacob export Mixamo animations manually (walk/run/sprint/aim/fire/reload/death) and drop them in `assets/animations/`.
- **Audio.** Gunfire, zombie vocals, footsteps, ambience — not sourced yet.
- **More weapon variants** if the starter set (one per weapon class) feels too samey.

---

## Sourcing shortlist

- **Mixamo** (mixamo.com) — free rigged/animated humanoid characters + a large animation library (walk/run/aim/reload/death). Best source for the soldier player model and zombie base models with usable animations.
- **Kenney.nl** — CC0, no attribution needed. Weapon and prop packs.
- **Quaternius** — CC0 character/vehicle packs.
- **Sketchfab** — filter "Downloadable" + CC license; verify license per-model before adding it here.
- **OpenGameArt.org**, **Poly Haven** (textures/HDRIs), **Godot Asset Library**.

Every asset added to this project must be logged in the table above with its source and license before being committed.
