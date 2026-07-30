# Zombie Town

A private, friends-only first-person zombie survival shooter built in **Godot 4** (native app, not a browser game).

Multiplayer is listen-server: one player hosts, others connect directly to their IP/port. No dedicated server or matchmaking service required.

## Requirements

- [Godot 4.3+](https://godotengine.org/download) (standard build, not .NET, unless we decide to use C#)

## Running the project

1. Open Godot 4.
2. Click **Import**, select this repo's `project.godot`.
3. Press F5 to run.

## Distribution

Builds are exported from Godot and published to a private/unlisted [itch.io](https://itch.io) page. The itch app handles installation and auto-updates for players (your friends) — see `docs/DISTRIBUTION.md`.

## Project structure

See `docs/ARCHITECTURE.md` for the full breakdown. Short version:

```
assets/     Models, animations, textures, audio (see ASSET_MANIFEST.md)
scenes/     .tscn scene files, organized by system
scripts/    GDScript/C#, organized by system (each folder has a CLAUDE.md)
docs/       Architecture, multiplayer design, asset pipeline, distribution
```

## Docs

- `docs/ARCHITECTURE.md` — project layout and conventions
- `docs/MULTIPLAYER.md` — listen-server networking design
- `docs/ASSET_PIPELINE.md` — where assets come from, licensing, import settings
- `docs/DISTRIBUTION.md` — build/export/itch.io release process
- `ASSET_MANIFEST.md` — index of every asset in the project
