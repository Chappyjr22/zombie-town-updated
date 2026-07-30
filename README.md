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

## Credits

Most assets are CC0 (no attribution required) — full sourcing detail in `ASSET_MANIFEST.md`. Assets that require attribution or carry a non-CC0 license:

- `assets/models/zombies/zombie-crawler.glb` — "Zombie half" by [Quaternius](https://poly.pizza/m/Htcsn9OrXJ), licensed CC-BY.
- `assets/audio/zombies/zombie-moan.mp3`, `zombie-attack.mp3`, `zombie-hurt.mp3`, `zombie-death.mp3` — recordings by Mike Koenig via [SoundBible](https://soundbible.com), licensed CC BY 3.0.
- `assets/audio/player/player-hurt-1.mp3`, `player-hurt-2.mp3`, `player-hurt-3.mp3` — [Mixkit](https://mixkit.co) fight sound effects, used under the [Mixkit Sound Effects Free License](https://mixkit.co/license/).
- `assets/audio/weapons/reload-*.mp3`, `weapon-*.mp3`/`.ogg` — [Pixabay](https://pixabay.com) recordings, used under the [Pixabay Content License](https://pixabay.com/service/license-summary/).
- `assets/audio/weapons/fire-*.mp3` — recorded by F8 Studios ("Snake's Authentic Gun Sounds" packs, [f8studios.itch.io](https://f8studios.itch.io/snakes-authentic-gun-sounds)); free for commercial use, no credit required, but linked here anyway.
