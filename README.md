# G1LockPickHelper

A lockpicking helper for **Gothic 1 Remake**: a UE4SS Lua mod that shows the key sequence that opens the lock
in the lockpicking minigame and follows you through it. Press **F3** and the mod picks the lock for you, using only
moves that cannot strain the pick.

- **Hint.** The current key and the next ones on a tape (or the whole sequence in lines), next to the lock. It
  follows your presses, keyboard or gamepad, and replans when the lock does not do what was expected.
- **Autosolve.** F3 in the minigame solves the lock with the moves the hint shows - only moves that cannot strain
  the pick. F3 right after using a chest (while the hero sits down) solves the minigame that opens next.
  Any key you press yourself takes over. "Auto-pick" in the settings solves every lock as it opens.
- **Exact locks.** The lock layouts come from the game files; the connections your lockpicking skill removes are
  removed from the hint too.
- **English and Russian**, following the game's language by default.

## Requirements

- Gothic 1 Remake (tested on build `Build83_CL174209`).
- [UE4SS - AngelScript Fix](https://www.nexusmods.com/gothic1remake/mods/524) (UE4SS 3.0.1 built for the game's
  AngelScript engine).
- Optional: [Shared Mod Menu](https://www.nexusmods.com/gothic1remake/mods/194) by Tautellini, to change the
  settings in game (F2).

## Install

1. Install UE4SS - AngelScript Fix as its page describes.
2. Extract the release archive (`G1LockPickHelper-<version>.zip`) into the game folder - the one that contains
   the `G1R` folder - so that `G1R\Binaries\Win64\ue4ss\Mods\G1LockPickHelper\` exists.
3. Start the game. The mod writes `settings.ini` into its folder on the first start.

Uninstall: delete `G1R\Binaries\Win64\ue4ss\Mods\G1LockPickHelper\`.

## Keys

| Key | What it does |
|---|---|
| F4 | Show / hide the hint |
| F3 | In the minigame: solve the lock / stop. Outside it: solve the minigame that opens within 5 s (with "Auto-pick" on: skip it) |
| F2 | Shared Mod Menu, if installed: the mod's tab "LockPick Helper" |

The keys are set in `settings.ini` (`[keys]`, UE4SS key names) and change after a game restart.

## Settings

`settings.ini` in the mod folder, with comments. With Shared Mod Menu most of the settings are also in
its tab "LockPick Helper" (not `debug`; the keys are shown read-only). A change there rewrites the whole file, so
your own comments in it are lost.

- `[general]` - `language` (`auto`: the game's language; `en`; `ru`), `debug` (detailed log, see below).
- `[hint]` - tape or lines, simple or gothic style, size, position, counter, shake on a miss.
- `[tape]`, `[lines]` - how many keys are shown and how.
- `[solve]` - `auto`: solve each lock by itself ("Auto-pick").
- `[keys]` - the keys above and the key labels of the minigame.

After editing the file press Ctrl+R (UE4SS mod reload) or restart the game.

## Report a bug

1. In `settings.ini` set `debug = true` under `[general]`, then press Ctrl+R or restart the game.
2. Repeat what went wrong.
3. Open an issue on GitHub (or a bug report on the Nexus page) and attach
   `G1R\Binaries\Win64\ue4ss\UE4SS.log`. The line that contains `[G1LockPickHelper] G1LockPickHelper <version>:`
   tells the mod's version, the game build, the language and whether the input hooks are on.

## Known limits

- The hint needs the lock in the mod's database (416 locks of build `Build83_CL174209`). A game update may add
  or change locks; the log then warns that the database is for another build.
- The autosolver needs the input hooks (the log says "input hooks yes"); without them F3 says "Autosolve
  unavailable" and the hint still works.
- LockpickSettings by Tautellini also changes the lockpicking minigame; using both at once is not tested.

## Build from source

- Tests: Lua 5.4 - `for f in tests/*_test.lua; do lua "$f" || break; done` (Git Bash, from the repository root);
  Python 3 - `python -m unittest tests.test_extract tests.test_lockgraphs_lua` (the extractor's ground-truth tests
  run when `G1R_GAME_DIR` points to the game folder).
- Lock database: `python tools/extract_lockgraphs.py --game-dir "<game folder>"` rewrites
  `mod/G1LockPickHelper/Scripts/lockgraphs.lua`.
- Deploy into the game: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy.ps1 -GameDir "<game folder>"`
  (keeps your `settings.ini`).
- Release archive: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1` →
  `out\G1LockPickHelper-<version>.zip`.

How the mod works inside: [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Credits

- Tautellini - the public notes on the lockpicking minigame (the LockpickSettings documentation and the G1R Lua
  modding notes), and Shared Mod Menu. No code of theirs is used here.
- The UE4SS team, and the author of UE4SS - AngelScript Fix for Gothic 1 Remake.

## AI disclosure

The code, tests and documentation of this mod were written by Claude (Anthropic's AI model) under the direction
of tslaceo, who designed the features, played and tested every version in game and decided what ships.

## License

MIT - see [LICENSE](LICENSE). The lock layouts in `mod/G1LockPickHelper/Scripts/lockgraphs.lua` (and the test
fixture) are extracted from Gothic 1 Remake; they are not covered by the license and belong to the game's
rights holders.
