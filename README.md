# LockPick Helper

A lockpicking helper for **Gothic 1 Remake**: a mod for the game's official Modkit that shows the key sequence that
opens the lock in the lockpicking minigame and follows you through it. Press **F3** and the mod picks the lock for
you, using only moves that cannot strain the pick.

- **Hint.** The current key and the next ones on a tape (or the whole sequence in lines), next to the lock. It
  follows your presses, keyboard or gamepad, and replans when the lock does not do what was expected. It appears
  about 2 seconds after the minigame opens (the game ignores presses at first).
- **Auto-pick.** F3 in the minigame picks the lock with the moves the hint shows - only moves that cannot strain
  the pick. F3 right after using a chest (while the hero sits down) auto-picks the minigame that opens next.
  While it picks, the hint counts down the seconds it still needs. Any key you press yourself takes over.
  "Always auto-pick" in the settings picks every lock as soon as its minigame starts.
- **Gamepad.** With a gamepad the hint shows the game's own button icons - PlayStation, Xbox or Switch, as the
  game's "Button icons" option says (with "Do not use" it shows letters, unless the row "Icons" is 2).
  Press reset twice (Triangle / Y) and the mod picks the lock.
- **Exact locks.** The lock layouts come from the game's own sources (the official Modkit); the connections your
  lockpicking skill removes are removed from the hint too.
- **English and Russian**, following the game's language by default.
- **Settings in the game's options**, on the Game tab.

## Requirements

- Gothic 1 Remake with Modkit support (tested on build `Build102_CL175960`).
- Nothing else: no UE4SS, no other mods.

## Install

**Steam Workshop:** subscribe to [LockPick Helper: hint and auto-pick](https://steamcommunity.com/sharedfiles/filedetails/?id=3830422263).
The game finds Workshop mods by itself; there is nothing to copy.

**By hand** (the file from Nexus or from the GitHub release):

1. Extract the archive (`LockPickHelper-<version>.zip`) into the game folder (the one that contains the `G1R`
   folder), so that `G1R\Mods\LockPickHelper\GothicMod.json` exists afterwards. `README.txt` and `LICENSE.txt` are in
   that folder too.
2. Start the game. It should list the mod as enabled: the main menu shows "1 mods enabled" (with this mod alone). If
   it does not, start the game with the launch option `-ModManagementUI` and enable LockPick Helper in the game's mod
   list; the same list turns the mod off.

**Vortex** works too, with its Gothic 1 Remake extension: use Mod Manager Download on the Nexus page, or Install From
File with the archive. It puts the files into `G1R\Mods\LockPickHelper` as links. Removing the mod in Vortex leaves that
folder with Vortex's empty marker files; delete it by hand. Tested with Vortex 2.9.

Use one way, Workshop or by hand (or Vortex), not both. To switch to the Workshop copy, delete the folder
`G1R\Mods\LockPickHelper` first.

**Upgrading from 1.x.** The current game does not start with UE4SS installed, so remove UE4SS first: delete
`dwmapi.dll` and the `ue4ss` folder in `G1R\Binaries\Win64` (the 1.x mod, `ue4ss\Mods\G1LockPickHelper`, is inside it).
If the game is on the Steam beta branch `previousrelease`, switch the beta back to None (the game's Properties >
Betas). The `settings.ini` of 1.x is not read: set the settings again in Options > Game.

**The game's warning about saves.** The game remembers the list of mods in a save. Loading a save made with another
list - before you installed the mod, or after you removed it - shows "This save was made with a different modlist":
choose **Continue anyway**.

Uninstall: unsubscribe in the Workshop, or delete the folder `G1R\Mods\LockPickHelper`.

## Keys

| Key | What it does |
|---|---|
| F4 | Show / hide the hint (in the minigame and outside it) |
| F3 | In the minigame: auto-pick the lock / stop. Outside it: auto-pick the minigame that opens within 5 s (with "Always auto-pick" on: skip the next one) |
| Reset twice (keyboard R R, gamepad Triangle / Y) | In the minigame: auto-pick the lock, like F3 (the row "Double reset" turns it off) |

The D-pad of a gamepad moves the pick as it does without the mod, and the hint follows it. F3 and F4 are fixed:
there is no rebinding in 2.0.

## Settings

Options > the **Game** tab, the block **[Mod] LockPick Helper**: 20 rows, in this order. The game keeps them in
`GameUserSettings.ini`. The labels are in the language of the row "Language" (0: the game's interface language); a
change of that row shows in the menu after a save load or a restart (the table gives the English labels). The **Reset**
button of the tab is the game's own.

Settings can be changed only between lockpicking minigames: the game's pause and options cannot be opened during
one. A change applies from the next lock.

| Row | What it does | Range | Default |
|---|---|---|---|
| Language (0 as in the game, 1 English, 2 Русский) | The language of the hint's texts and of these labels. 0 follows the game's interface language: Russian, otherwise English | 0-2 | 0 |
| Tape layout | On: the tape (the current key and the next ones). Off: lines (the whole sequence) | on / off | on |
| Gold letters | On: a gold letter in a gold frame (the game's text font). Off: keys like the game's own key prompts in the minigame. Called Gothic style in 1.x | on / off | off |
| Icons (0 auto, 1 letters, 2 icons) | 0: gamepad icons while you play with a gamepad, letters on the keyboard (and always letters when the game's "Button icons" is "Do not use"). 1: always letters. 2: always gamepad icons | 0-2 | 0 |
| Icon set (0 game, 1 PS, 2 Xbox, 3 Switch) | Which icons. 0: as the game's "Button icons" option says (with "Auto": by the pad's name). 1 PlayStation, 2 Xbox, 3 Switch | 0-3 | 0 |
| Size, % | The size of the hint | 50-200 | 100 |
| Position X | Shifts the hint sideways, in the game's interface units, from the right edge of the screen: smaller moves it left | -3000 to 3000 | -760 |
| Position Y | Shifts the hint up or down: bigger moves it down | -2000 to 2000 | 0 |
| Counter | The counter of pressed keys out of all ("3/12") | on / off | on |
| Shake on a miss | The hint shakes when you press a wrong key | on / off | on |
| Upcoming keys | Tape: how many keys after the current one | 1-10 | 5 |
| Pressed keys | Tape: how many pressed keys stay on the left | 0-6 | 3 |
| Smooth scroll | Tape: slides after a press | on / off | on |
| Dark background | A dark plate behind the tape or the lines | on / off | off |
| Keys per line | Lines: keys in a line | 4-40 | 16 |
| Lines on screen | Lines: how many lines are shown at once | 1-12 | 6 |
| Fold repeats from | Lines: N or more equal keys in a row fold into "A×N". 0 or 1: never | 0-20 | 3 |
| Always auto-pick | Every lock is picked as soon as its minigame is ready (F3 outside a minigame skips the next one) | on / off | off |
| Double reset | Two resets within half a second start auto-pick | on / off | on |
| Countdown | While auto-pick works, the hint says "Auto-picking… 12 s", the seconds still needed. Off: "Auto-picking…" | on / off | on |

## Status

The mod is not in active development: the author has finished the game and does not plan another playthrough for
now. Every feature was tested in game; compatibility with other mods was not tested.

## Report a bug

1. Attach `%LOCALAPPDATA%\G1R\Saved\LockPickHelper.log` (a new file on every start of the game). Its first line
   tells the mod's version, the game build, the language, the icon settings and whether the detailed log is on;
   after that come the lock of every minigame, auto-pick's starts and stops, and warnings.
2. For a detailed log (every plate reading, press and redraw), close the game and, in the section
   `[/Script/Angelscript.LPH_Settings]` of `%LOCALAPPDATA%\G1R\Saved\Config\Windows\GameUserSettings.ini`, change
   `Debug=False` to `Debug=True` (the game writes that line itself, the last one of the section; if the line or the
   section is missing, add it at the end). Simpler: add `-LPHDebug` to the game's launch options (Steam: the game's
   Properties > Launch Options). The first line of the log then says `debug on`. Repeat what went wrong and attach the
   new log.
3. Open an issue on GitHub (or a bug report on the Nexus page).

## Known limits

- The hint needs the lock in the mod's database (416 locks, made from the Modkit sources of build
  `Build102_CL175960`). A lock the database does not know shows `Lock not in the database: <name>`; a game update
  may add or change locks, and the log then warns that the database is for another build.
- Settings change only between minigames (see Settings).
- A held D-pad repeats the move quickly.
- A DualSense through Steam Input looks like an Xbox pad to the game: with the row "Icons" at 0 and the game's
  "Button icons" on Auto the hint shows Xbox icons. Set the row "Icon set" to 1 (PS), choose "PlayStation 5" in the
  game's "Button icons", or turn Steam Input off for the game (Steam > the game's Properties > Controller).

## Older game version (UE4SS)

2.0 runs on the current game (`Build102`), which refuses to start with UE4SS installed. 1.x was a UE4SS mod and
stays for the Steam beta branch `previousrelease` (game build `Build83_CL174209`, with UE4SS - AngelScript Fix):
[1.2.0 on Nexus](https://www.nexusmods.com/gothic1remake/mods/654) and the
[v1.2.0 release on GitHub](https://github.com/tslaceo/G1LockPickHelper/releases/tag/v1.2.0). It gets no updates. Its
source is the tag `v1.2.0` of this repository. To move from 1.x to 2.0 see "Upgrading from 1.x" under Install.

## Build from source

The mod is `mod/LockPickHelper/` (`GothicMod.json`, `Script/LockPickHelper/*.as`); its tests are in
`Script/LockPickHelper/UnitTests/` and stay out of the archive.

- Lock database: `python tools/gen_lockgraphs.py --modkit <G1R-Modkit clone> --commit <sha> --build <Build...>`
  (for example `--commit 619c2e6 --build Build102_CL175960`) reads the lock classes of the
  [Modkit](https://github.com/AlkimiaInteractive/G1R-Modkit) sources and rewrites
  `mod/LockPickHelper/Script/LockPickHelper/LockGraphs.as` and `tools/oracle/locks_data.lua`.
- Tests of the generator: `python -m unittest tests.test_gen_lockgraphs` (from the repository root). The checks
  against the Modkit sources run when `G1R_MODKIT_DIR` points to the clone; the ones against the 1.2.0 database need
  Lua 5.4 and the tag `v1.2.0`.
- Reference data for the solver: `lua tools/oracle/golden.lua` (Lua 5.4, from the repository root; about a minute) runs
  the 1.2.0 solver (`tools/oracle/solver.lua`) over the database and rewrites `UnitTests/GoldenSolver.as`.
- Deploy into the game: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy.ps1 -GameDir "<game folder>"`
  copies the whole package, tests included, to `G1R\Mods\LockPickHelper` (the game must be closed).
- Tests in the game: start the game with `-as-development-mode -Mods=LockPickHelper -LPHTests`. They run once in the
  main menu and write `%LOCALAPPDATA%\G1R\Saved\LockPickHelper-tests.log`; its last line is
  `tests done: <N> passed, <M> failed`. `-LPHTests=golden` adds the full reference runs of the solver. (A script
  compile error shows as a window of the game.)
- Release archive: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1` →
  `out\LockPickHelper-<version>.zip`, whose entries are `G1R/Mods/LockPickHelper/...` (extract it into the game
  folder). It packs only the files git tracks in `mod/LockPickHelper` and refuses to pack while that folder has an
  uncommitted or untracked file, or while `LPH::DebugAlways` in `Config.as` is true.
- The release build in the game, as a player gets it (for a manual-install check, and before a Workshop upload):
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-release.ps1 -GameDir "<game folder>"` extracts
  that archive into the game folder, replacing `G1R\Mods\LockPickHelper`, and checks the result. More in
  [docs/TECHNICAL.md](docs/TECHNICAL.md), "Release".

How the mod works inside: [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Credits

- Tautellini - the public notes on the lockpicking minigame (the LockpickSettings documentation and the G1R Lua
  modding notes). No code of theirs is used here.
- Alkimia Interactive - the Modkit, whose sources the lock database is generated from.
- The UE4SS team, and the author of UE4SS - AngelScript Fix for Gothic 1 Remake: 1.x ran on them.

## AI disclosure

The code, tests and documentation of this mod were written by Claude (Anthropic's AI model) under the direction
of tslaceo, who designed the features, played and tested every version in game and decided what ships.

## License

MIT - see [LICENSE](LICENSE). The lock layouts in `mod/LockPickHelper/Script/LockPickHelper/LockGraphs.as` and
`tools/oracle/locks_data.lua`, and the data derived from them (`mod/LockPickHelper/Script/LockPickHelper/UnitTests/GoldenSolver.as`,
`tests/fixtures/*`), come from the Gothic 1 Remake sources; they are not covered by the license and belong to the
game's rights holders.

This is an unofficial modification. It is not made, endorsed or supported by THQ Nordic.
