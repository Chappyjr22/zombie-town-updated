# Multiplayer: Listen-Server

## Model

One player is the host — their game instance also runs the authoritative simulation (zombie AI, spawning, damage resolution, round state). Everyone else, including the host's own client, connects as a peer via Godot's high-level multiplayer API (`ENetMultiplayerPeer`).

- Host: `create_server(port)`, then `create_host()` / `join as peer 1` implicitly.
- Clients: `create_client(host_ip, port)`.
- No relay, no dedicated server, no matchmaking service. The host shares their IP (or a Hamachi/Tailscale/ZeroTier VPN IP if NAT punch-through is flaky) with friends directly.

## Why listen-server is fine here

Friends-only, small group (realistically 2-4 players), no need to protect against cheating from the host — the host is a friend, not the public. This avoids building/hosting/paying for a dedicated server entirely.

## Sync responsibilities

- **Host-authoritative:** zombie spawning/movement/damage/death, round progression, pickups/loot spawns.
- **Client-owned, host-relayed:** player position/rotation/animation state, weapon fire events, health.

## Known limitation

If the host disconnects, the session ends (no host migration in v1). Acceptable for a casual friends game; revisit only if it becomes annoying in practice.

## Implementation notes

Networking code lives in `scripts/networking/`. See that folder's `CLAUDE.md` for the current API surface once implemented.
