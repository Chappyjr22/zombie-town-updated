# scripts/networking

Owns: listen-server host/join flow (`ENetMultiplayerPeer`), state sync between host and clients. Full design in `docs/MULTIPLAYER.md`.

Planned autoloads:
- `NetworkManager` — create_server/create_client, peer connect/disconnect handling, RPC dispatch.
- `GameState` — shared round/game state, host-authoritative.

Not yet implemented.
