# Gameplay Scope

## Current target: core loop first

Build and get fun before adding meta-progression:

This list predates most of what's actually built now and is kept only for the items still genuinely true - see each system's own `CLAUDE.md` for current, maintained status: `scripts/player/`, `scripts/weapons/`, `scripts/ai/`, `scripts/economy/`, `scripts/ui/`. The round loop, points economy, perks, Pack-a-Punch, mystery box, and pause menu are all built.

## Tier 6 — deferred until closer to release

Explicitly held back rather than built now (user decision) - core gameplay and its editor-facing polish come first:

- **Boss rounds.** Not built. The old three.js prototype (`chappyjr22/zombie-town-online`) ran one every 10th round (`6000 + max(0, r-10)*550` health, 1.48× scale, one boss plus ten escorts) and has a CC0 boss model with provenance already checked (`public/models/boss-zombie/boss-zombie.glb` in that repo, `LICENSE.txt` alongside it) - not pulled into this project yet. The user has a boss model in mind and wants core gameplay solid before adding this.
- **Zombie downed/crawl state.** Not built. `Crawl`/`CrawlRun` clips are already imported on both Mixamo zombie variants (`ASSET_MANIFEST.md`) but nothing selects them - the AI state machine is `IDLE`/`CHASE`/`ATTACK`/`DEAD` only, see `scripts/ai/CLAUDE.md`. (Not to be confused with the *player's* downed/self-revive state, which exists - `scripts/player/player.gd`, gated on the Quick Revive perk.)
- **Networking.** Not built beyond a single-player-scoped `GameState` autoload holding last-run stats. Full design in `docs/MULTIPLAYER.md`; `scripts/networking/CLAUDE.md` tracks current status. Recommended to hold off until the core single-player loop is stable - retrofitting host authority onto gameplay systems is more expensive after the fact than designing it in from the start.

## Zombie ragdoll on death

**Superseded — see `scripts/ai/CLAUDE.md`'s "round 7" entry for the full account.** The plan below (Godot's built-in `PhysicalBone3D` simulation) was implemented and tested through seven rounds of fixes - bones launching on scene start, T-posing instead of ragdolling, corpses stretching into spikes - and ultimately abandoned in favor of a canned `Death` animation clip, which is what `zombie.gd` uses today. The infrastructure (`PhysicsLayers.RAGDOLL`, `_isolate_ragdoll_bones()`, `_ragdoll_bone_names()`) is still in the file, unused. Revisiting it is Tier 4 work, not Tier 6, and per that file's own notes needs hands-on per-bone joint tuning in the editor rather than more blind code changes - the original plan text is kept below only as background on what was tried and why it's a dead end without that.

The old three.js prototype implemented ragdolls from scratch: a hand-rolled 15-point Verlet-integration skeleton with distance constraints, because three.js has no built-in skeletal physics. That complexity doesn't carry over — Godot has ragdolls built in, which is what the abandoned attempt above used instead.
