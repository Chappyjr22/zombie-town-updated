# scripts/networking

Owns: listen-server host/join flow (`ENetMultiplayerPeer`), state sync between host and clients. Full design in `docs/MULTIPLAYER.md`.

Planned autoloads:
- `NetworkManager` — create_server/create_client, peer connect/disconnect handling, RPC dispatch. Not yet implemented.
- `GameState` (`game_state.gd`) — **started, but only single-player-scoped so far.** Currently just `last_round_reached`/`last_points`/`last_kills`, written by `scripts/ui/hud.gd` on the player's `died` signal and read by `scripts/ui/main_menu.gd` to show a "last run" line - the only cross-scene state the game has right now. Not host-authoritative, not networked, not synced to anyone. When `NetworkManager` gets built, this is the autoload that becomes the shared/authoritative round state - revisit its contents then rather than assuming today's shape is final.
