# Asset Pipeline

## Sourcing

Free assets only, license-checked before use. Preferred sources, roughly in order of use:

| Need | Best source |
|---|---|
| Soldier / human character + animations | Mixamo |
| First-person arms (**if ever moving off true first person**) | See the note below — do not carve them out of a body |
| Zombie base model + animations | Mixamo (retarget a humanoid, reskin) or Sketchfab |
| Guns | Kenney.nl weapon packs, Sketchfab (CC) |
| Vehicles | Kenney.nl, Quaternius |
| Environment props | Kenney.nl, OpenGameArt.org, or Meshy AI generation — see below |
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
- Runtime GLBs and extracted model textures that match `.gitattributes` are stored with Git LFS. Keep rules narrowly scoped to genuinely large assets; do not migrate every legacy FBX/PNG without a deliberate history/storage review.

## A shooter needs two character assets, and a rigged humanoid is only one of them

- A **world model** — the third-person body other players see. `mixamo_soldier.glb` is this, and it's good at it.
- A **view model** — arms only, modelled to *end* at a sleeve cuff, animated in camera space.

Buying a great world model does not get you a view model, and a view model cannot reliably be carved out of one. This was tried here at length and abandoned: the arms of a full body have no cuff to end at, so a cut leaves an open tube that the camera's near plane slices into a flat sheet; boundary vertices keep part of their weight on a spine that is no longer in the mesh and smear into spikes when a clip twists; and Mixamo's clips are framed for a camera looking *at* a body, so nothing in them keeps the weapon on screen. The game now renders in true first person instead — the camera sits at the player's own head and the body is the viewmodel — which sidesteps all of it.

Checking that a rigged humanoid has bones named `Hand`, `ForeArm` and so on proves nothing; nearly all of them do, this one included down to individual finger joints. When evaluating an arms asset, ask instead:

1. Is the geometry **arms only**, terminating at a cuff?
2. Does it ship **first-person** idle / walk / sprint / fire / reload?

If either answer is no, it's a world model.

## AI-generated environment assets (Meshy)

Evaluated as a third sourcing option alongside the free (Kenney) and paid packs already tracked in `ASSET_MANIFEST.md`. Three test generations (an abandoned house, a fenced backyard, a rubble/debris pile) via [meshy.ai](https://www.meshy.ai) established a working process and real limitations — verified by measuring and rendering each result, never by trusting the in-app preview alone:

- **Never trust raw generation for scale.** Text-prompt dimensions get ignored — one generation came out 1.8m instead of the requested 6m, wrong non-uniformly on every axis, not just smaller. Meshy's export dialog (Resize on, explicit Height in cm, Origin: Bottom) is reliable instead — nailed the target height exactly across three separate generations. Always use the export dialog for scale; never rely on prompt text for it.
- **Thin/lattice geometry fails; solid/blocky forms don't.** Vines and a chain-link fence both broke — the fence rendered as bare posts and one sagging wire with no fabric at all, despite a clean concept image. This isn't fixable by adding "no thin geometry" to a prompt that still needs a fence — it means don't ask this tool for that category of object as real geometry at all. Solid forms (brick, concrete, dumpsters, rubble) come out well consistently.
- **Raw polycount is unpredictable and ignores prompt requests.** Asking for "optimized/low-to-mid polygon count" in the prompt did nothing — a small debris pile still came out at 1.38M triangles. A follow-up remesh pass with an explicit numeric target (not a vague description) is required, and that part *is* honored precisely (asked for 5,000-6,000 tris, got 5,707).
- **The remesh step drops normal maps even when explicitly told to preserve them** (confirmed twice). Visual impact is smaller than expected — a lot of perceived depth is already baked into the albedo texture's shading — but don't rely on it. If true normal-mapped detail matters later, bake one manually in Blender from the pre-remesh high-poly source, don't re-prompt Meshy for it.
- **Lock mood/lighting to flat/diffuse options** ("overcast," not "golden hour"). Directional lighting gets baked into the diffuse texture and will clash with Godot's own dynamic lighting once the asset is actually in a scene.
- **Match palette across separate generations deliberately.** Nothing enforces consistency between prompts on its own — picking answers that echo an already-generated asset's color language is what kept multiple pieces reading as one coherent world instead of several.

**Working process**: Image to 3D (concept image first, not straight Text to 3D) → lock mood/lighting (flat/diffuse) and palette (match existing assets) → generate → prefer the triangle mesh over quad if offered (Godot triangulates on import regardless; quad topology only matters for hand-editing in a DCC tool) → at export, Resize on with explicit real-world Height in cm, Origin: Bottom → if polycount looks large, remesh with an explicit target triangle count and re-verify before trusting it.

**Status**: proven at prop/small-structure scale. Full map/environment-scale generation not yet tested — free (Kenney) and paid sourcing options remain the fallback if that doesn't hold up.

## Realism/quality bar

Aiming for "decent, semi-realistic" — not stylized low-poly, not AAA. Prioritize models with:
- PBR textures (albedo/normal/roughness) rather than flat-shaded low-poly.
- Reasonable poly counts for real-time (characters ~10-30k tris, weapons ~5-15k tris) — Godot's Forward+ renderer handles this comfortably on modern hardware.
