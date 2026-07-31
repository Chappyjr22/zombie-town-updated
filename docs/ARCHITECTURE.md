# Architecture

## Perspective: third person

The game is a **third-person** shooter. The camera orbits the player on a
`SpringArm3D` (so walls push it in rather than clipping through), the character
always faces where the camera looks, and aiming pulls the camera in over the
shoulder.

That last part matters for animation: because the body faces the aim direction
rather than the movement direction, strafing and walking backwards are real
states, which is exactly what the directional walk/run blend space in
`scripts/player/player.gd` is built for.

### Why not first person

It was first person for a while, and it was abandoned deliberately. The short
version: **a shooter needs two character assets**, a *world model* (the
third-person body other players see) and a *view model* (arms only, ending at a
cuff, animated in camera space). `mixamo_soldier.glb` is a world model, and a
view model can't reliably be derived from one - arms cut out of a full body have
no cuff to terminate at, and clips authored for a camera looking *at* a body
don't keep a weapon inside a camera looking *out* of its eyes.

`docs/ASSET_PIPELINE.md` has the full account and the two questions to ask of any
arms asset. Don't re-derive this; it cost a lot to learn.

## Goals

- Keep everything Claude/agent-editable as **text** (Godot `.tscn`/`.tres`/`.gd` are text by default — keep it that way, avoid binary-packed scenes).
- Keep binary assets out of the code-search path. Never `grep`/enumerate `assets/` — use `ASSET_MANIFEST.md`.
- Each `scripts/<system>/` folder owns one gameplay system and has its own short `CLAUDE.md` describing its responsibilities and public interface, so an agent only needs to load the folder(s) relevant to the task at hand.

## Folder map

```
assets/
  models/{characters,zombies,weapons,vehicles,props}
  animations/
  textures/
  audio/
scenes/
  player/      Player character scene(s), camera rig, first-person view model
  zombies/     Zombie scene(s), spawner scenes
  weapons/     Per-weapon scenes (model + muzzle flash + hitscan/projectile config)
  levels/      Maps / rounds, main menu
  ui/          HUD, menus, lobby/host-join screens
scripts/
  player/      Movement, camera, input, health
  ai/          Zombie behavior, pathfinding, spawning/wave logic
  weapons/     Weapon base class, per-weapon behavior, ballistics
  networking/  Listen-server host/join, state sync (see docs/MULTIPLAYER.md)
  ui/          Menu logic, HUD binding
resources/
  weapons/     WeaponData .tres instances - one per weapon, data-driven (model/sound/stats), no code per weapon
docs/          This file, plus MULTIPLAYER.md, ASSET_PIPELINE.md, DISTRIBUTION.md, GAMEPLAY.md
```

## Conventions

- GDScript, `snake_case` for files and functions, `PascalCase` for class names.
- One scene = one `.tscn` file with a matching `.gd` script attached, named identically (`zombie.tscn` / `zombie.gd`).
- Autoloads (singletons) are limited to: `GameState`, `NetworkManager` — declared in Project Settings > Autoload, documented in `scripts/networking/CLAUDE.md`.
- Before adding a new system folder, check whether an existing one already owns that responsibility.
