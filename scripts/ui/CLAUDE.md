# scripts/ui

Owns: main menu, host/join lobby screen, in-game HUD (health, ammo, weapon), pause menu.

Depends on: `scripts/networking` (host/join actions), `scripts/player` (HUD data).

## Status

- `hud.gd` (`class_name HUD`, `scenes/ui/hud.tscn`) — the in-game HUD, instanced into `player.tscn` as `HUD`. Health bar and value bottom-left, weapon name and `mag / reserve` ammo bottom-right, and a weapon-name toast above centre that fades after a switch.

  **It is a pure view.** It holds no game state and never reads from the player or the weapon; `bind_player()` connects it to `health_changed`, `ammo_changed`, `weapon_changed`, `aim_changed` and `fired`, and everything after that arrives by signal. That keeps gameplay ignorant of what's on screen, and means a second local player or a spectator can bind its own instance to a different source.

  `bind_player()` also catches up on the current weapon and ammo by hand. The starting weapon is equipped in `WeaponController._ready()`, which runs *before* the player binds the HUD — children are readied before their parent — so that first `weapon_changed` would otherwise be missed and the readouts would sit on the scene's placeholder text until the first switch.

  Ammo colours amber below 30% of a magazine and red when empty; the health bar lerps green to red. Both are so state reads at a glance without parsing digits.

  **Round readout and points**, added with the game loop. `RoundPanel` (top centre) shows `ROUND 07` plus a status line that reads `12 remaining` while there's work left and switches to `clear · next in 6s` once the round is done — the countdown is only surfaced when it's the thing the player is actually waiting on. `PointsPanel` (bottom left, above health) shows the balance, digit-grouped because points reach five figures by the mid rounds and unseparated digits stop being readable at a glance.

  These come from the level's `RoundDirector` rather than from the player, found by group in `_bind_round_director()`. That lookup is **deferred a frame on purpose**: the director is a sibling up in the level while the HUD is nested inside the player scene, so which is ready first depends on the order they happen to sit in the level tree — a detail nobody should have to preserve when rearranging a scene. A level with no director is legitimate (weapon test scenes have none) and simply hides the round readout.

  **Colours are the browser build's palette**, carried over so the two versions look like the same game: amber `#e8a33d` for points, bone `#e6e0d2` for secondary text, blood `#a3231e` for the round number.

- `crosshair.gd` (`class_name Crosshair`, `HUD/Crosshair`) draws a resolution-independent centred crosshair. It tightens in ADS, expands with normalized movement speed (fed per-frame by the player, since that's not signal data), and pulses on `fired`.

- `hitmarker.gd` (`class_name Hitmarker`, `HUD/Hitmarker`) flashes a four-tick X on `WeaponController.hit_confirmed`, white for a hit and blood-red for a kill. Hitscan gives no other feedback — the shot is instant and the target is usually behind other targets — so without it the player can't tell a hit from a miss. Ticks sit at 45° so they frame the crosshair rather than overlap it, and it fades rather than blinking off so automatic fire reads as a sustained marker instead of a strobe.

## Known gaps

- Damage-direction indicators, interaction prompts, pause menu, and lobby UI are not implemented.
- **No perk icons or points-multiplier readout.** Both existed in the browser build's HUD; neither has a system behind it here yet.
- **No reload indicator.** `reload_started(duration)` is emitted and unused by the HUD — a progress arc round the crosshair is the obvious use for it.
- The weapon toast shows the slot number, but there's no persistent slot/loadout strip showing what else is carried.
