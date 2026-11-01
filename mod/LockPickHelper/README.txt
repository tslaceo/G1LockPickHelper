LockPick Helper 2.0.1 - lockpicking helper for Gothic 1 Remake (a mod for the game's Modkit)

Shows the key sequence that opens the lock in the lockpicking minigame and follows
you through it. F3 lets the mod pick the lock for you, using only moves that cannot
strain the pick.

Needs the current Gothic 1 Remake (tested on Build102_CL175960). No UE4SS, no other mods.

Install
- Steam Workshop: subscribe to "LockPick Helper: hint and auto-pick":
  https://steamcommunity.com/sharedfiles/filedetails/?id=3830422263
- By hand: extract this archive into the game folder (the one that contains the G1R
  folder), so that G1R\Mods\LockPickHelper\GothicMod.json exists. README.txt and
  LICENSE.txt are in that folder too. Start the game: the main menu should show
  "1 mods enabled" (this mod alone). If it does not, start the game with the launch
  option -ModManagementUI and enable LockPick Helper in the game's mod list.
Use one way, Workshop or by hand, not both: to switch to Workshop, delete
G1R\Mods\LockPickHelper first.
Uninstall: unsubscribe, or delete the folder G1R\Mods\LockPickHelper.
From 1.x: the current game does not start with UE4SS, so remove it first (dwmapi.dll
and the ue4ss folder in G1R\Binaries\Win64; the 1.x mod is inside it) and, on the Steam
beta previousrelease, switch the beta back to None. settings.ini of 1.x is not read.
A save made with another list of mods makes the game ask "This save was made with a
different modlist": choose Continue anyway.

Keys: F4 shows/hides the hint; F3 auto-picks the open lock (or the one you open within
5 seconds) and stops auto-pick. Gamepad: the hint shows the game's button icons; press
reset twice (Triangle / Y, R R on the keyboard) to auto-pick the lock.

Settings: Options > Game, the block "[Mod] LockPick Helper" (20 rows). They can be
changed between lockpicking minigames only: the options cannot be opened during one.
The labels are in the language of the row Language (0: the game's language); a change
of that row shows in the menu after a save load or a restart.

Status: not in active development (the author has finished the game and plans no new
playthrough for now). Every feature was tested in game; compatibility with other mods
was not tested.

Report a bug: attach %LOCALAPPDATA%\G1R\Saved\LockPickHelper.log (new on every start).
For a detailed log close the game and, in the section
[/Script/Angelscript.LPH_Settings] of
%LOCALAPPDATA%\G1R\Saved\Config\Windows\GameUserSettings.ini, change Debug=False to
Debug=True (the game writes that line itself; if the line or the section is missing,
add it at the end). Simpler: add -LPHDebug to the game's launch options (Steam: the
game's Properties > Launch Options). The first line of the log then says "debug on".
Repeat what went wrong and attach the log.

A DualSense shows Xbox icons? Steam Input makes it look like an Xbox pad: set the row
"Icon set" to 1 (PS), or turn Steam Input off for the game.

Older game version (the Steam beta branch previousrelease, Build83): use 1.2.0, a UE4SS
mod: https://github.com/tslaceo/G1LockPickHelper/releases/tag/v1.2.0

Source code, bug reports, technical notes: https://github.com/tslaceo/G1LockPickHelper
License: MIT (LICENSE.txt). The lock data generated from the game's sources is not covered.
This is an unofficial modification. It is not made, endorsed or supported by THQ Nordic.
