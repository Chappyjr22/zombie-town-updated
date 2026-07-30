# Zombie Town — agent notes

Godot 4 first-person zombie survival shooter. Private, friends-only, listen-server multiplayer. Native app distributed via itch.io — not a browser/web game.

## Before touching anything

- Never enumerate or grep `assets/` — binaries. Use `ASSET_MANIFEST.md` to find what exists.
- Each `scripts/<system>/` folder has its own `CLAUDE.md`. Read only the ones relevant to the current task, not the whole tree.
- Full context docs live in `docs/`: `ARCHITECTURE.md`, `MULTIPLAYER.md`, `ASSET_PIPELINE.md`, `DISTRIBUTION.md`.

## Adding assets

Follow `docs/ASSET_PIPELINE.md`'s checklist exactly — every asset must get a row in `ASSET_MANIFEST.md` and, if it requires attribution, a credit in `README.md`.

## Conventions

GDScript, snake_case files/functions, PascalCase classes, one scene = one `.tscn` + matching `.gd`. See `docs/ARCHITECTURE.md` for the full folder map and autoload list.
