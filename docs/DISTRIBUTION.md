# Distribution: itch.io

## Why itch.io

- Free, supports private/unlisted pages (shareable link, optional password) — only your friends see it.
- The itch.io desktop app installs the game and auto-updates it whenever a new build is pushed, via `butler`.
- Doesn't touch runtime performance at all — it only hosts the download page and pushes new build files; the game itself runs as a plain native Godot export, same as if you'd copied the .exe over manually.

## One-time setup

1. Create an itch.io account, create a new project (set visibility to "Restricted" / unlisted, or password-protected).
2. Install `butler`: https://itch.io/docs/butler/installing.html
3. `butler login`

## Export from Godot

1. Editor > Export... > add presets for Windows (and Linux/macOS if needed).
2. Export to `build/windows/ZombieTown.exe` (this folder is gitignored — builds aren't committed, only pushed to itch).

## Push a build

```bash
butler push build/windows <your-itch-username>/zombie-town:windows
```

Repeat per platform channel (`:windows`, `:linux`, `:macos`). Players with the itch app get the update automatically next time they open it.

## Optional: automate via GitHub Actions

Once the project is stable enough to be worth automating, a workflow can run the Godot headless export + `butler push` on tag/push. Not needed for early development — do this later if manual exports get tedious.
