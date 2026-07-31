# scripts/ui

Owns: main menu, host/join lobby screen, in-game HUD (health, ammo, weapon), pause menu.

Depends on: `scripts/networking` (host/join actions), `scripts/player` (HUD data).

## Status

- `hud.gd` (`class_name HUD`, `scenes/ui/hud.tscn`) — the in-game HUD, instanced into `player.tscn` as `HUD`. Health bar and value bottom-left, weapon name and `mag / reserve` ammo bottom-right, and a weapon-name toast above centre that fades after a switch.

  **It is a pure view.** It holds no game state and never reads from the player or the weapon; `bind_player()` connects it to `health_changed`, `ammo_changed`, `weapon_changed`, `aim_changed` and `fired`, and everything after that arrives by signal. That keeps gameplay ignorant of what's on screen, and means a second local player or a spectator can bind its own instance to a different source.

  `bind_player()` also catches up on the current weapon and ammo by hand. The starting weapon is equipped in `WeaponController._ready()`, which runs *before* the player binds the HUD — children are readied before their parent — so that first `weapon_changed` would otherwise be missed and the readouts would sit on the scene's placeholder text until the first switch.

  Ammo colours amber below 30% of a magazine and red when empty; the health bar lerps green to red. Both are so state reads at a glance without parsing digits.

- `crosshair.gd` (`class_name Crosshair`, `HUD/Crosshair`) draws a resolution-independent centred crosshair. It tightens in ADS, expands with normalized movement speed (fed per-frame by the player, since that's not signal data), and pulses on `fired`.

## Known gaps

- Round counter, hit markers, damage-direction indicators, interaction prompts, pause menu, and lobby UI are not implemented.
- **No reload indicator.** `reload_started(duration)` is emitted and unused by the HUD — a progress arc round the crosshair is the obvious use for it.
- The weapon toast shows the slot number, but there's no persistent slot/loadout strip showing what else is carried.
