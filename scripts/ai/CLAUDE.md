# scripts/ai

Owns: zombie behavior (pathfinding/chase/attack), spawner logic, wave/round progression. Runs authoritatively on the host only (see `docs/MULTIPLAYER.md`); results are relayed to clients, not simulated locally on clients.

Depends on: `scripts/networking` (to relay authoritative state).

Not yet implemented.
