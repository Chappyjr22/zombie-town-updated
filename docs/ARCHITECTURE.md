# Architecture

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
