# scripts/ui

Owns: main menu, host/join lobby screen, in-game HUD (health, ammo, round counter), pause menu.

Depends on: `scripts/networking` (host/join actions), `scripts/player` (HUD data).

## Status

- `crosshair.gd` (`player.tscn` → `HUD/Crosshair`) draws a resolution-independent centered crosshair. It tightens when `WeaponController.aim_changed` enters ADS, expands with normalized player movement speed, and pulses on `fired`.

## Known gaps

- Health, ammo, round counter, hit markers, interaction prompts, pause menu, and lobby UI are not implemented yet.
