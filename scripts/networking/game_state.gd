extends Node

## Autoload (Project Settings > Autoload) - shared state that survives a
## scene change. `main_menu.tscn` and `scenes/ui/hud.gd`'s game-over screen
## both read/write this to pass a run's stats across the menu<->level
## transition, since local script vars don't survive `change_scene_to_file()`.
##
## This is genuinely single-player-scoped for now: `scripts/networking/CLAUDE.md`
## already planned a `GameState` autoload as "shared round/game state,
## host-authoritative" for once multiplayer exists, and this is that same
## autoload, started early - but nothing here is host-authoritative or
## networked yet. Revisit alongside `NetworkManager` when that gets built,
## rather than assuming this is already multiplayer-ready.

var last_round_reached := 0
var last_points := 0
var last_kills := 0
## True once a run has actually ended - lets main_menu.gd tell "never played"
## apart from "died on round 1 with a wipe of everything".
var has_last_run := false


func record_run_end(round_reached: int, points: int, kills: int) -> void:
	last_round_reached = round_reached
	last_points = points
	last_kills = kills
	has_last_run = true
