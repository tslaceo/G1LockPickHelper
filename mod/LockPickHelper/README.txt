LockPick Helper 2.0.0 - lockpicking helper for Gothic 1 Remake (a mod for the game's Modkit)

Shows the key sequence that opens the lock in the lockpicking minigame and follows
you through it. F3 lets the mod pick the lock for you, using only moves that cannot
strain the pick.

Needs the current Gothic 1 Remake (tested on Build102_CL175960). No UE4SS, no other mods.

Install
- Steam Workshop: subscribe to LockPick Helper.
- By hand: this archive holds the folder LockPickHelper. Extract the archive into the
  game's G1R\Mods folder (make Mods if it is not there), so that
  G1R\Mods\LockPickHelper\GothicMod.json exists. README.txt and LICENSE.txt are in that
  folder too. Start the game: it lists the mod as enabled (the main menu shows
  "1 mods enabled" with this mod alone). The game's mod list (launch option
  -ModManagementUI) turns it off and on.
Uninstall: unsubscribe, or delete the folder G1R\Mods\LockPickHelper.
A save made with another list of mods makes the game ask "This save was made with a
different modlist": choose Continue anyway.

Keys: F4 shows/hides the hint; F3 auto-picks the open lock (or the one you open within
5 seconds) and stops auto-pick. Gamepad: the hint shows the game's button icons; press
reset twice (Triangle / Y, R R on the keyboard) to auto-pick the lock.

Settings: Options > Game, the block "[Mod] LockPick Helper" (20 rows). They can be
changed between lockpicking minigames only: the options cannot be opened during one.

Report a bug: attach %LOCALAPPDATA%\G1R\Saved\LockPickHelper.log (new on every start).
For a detailed log close the game, add the line Debug=True under
[/Script/Angelscript.LPH_Settings] in
%LOCALAPPDATA%\G1R\Saved\Config\Windows\GameUserSettings.ini (add that section if it
is not there), repeat what went wrong and attach the log.

A DualSense shows Xbox icons? Steam Input makes it look like an Xbox pad: set the row
"Icon set" to 1 (PS), or turn Steam Input off for the game.

Older game version (the Steam beta branch previousrelease, Build83): use 1.2.0, a UE4SS
mod: https://github.com/tslaceo/G1LockPickHelper/releases/tag/v1.2.0

Source code, bug reports, technical notes: https://github.com/tslaceo/G1LockPickHelper
License: MIT (LICENSE.txt). The lock data generated from the game's sources is not covered.
This is an unofficial modification. It is not made, endorsed or supported by THQ Nordic.
