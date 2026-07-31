# Asset Manifest

Index of every binary asset in `assets/`. **Look here instead of scanning `assets/` directly** — binary files are unreadable and expensive to enumerate. Update this file whenever an asset is added, replaced, or removed.

Columns: Path · Source · License · Notes (poly count / rig / usage)

## Characters

| Path | Source | License | Notes |
|---|---|---|---|
| `characters/soldier.glb` | [poly.pizza/m/PpLF4rt4ah](https://poly.pizza/m/PpLF4rt4ah) — "Character Soldier" by Quaternius | CC0 | Rigged + animated: `Idle`, `Idle_Shoot`, `Run`, `Run_Gun`, `Jump`, `Jump_Idle`, `Jump_Land`, `Duck`, `Punch`, `HitReact`, `Death`, `Wave`, `Yes`, `No`. Candidate for the player model — has run/shoot poses out of the box. |
| `characters/swat.glb` | [poly.pizza/m/Btfn3G5Xv4](https://poly.pizza/m/Btfn3G5Xv4) — "SWAT" by Quaternius | CC0 | Rigged + animated: `Idle`, `Idle_Gun`, `Idle_Gun_Pointing`, `Idle_Gun_Shoot`, `Gun_Shoot`, `Run`, `Run_Shoot`, `Run_Left/Right/Back`, `Walk`, `Roll`, `Kick_Left/Right`, `Punch_Left/Right`, `HitRecieve` (x2), `Death`, plus sword/interact/wave extras. Larger animation set than `soldier.glb` — likely the better player-model pick. |
| `characters/mixamo_soldier.glb` | [Adobe Mixamo](https://www.mixamo.com/) — Gasmask Soldier character + animation library | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Current player **world model** — the third-person body other players see. Consolidated runtime glTF with `idle`, `walk`, `run`, `move_back`, `strafe_left`, `strafe_right`, `crouch_idle`, `crouch_walk`, `jump_start`, `jump_air`, `jump_land`, `fire`, `fire_move`, `reload`, `hit`, and `death`. Raw FBX downloads live in `characters/mixamo_soldier/` and are excluded from Godot import by `.gdignore`. |
| `animations/rifle_aim_idle.res` | Adobe Mixamo — "Rifle Aiming Idle", extracted by `tools/build_clips.gd` | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Loaded over the soldier's `idle` at runtime by `scripts/player/player.gd`. The stock idle carries the rifle across the chest — a patrol carry rather than a soldier ready to fire. |
| `animations/rifle_sprint.res` | Adobe Mixamo — "Sprint Forward", extracted by `tools/build_clips.gd` | same | Loaded as `sprint`. The consolidated model has **no sprint clip at all**, so sprinting previously played `run` and was indistinguishable from jogging. |

Both are loose `Animation` resources rather than a rebuilt `.glb`, so the player model itself is never rewritten. Their track paths (`Skeleton3D:mixamorig_*`) already address the soldier's skeleton, so they drop straight on with no retargeting. The tool also **strips horizontal root motion** — Mixamo bakes 3.5m of forward travel into "Sprint Forward", which makes the model surge and snap back against a physics-driven body.

The two legacy Quaternius skeletons are both named `CharacterArmature` internally but are **not** guaranteed bone-compatible (different node counts — 78 vs 85). The Mixamo player uses a different `mixamorig_` skeleton. Don't swap animations between these models without checking Godot's animation retargeting first.

## Zombies

| Path | Source | License | Notes |
|---|---|---|---|
| `zombies/zombie.glb` | [poly.pizza/m/JoBvxIUpZP](https://poly.pizza/m/JoBvxIUpZP) — "Zombie" by Quaternius | CC0 | Rigged + animated: `Idle`, `Walk`, `Run`, `Attack`, `Jump`, `HitRecieve`, `Death`. Smaller skeleton (20 nodes) than the player models. |
| `zombies/zombie-alt.glb` | [poly.pizza/m/VlXjG0N8Eg](https://poly.pizza/m/VlXjG0N8Eg) — "Zombie" by Quaternius | CC0 | Rigged + animated: `Idle`, `Idle_Attack`, `Walk`, `Run`, `Run_Arms`, `Run_Attack`, `Crawl`, `Jump`, `Jump_Idle`, `Jump_Land`, `Punch`, `HitReact`, `Death`, `Wave`, `Yes`, `No`. Richest zombie animation set — good primary zombie. |
| `zombies/zombie-crawler.glb` | [poly.pizza/m/Htcsn9OrXJ](https://poly.pizza/m/Htcsn9OrXJ) — "Zombie half" by Quaternius | CC-BY | Legless/crawler variant. Rigged + animated: `Idle`, `Walk`, `Run`, `Crawl`, `Jump`, `Jump_Idle`, `Jump_Land`, `HitRecieve`, `Death`. **Requires attribution** — credit "Quaternius" — added to README credits. |
| `zombies/scary_zombie.glb` | Adobe Mixamo — "Scary Zombie Pack" (`Ch10_nonPBR`) | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Semi-realistic current zombie variant with high-resolution embedded textures and a 65-bone Mixamo rig. Consolidated clips: `Idle`, `Walk`, `Run`, `Attack`, `Death`, `NeckBite`, `Crawl`, `Bite`, `BiteAlt`, `DeathAlt`, `CrawlRun`, and `Scream`. |
| `zombies/cop_zombie.glb` | Adobe Mixamo — "Copzombie L Actisdato" | [Mixamo royalty-free use](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html) | Police zombie variant with a 67-bone Mixamo rig. The Scary Zombie Pack's 12 clips are retargeted by matching Mixamo bone names; the cop's two additional eye bones retain their rest pose. |

## Weapons

| Path | Source | License | Notes |
|---|---|---|---|
| `weapons/cc0/*.glb` (9 files) | [3dmodelscc0.itch.io/free-cc0-guns-explosives-pack](https://3dmodelscc0.itch.io/free-cc0-guns-explosives-pack) — "Free CC0 Guns & Explosives Pack" | **CC0 1.0** (see `weapons/cc0/LICENSE.txt`) | **The current weapon pack.** `ak47`, `m4a1`, `shotgun`, `sniper`, `suomi-kp`, `grease-gun`, `luger`, `makarov`, `flare-gun`. Semi-realistic, 1.7k–9.3k tris, embedded PBR materials, and **authored at real-world scale** (the AK is 0.877m) so nothing needs resizing. Taken as the already-converted GLBs from the sibling [zombie-town-online](https://github.com/Chappyjr22/zombie-town-online) repo rather than the source RAR, which ships FBX with reportedly patchy materials. The source pack also has explosives (C4, claymores, mines, grenades, molotov) not yet pulled in — useful for traps later. |

Each weapon is wrapped in a `scenes/weapons/*.tscn` carrying two `Marker3D` sockets, `Grip` and `Foregrip`, which is how `WeaponController` seats it in the hand and works out which way the barrel points. Generated by `tools/build_weapon_scenes.gd`, which seeds them off the model's `Trigger` part and then never overwrites them, so editor tuning is safe. Note the pack is **not** consistent about which way the muzzle faces — `ak47`, `shotgun` and `makarov` point +Z, the rest -Z — which is exactly why the sockets define direction rather than it being inferred.

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

## Animations

Every runtime character/zombie model in `assets/models/characters/` and `assets/models/zombies/` has its animation clips baked into the same `.glb` (see the tables above for clip names). Godot imports these as an `AnimationPlayer`/`AnimationLibrary` on the model's scene automatically. The Mixamo player's individual FBX downloads are retained only as ignored source files; the game loads their consolidated `mixamo_soldier.glb`.

**Not every third-person clip works in first person.** The game renders in true first person — the camera sits at the player's own head, so the body's animation *is* the first-person animation. Clips that read fine from outside can point the weapon well off the crosshair: "Rifle Idle" carries it across the chest, and "Reloading" travels 3.5m. `tools/probe_clip_poses.gd` scores a candidate clip on how squarely it holds the weapon down the view, and `tools/build_aim_idle.gd` shows how to pull a better one out of the raw Mixamo FBXs. Check a clip with the probe before wiring it into the player.

If a future character model needs animations it doesn't ship with, Quaternius's CC0 "Universal Animation Library" packs (Unreal-Godot `.glb` variants, retargetable via Godot's bone-mapping) are the fallback — not currently pulled into the repo since it wasn't needed.

## Textures

| Path | Source | License | Notes |
|---|---|---|---|

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
| `reload-lmg.mp3`, `reload-pistol.mp3`, `reload-rifle.mp3`, `reload-shell.mp3`, `reload-shotgun.mp3` | Pixabay, via [chappyjr22/zombie-town-online](https://github.com/chappyjr22/zombie-town-online) | [Pixabay Content License](https://pixabay.com/service/license-summary/) | Reload foley, reused from the earlier three.js prototype (same account, license already documented there). |
| `weapon-handle.mp3`, `weapon-holster.ogg`, `weapon-metal-load.ogg`, `weapon-pistol-reload.ogg`, `weapon-smg-reload.ogg` | Pixabay, via zombie-town-online | Pixabay Content License | Weapon handling foley (draw/holster/mag insert). |
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

- **Shotgun reload SFX** could use a more distinct pump-action sound (currently reuses generic `reload-shotgun.mp3`) — Snake's Second Gun Sounds pack has pump/shell-load sounds not yet pulled in.
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
