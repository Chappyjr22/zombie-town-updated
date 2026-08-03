# Asset Manifest

Index of every binary asset in `assets/`. **Look here instead of scanning `assets/` directly** — binary files are unreadable and expensive to enumerate. Update this file whenever an asset is added, replaced, or removed.

Columns: Path · Source · License · Notes (poly count / rig / usage)

## Characters

| Path | Source | License | Notes |
|---|---|---|---|
| `characters/soldier.glb` | [poly.pizza/m/PpLF4rt4ah](https://poly.pizza/m/PpLF4rt4ah) — "Character Soldier" by Quaternius | CC0 | Rigged + animated: `Idle`, `Idle_Shoot`, `Run`, `Run_Gun`, `Jump`, `Jump_Idle`, `Jump_Land`, `Duck`, `Punch`, `HitReact`, `Death`, `Wave`, `Yes`, `No`. Candidate for the player model — has run/shoot poses out of the box. |
| `characters/swat.glb` | [poly.pizza/m/Btfn3G5Xv4](https://poly.pizza/m/Btfn3G5Xv4) — "SWAT" by Quaternius | CC0 | Rigged + animated: `Idle`, `Idle_Gun`, `Idle_Gun_Pointing`, `Idle_Gun_Shoot`, `Gun_Shoot`, `Run`, `Run_Shoot`, `Run_Left/Right/Back`, `Walk`, `Roll`, `Kick_Left/Right`, `Punch_Left/Right`, `HitRecieve` (x2), `Death`, plus sword/interact/wave extras. Larger animation set than `soldier.glb` — likely the better player-model pick. |
| `characters/mixamo_soldier.glb` | [Adobe Mixamo](https://www.mixamo.com/) — Gasmask Soldier character + animation library | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Current player **world model** — the third-person body other players see. Consolidated runtime glTF with `idle`, `walk`, `run`, `move_back`, `strafe_left`, `strafe_right`, `crouch_idle`, `crouch_walk`, `jump_start`, `jump_air`, `jump_land`, `fire`, `fire_move`, `reload`, `hit`, and `death`. Raw FBX downloads live in `characters/mixamo_soldier/` and are excluded from Godot import by `.gdignore`. |
| `animations/rifle/*.res` (49 clips) | Adobe Mixamo — "Rifle 8-Way Locomotion Pack", converted by `tools/build_clips.gd` | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | **The player's two-handed locomotion set**, used by every weapon whose `WeaponData.locomotion_set` is `rifle` — which is all of them but the two handguns. Walk, run, sprint and crouch, each with all eight directions, plus aimed idles, jumps, turns and deaths — every clip authored with a rifle held. Loaded over the model's own clips at runtime by `scripts/player/player.gd`. Replaces the model's stock locomotion, which is largely empty-handed: measured, its strafes carry the hands **0.04m** above the hips against **0.43m** for a weapon held ready, so stepping sideways dropped the rifle to the character's waist. The pack ships the same `Ch35` character as `mixamo_soldier.glb`, so the rig matches and nothing needs retargeting. Its bundled 140MB character mesh is **not** imported — we already have the model. |
| `animations/rifle/idle_aiming_braced.res` | Adobe Mixamo — "Rifle Aiming Idle", downloaded separately before the 8-way pack | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | The standing idle actually used, in preference to the pack's own `idle_aiming` (which is still on disk). Carries the weapon **6.8cm higher** with the hands **5.8cm further apart** — a braced hold rather than a relaxed one. Being from the pack buys the alternative nothing: measured against the average pose of the eight clips it crossfades with, the two sit 0.293m and 0.317m away, and 2.4cm is nothing across a ~0.1s blend. |
| `animations/pistol/*.res` (20 clips) | Adobe Mixamo — "Pistol/Handgun Locomotion Pack", converted by `tools/build_clips.gd -- pistol` | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | **The one-handed locomotion set**, selected by `pistol.tres` and `revolver.tres`. Idle, walk, run, backpedal, a strafe per side, curving "arc" runs that stand in for the diagonals, a jump pair, and a kneel. Measured at **+0.36m to +0.49m** hands-above-hips throughout, so nothing drops the weapon. Smaller than the rifle pack in two ways that `scripts/player/locomotion_sets.gd` covers explicitly: **no sprint** (the run tier is reused and its stride sped up instead) and **no crouch-walk** (the walk tier is reused, so the capsule shrinks but the body doesn't visibly crouch). Same `Ch35` rig; bundled character mesh not imported. |

They are loose `Animation` resources rather than a rebuilt `.glb`, so the player model itself is never rewritten. Their track paths (`Skeleton3D:mixamorig_*`) already address the soldier's skeleton, so they drop straight on with no retargeting. The tool also **strips horizontal root motion** — Mixamo bakes metres of travel into its locomotion clips, which makes the model surge and snap back against a physics-driven body.

The two legacy Quaternius skeletons are both named `CharacterArmature` internally but are **not** guaranteed bone-compatible (different node counts — 78 vs 85). The Mixamo player uses a different `mixamorig_` skeleton. Don't swap animations between these models without checking Godot's animation retargeting first.

## Zombies

| Path | Source | License | Notes |
|---|---|---|---|
| `zombies/zombie.glb` | [poly.pizza/m/JoBvxIUpZP](https://poly.pizza/m/JoBvxIUpZP) — "Zombie" by Quaternius | CC0 | **Unused** — never wired into any `.tscn`. `zombie-alt.glb` (Quaternius's other zombie) was the one actually in play as `scenes/zombies/zombie.tscn`; that whole scene was removed for not matching this project's semi-realistic look once the Mixamo zombies (below) landed. This leftover file was orphaned independently of that and was never referenced to begin with — flagged here rather than deleted, since removing it wasn't asked for. |
| `zombies/zombie-crawler.glb` | [poly.pizza/m/Htcsn9OrXJ](https://poly.pizza/m/Htcsn9OrXJ) — "Zombie half" by Quaternius | CC-BY | Legless/crawler variant. Rigged + animated: `Idle`, `Walk`, `Run`, `Crawl`, `Jump`, `Jump_Idle`, `Jump_Land`, `HitRecieve`, `Death`. **Requires attribution** — credit "Quaternius" — added to README credits. |
| `zombies/scary_zombie.glb` | Adobe Mixamo — "Scary Zombie Pack" (`Ch10_nonPBR`) | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Semi-realistic current zombie variant with high-resolution embedded textures and a 65-bone Mixamo rig. Consolidated clips: `Idle`, `Walk`, `Run`, `Attack`, `Death`, `NeckBite`, `Crawl`, `Bite`, `BiteAlt`, `DeathAlt`, `CrawlRun`, and `Scream`. |
| `zombies/cop_zombie.glb` | Adobe Mixamo — "Copzombie L Actisdato" | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Police zombie variant with a 67-bone Mixamo rig. The Scary Zombie Pack's 12 clips are retargeted by matching Mixamo bone names; the cop's two additional eye bones retain their rest pose. |

## Weapons

| Path | Source | License | Notes |
|---|---|---|---|
| `weapons/cc0/*.glb` (9 files) | [3dmodelscc0.itch.io/free-cc0-guns-explosives-pack](https://3dmodelscc0.itch.io/free-cc0-guns-explosives-pack) — "Free CC0 Guns & Explosives Pack" | **CC0 1.0** (see `weapons/cc0/LICENSE.txt`) | **The current weapon pack.** `ak47`, `m4a1`, `shotgun`, `sniper`, `suomi-kp`, `grease-gun`, `luger`, `makarov`, `flare-gun` — all 9 now wired to a `WeaponData` and wall-buyable (`flare-gun` was the last holdout: already imported with sockets placed in `scenes/weapons/flare-gun.tscn`, just never given a `.tres`/level placement until `resources/weapons/flare_gun.tres`). Semi-realistic, 1.7k–9.3k tris, embedded PBR materials, and **authored at real-world scale** (the AK is 0.877m) so nothing needs resizing. Taken as the already-converted GLBs from the sibling [zombie-town-online](https://github.com/Chappyjr22/zombie-town-online) repo rather than the source RAR, which ships FBX with reportedly patchy materials. The source pack also has explosives (C4, claymores, mines, grenades, molotov) not yet pulled in — useful for traps later. |

Each weapon is wrapped in a `scenes/weapons/*.tscn` carrying three `Marker3D` sockets. `Grip` and `Foregrip` are **wrist positions** — deliberately offset below and to the side of the weapon by the thickness of a hand — and `Muzzle` sits on the bore, with **its own facing (`-Z`) defining the barrel direction**. That last part matters: a line drawn between the two hand sockets is neither level nor straight down the weapon, so using it to orient the gun tips it downward and yaws it. Generated by `tools/build_weapon_scenes.gd`, which seeds them off the model's `Trigger` part and then never overwrites them, so editor tuning is safe. Note the pack is **not** consistent about which way the muzzle faces — `ak47`, `shotgun` and `makarov` point +Z, the rest -Z — which is exactly why the sockets define direction rather than it being inferred.

### Superseded

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

The Quaternius weapons and their Scope/Silencer/Flashlight attachments are no longer referenced by any `WeaponData`, but are left in place until the new pack is confirmed in-game. Delete them once it is.

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
| `props/city-kit-suburban/*.glb` (40 files) | Kenney "City Kit (Suburban)" v2.0 ([kenney.nl/assets/city-kit-suburban](https://kenney.nl/assets/city-kit-suburban)) | **CC0 1.0** (see `city-kit-suburban/LICENSE.txt`) | **Stylized low-poly, not the project's usual semi-realistic bar** — picked anyway as a free placeholder town while a matched-style pack (see "Still needed" below) stays a paid option. 21 building variants (`building-type-a` through `-u`), plus `driveway-long/short`, 8 `fence-*` sizes, `path-long/short`/`path-stones-*`, `planter`, `tree-large/small`. GLB format; each `.glb` references the shared `Textures/colormap.png` alongside it by relative path rather than embedding it - that folder has to ship with the `.glb` files, not just the models themselves. No OBJ/FBX copies kept, matching the project's glTF-only convention. **Not real-world scale** - measured by probe: buildings run only ~0.9-1.8m footprint, ~0.75-1.25m tall, smaller than the 1.8m player capsule. This kit reads as built for a toy-scale/diorama city-builder game, not a walkable human-scale one - needs a uniform scale-up (~6x gets single-story houses into a believable 4.4-11m range) when placed, unlike the weapon pack, which needed none. |

## Environment — Maple Row (new map, in progress)

| Path | Source | License | Notes |
|---|---|---|---|
| `props/maple_row/rowhouse_unit.glb` | [meshy.ai](https://www.meshy.ai) — Image to 3D, "a single abandoned residential street..." prompt (see `docs/ASSET_PIPELINE.md`) | Meshy AI generation, project use only | Repeatable street-facing rowhouse module, boarded window + door (facade only, not a door cut — never intended to be enterable). Measured 7.55m × 6.0m × 3.25m (W×H×D); height locked via export dialog, width/depth ran larger/shallower than the 5m×8m prompted. Solid exterior shell, no interior. |
| `props/maple_row/rowhouse_damaged.glb` | same prompt set, damaged variant | Meshy AI generation, project use only | Visual-variety twin of `rowhouse_unit.glb` — partial roof collapse, same brick/weathering palette. Measured 6.87m × 6.0m × 2.84m. Solid exterior shell, no interior. |
| `props/maple_row/sidewalk_segment.glb` | same prompt set | Meshy AI generation, project use only | Measured 1.61m × 0.15m × 1.04m against a 3m×2m×0.15m prompt — height (0.15m) is correct, length/width came in much smaller. Safe to non-uniformly rescale in Godot to the target footprint (plain concrete texture, no brick-style pattern to distort). |
| `props/maple_row/road_segment.glb` | same prompt set | Meshy AI generation, project use only | Measured 2.33m × 0.05m × 2.33m. Raw generation had real geometric undulation (not just texture) — flattened by hand in Blender (all vertices scaled to 0 on the up axis, UVs/texture untouched) before this copy. Re-verified flat after the fix. |
| `props/maple_row/corner_store.glb` | Meshy AI, "Corner Store" prompt (`docs/ASSET_PIPELINE.md` anchor-building set) | Meshy AI generation, project use only | Map's starting-room building. Measured 6.86m × 4.0m × 3.93m against a 8m×8m×4m prompt (height correct, footprint smaller — accepted as-is, appropriately cramped for a starting room). Hollow interior confirmed. Door came through boarded/solid rather than an open gap — cut through with a Blender boolean (`tools/blender_inspect.py`-style front-face render located the opening, `Boolean Difference` cut it); the cut clipped a small entry step that stuck out past the wall face — minor, not fixed. |
| `props/maple_row/school_ground.glb` | Meshy AI, "School — ground floor shell" prompt | Meshy AI generation, project use only | Measured 10.81m × 4.5m × 5.59m against 20m×12m×4.5m (height correct). Columned entry portico with a boarded double-door — cut through via Blender boolean, sized narrow enough in X to pass between the columns without touching them; portico/pediment fully intact after the cut. |
| `props/maple_row/school_upper.glb` | Meshy AI, "School — second floor module" prompt | Meshy AI generation, project use only | Measured 10.27m × 4.5m × 4.83m — height matches `school_ground.glb` exactly; width/depth are 5-14% off and need a non-uniform Godot-side scale (`scale = (10.81/10.27, 1.0, 5.59/4.83)`) to align footprints before stacking. Front windows came through already open — no cutting needed. |
| `props/maple_row/garage.glb` | Meshy AI, "Garage / Gas Station" prompt | Meshy AI generation, project use only | Measured 8.34m × 5.0m × 3.97m against 15m×10m×5m (height correct). Bay door came through as a closed corrugated roll-door mesh, not an opening — cut via Blender boolean. **Known minor artifact**: a small leftover fragment of the door panel remains in the bottom-left corner of the opening (cutter didn't fully clear that edge) — reads passably as debris, not yet cleaned up. Canopy/support-post detail from the original prompt was deliberately **not** requested of Meshy (thin support posts are the one geometry category that reliably fails, per the fence/vine findings below) — build that piece procedurally in Godot instead, same as the bank's portico columns in `town.tscn`. |
| `props/maple_row/apartment_ground.glb` | Meshy AI, "Apartment Building — ground floor shell" prompt | Meshy AI generation, project use only | Measured 4.71m × 3.0m × 3.01m against 12m×12m×3m — height correct, footprint notably smaller than the rest of the set (~39%/25% of the request). Accepted as-is rather than regenerated; height is made up for by stacking floors. Door and entry stoop came through already open, no cutting needed. |
| `props/maple_row/apartment_upper.glb` | Meshy AI, "Apartment Building — upper floor module" prompt, second attempt | Meshy AI generation, project use only | First generation (`apartment_upper_3d_v2`, discarded, not copied in) came back as a flat facade-only panel (0.7m deep) rather than a hollow box — regenerated. This version measured 4.49m × 3.0m × 2.8m, a real hollow box close to `apartment_ground.glb`'s footprint; needs a small Godot-side scale (`scale = (4.71/4.49, 1.0, 3.01/2.8)`) to match exactly. Middle opening between the two windows came through already cut. Only asset in this set with a real baked normal map (from the "image-to-3d" pipeline variant, unlike every other piece's Text/Image-to-3D-then-remesh path). |
| `props/maple_row/fountain.glb` | Meshy AI, "Plaza fountain" prompt | Meshy AI generation, project use only | Measured 6.03m diameter × 2.0m tall against a 4m/2m prompt — came out *larger* than requested (only asset in the set to do so). Kept at generated size; works well as the plaza's central landmark. Dry cracked basin, plain square pedestal, no thin railings/piping. No cutting needed. |

**General notes for this set**: every model reports `normal_enabled: false` (baked normal maps dropped) except `apartment_upper.glb` — matches the known Meshy remesh behavior documented under "AI-generated environment assets (Meshy)" below. None of these have been placed in a `.tscn` yet; `tools/build_maple_row_level.gd` (once written) is what will instance them into the actual map. Height is the only dimension ever locked correctly straight out of Meshy's export dialog — width/depth vary per-generation and were either accepted as-is or corrected with a scale, noted per-row above.

## Animations

Every runtime character/zombie model in `assets/models/characters/` and `assets/models/zombies/` has its animation clips baked into the same `.glb` (see the tables above for clip names). Godot imports these as an `AnimationPlayer`/`AnimationLibrary` on the model's scene automatically. The Mixamo player's individual FBX downloads are retained only as ignored source files; the game loads their consolidated `mixamo_soldier.glb`.

**Not every third-person clip works in first person.** The game renders in true first person — the camera sits at the player's own head, so the body's animation *is* the first-person animation. Clips that read fine from outside can point the weapon well off the crosshair: "Rifle Idle" carries it across the chest, and "Reloading" travels 3.5m. `tools/probe_clip_poses.gd` scores a candidate clip on how squarely it holds the weapon down the view, and `tools/build_aim_idle.gd` shows how to pull a better one out of the raw Mixamo FBXs. Check a clip with the probe before wiring it into the player.

If a future character model needs animations it doesn't ship with, Quaternius's CC0 "Universal Animation Library" packs (Unreal-Godot `.glb` variants, retargetable via Godot's bone-mapping) are the fallback — not currently pulled into the repo since it wasn't needed.

## Textures

| Path | Source | License | Notes |
|---|---|---|---|
| `textures/town/asphalt_02/*` | [Poly Haven — Asphalt 02](https://polyhaven.com/a/asphalt_02) | CC0 | Road/ground surface for `town.tscn`. |
| `textures/town/brick_wall_10/*` | [Poly Haven — Brick Wall 10](https://polyhaven.com/a/brick_wall_10) | CC0 | General Store walls. |
| `textures/town/beige_wall_001/*` | [Poly Haven — Beige Wall 001](https://polyhaven.com/a/beige_wall_001) | CC0 | Bank and Church stucco walls. |
| `textures/town/brown_planks_03/*` | [Poly Haven — Brown Planks 03](https://polyhaven.com/a/brown_planks_03) | CC0 | Bar and Diner wood siding. |
| `textures/town/brown_planks_08/*` | [Poly Haven — Brown Planks 08](https://polyhaven.com/a/brown_planks_08) | CC0 | Wood-floored building interiors. |
| `textures/town/checkered_pavement_tiles/*` | [Poly Haven — Checkered Pavement Tiles](https://polyhaven.com/a/checkered_pavement_tiles) | CC0 | Bank and Church tile floors. |
| `textures/town/grey_roof_01/*` | [Poly Haven — Grey Roof 01](https://polyhaven.com/a/grey_roof_01) | CC0 | Bar, Diner, and General Store roofs. |
| `textures/town/ceramic_roof_01/*` | [Poly Haven — Ceramic Roof 01](https://polyhaven.com/a/ceramic_roof_01) | CC0 | Church roof and tower. |
| `textures/town/brushed_concrete/*` | [Poly Haven — Brushed Concrete](https://polyhaven.com/a/brushed_concrete) | CC0 | Bank facade and columns. |
| `textures/town/corrugated_iron/*` | [Poly Haven — Corrugated Iron](https://polyhaven.com/a/corrugated_iron) | CC0 | Perimeter fence and fire barrels. |

Each is a 1k `diff`/`nor_gl`/`rough` JPG triplet, downloaded via the Poly Haven API. Chosen over Kenney's stylized CC0 kits specifically to keep `town.tscn` in the same "semi-realistic PBR" register as the existing weapons/characters rather than introducing a cartoonish low-poly style — see `docs/ASSET_PIPELINE.md`'s realism/quality bar.

## Audio

### `audio/weapons/`

| Path | Source | License | Notes |
|---|---|---|---|
| `fire-pistol.mp3` | Snake's Authentic Gun Sounds 2 ([f8studios.itch.io/snakes-second-authentic-gun-sounds-pack](https://f8studios.itch.io/snakes-second-authentic-gun-sounds-pack)), "9mm Single" | Free — commercial use OK, no credit required | Real 9mm pistol shot. Pair with `weapons/Pistol_1.fbx`. |
| `fire-revolver.mp3` | Snake's Authentic Gun Sounds ([f8studios.itch.io/snakes-authentic-gun-sounds](https://f8studios.itch.io/snakes-authentic-gun-sounds)), "22LR Single" | Free — commercial use OK, no credit required | Placeholder for `weapons/Revolver_1.fbx` — a real .38/.357 sound would fit better; swap later if available. |
| `fire-assault-rifle.mp3` | same pack, "556 Single" | same | 5.56 rifle shot. Pair with `weapons/AssaultRifle_1.fbx` and `weapons/Bullpup_1.fbx`. |
| `fire-assault-rifle-2.mp3` | same pack, "762x39 Single" | same | AK-pattern round. Pair with `weapons/AssaultRifle2_1.fbx`. |
| `fire-submachine-gun.mp3` | same pack, "556 Burst" | same | Fast burst, works as SMG auto-fire. Pair with `weapons/SubmachineGun_1.fbx`. |
| `fire-sniper-rifle.mp3` | same pack, "762x54r Single" | same | Big sniper/DMR-caliber shot. Pair with `weapons/SniperRifle_1.fbx`. |
| `fire-shotgun.mp3` | Snake's Authentic Gun Sounds 2, "20 Gauge Single" | same | Pair with `weapons/Shotgun_1.fbx` and `weapons/Shotgun_SawedOff.fbx`. |
| `reload-lmg.mp3`, `reload-pistol.mp3`, `reload-rifle.mp3`, `reload-shell.mp3`, `reload-shotgun.mp3` | Pixabay, via [chappyjr22/zombie-town-online](https://github.com/chappyjr22/zombie-town-online) | [Pixabay Content License](https://pixabay.com/service/license-summary/) | Present but **unused** — superseded below. Kept in case a future weapon class (LMG, shell-loaded shotgun) wants a distinct sample. |
| `weapon-handle.mp3`, `weapon-holster.ogg`, `weapon-metal-load.ogg`, `weapon-pistol-reload.ogg`, `weapon-smg-reload.ogg` | Pixabay, via zombie-town-online | Pixabay Content License | **The actual reload sounds every `WeaponData.reload_sound` uses** — `weapon-pistol-reload.ogg` for the two handguns, `weapon-smg-reload.ogg` for everything else. This matches zombie-town-online's own `reloadSampleKind()`/`RELOAD_AUDIO_LENGTH` mapping exactly (its `reloadRifle`/`reloadShotgun`/`reloadLmg`/`reloadWonder` kinds all resolve to the same SMG sample; only `reloadPistol` and shell-by-shell reloads get a distinct one). The `reload-*.mp3` row above was what got wired here initially and was wrong — those files were never the browser build's real reload audio. |
| `impact-flesh.ogg`, `impact-metal-1.ogg` .. `impact-metal-4.ogg` | CC0 field recordings (Freesound "Punch" + Minetest default asset library), via zombie-town-online | CC0 | Bullet-impact sounds. |

### `audio/zombies/`

| Path | Source | License | Notes |
|---|---|---|---|
| `zombie-moan.mp3` | [SoundBible — Zombie Moan](https://soundbible.com/1035-Zombie-Moan.html) by Mike Koenig, via zombie-town-online | CC BY 3.0 | **Requires attribution** — credited in README. |
| `zombie-attack.mp3` | [SoundBible — Zombie Attack Walk](https://soundbible.com/1030-Zombie-Attack-Walk.html) by Mike Koenig, via zombie-town-online | CC BY 3.0 | **Requires attribution** — credited in README. |
| `zombie-hurt.mp3` | [SoundBible — Zombie Gets Attacked](https://soundbible.com/1040-Zombie-Gets-Attacked.html) by Mike Koenig, via zombie-town-online | CC BY 3.0 | **Requires attribution** — credited in README. |
| `zombie-death.mp3` | [SoundBible — Zombie Long Death](https://soundbible.com/1042-Zombie-Long-Death.html) by Mike Koenig, via zombie-town-online | CC BY 3.0 | **Requires attribution** — credited in README. |

### `audio/player/`

| Path | Source | License | Notes |
|---|---|---|---|
| `player-hurt-1.mp3`, `player-hurt-2.mp3`, `player-hurt-3.mp3` | Mixkit ("Boxer getting hit," "Fighting man's voice," "Fighting man voice of pain"), via zombie-town-online | [Mixkit Sound Effects Free License](https://mixkit.co/license/) | Player hit-react vocals. |
| `footstep-1.mp3` .. `footstep-4.mp3` | via zombie-town-online | **Unconfirmed** | Not itemized in the source repo's credits — origin unclear. Fine for this private, non-commercial use; verify/replace before any wider distribution. |

### `audio/environment/`

| Path | Source | License | Notes |
|---|---|---|---|
| `ambience-town.ogg` | [Freesound — "Ambience: Night in nature (South of France) - 6"](https://freesound.org/people/SamuelGremaud/sounds/437003/) by SamuelGremaud, via zombie-town-online | CC0 | |
| `ambience-nuketown.mp3` | Freesound, via zombie-town-online | CC0 | |
| `ambience-blacksire.ogg` | "Room Ambience" by gchase (preserved in [Coming Out Simulator](https://github.com/ncase/cos)), via zombie-town-online | CC0 | |
| `fire-crackle.ogg` | [Freesound — "Fire, Campfire, Bonfire"](https://freesound.org/people/yaros_nov/sounds/434026/) by yaros_nov, via zombie-town-online | CC0 | |

### `audio/ui/`

| Path | Source | License | Notes |
|---|---|---|---|
| `interact-buy.mp3`, `interact-deny.mp3`, `interact-pickup.mp3` | Kenney (Impact Sounds / RPG Audio / Interface Sounds / Sci-Fi Sounds), via zombie-town-online | CC0 | No attribution required. |

---

## Still needed

- **A semi-realistic town/building pack, to replace `props/city-kit-suburban/`** once the stylized-low-poly placeholder has served its purpose. Researched and shortlisted: ["Realistic Buildings 3D Assets Pack For Godot" Vol. 1](https://www.gamedevmarket.net/asset/realistic-buildings-3d-assets-pack-for-godot) by cacybernetic — $15, 40+ models, 4K PBR textures, ships in both FBX and glTF/GLB, each model comes with its own collider already set up, and the theming (abandoned/post-apocalyptic/urban) fits a zombie setting better than a generic suburb would. A Vol. 2 exists at the same price if more variety is needed. **License wasn't fully verified** (Sketchfab listing only confirmed a "NoAI" tag, unrelated to game-use rights) — read the actual license text on the purchase page before buying. Free stylized alternative already in use for comparison: Kenney's own City Kit (Suburban), CC0.
- **Shotgun reload SFX** could use a more distinct pump-action sound (currently shares the generic `weapon-smg-reload.ogg`, same as the browser build) — Snake's Second Gun Sounds pack has pump/shell-load sounds not yet pulled in, and `weapon-metal-load.ogg` (already in the repo) is the browser build's dedicated shell-by-shell sample if the shotgun ever reloads incrementally instead of as one clip.
- **More weapon variants** if the starter set (one per weapon class) feels too samey.
- **Textures** beyond what ships baked into the models above (all current models are self-contained).
- **Footstep source verification** — see note above.

---

## Sourcing shortlist

- **Mixamo** (mixamo.com) — free rigged/animated humanoid characters + a large animation library (walk/run/aim/reload/death). Best source for the soldier player model and zombie base models with usable animations.
- **Kenney.nl** — CC0, no attribution needed. Weapon and prop packs.
- **Quaternius** — CC0 character/vehicle packs.
- **Sketchfab** — filter "Downloadable" + CC license; verify license per-model before adding it here.
- **OpenGameArt.org**, **Poly Haven** (textures/HDRIs), **Godot Asset Library**.

Every asset added to this project must be logged in the table above with its source and license before being committed.
