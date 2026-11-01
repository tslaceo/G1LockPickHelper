# Changelog

## 2.0.1

- Fixed: with "Gold letters" off, the gamepad icons came out darker and more orange than the letters and the game's own
  icons. The game's icons are already beige, and the mod tinted them beige once more. Now they look as the game draws
  them; with "Gold letters" the current key's icon is a brighter gold, and the done and missed keys are nearer the
  green and the red of the letters.
- README: the known limit about remapped walking was wrong. The minigame always takes W/A/S/D, whatever keys walking is
  bound to, so the hint's letters are always the keys to press.

## 2.0.0

LockPick Helper is now a mod for the game's official Modkit and works on the current game version (`Build102`),
which refuses to start with UE4SS. The features are the ones of 1.2.0.

- Install from the Steam Workshop, or by hand: extract the archive into the game folder (the one that contains the
  `G1R` folder), so that `G1R\Mods\LockPickHelper\GothicMod.json` exists. No UE4SS, no Shared Mod Menu. The game warns
  "This save was made with a different modlist" when you load a save made without the mod (or with another list of
  mods): choose Continue anyway.
- The settings are in the game's options, on the Game tab, in the block "[Mod] LockPick Helper" (20 rows), in the
  language of the mod. They replace `settings.ini` and the Shared Mod Menu tab; a `settings.ini` of 1.x is not read, the
  settings start from their defaults. "Dark background" is one row for the tape and the lines. The Shared Mod Menu
  buttons "Show example" and "Reset position" and its input fix are gone. The settings can be changed between
  lockpicking minigames only: the options cannot be opened during one.
- Same as before: the hint (tape or lines, plain or gold letters, dark background, counter, shake on a miss, smooth
  scroll, folded repeats), auto-pick (F3 in the minigame and right before it, "Always auto-pick", reset twice,
  countdown), the game's gamepad icons, English and Russian, the lockpicking skill. F4 and F3 work in the minigame
  and outside it; they are fixed keys now (the game's options cannot take a key).
- New: while the solver prepares a big lock the hint says "Thinking…" ("Считаю…").
- Changed: the row "Gothic style" is now "Gold letters". With it off, the keys look like the minigame's own key prompts:
  a square dark box with a thin beige border, and no shadow under the letter.
- The lock database comes from the Modkit sources of `Build102` (416 locks).
- The log is `%LOCALAPPDATA%\G1R\Saved\LockPickHelper.log`, new on every start. For a detailed log change `Debug=False`
  to `Debug=True` in the section `[/Script/Angelscript.LPH_Settings]` of `GameUserSettings.ini`, or add `-LPHDebug` to
  the game's launch options (README, "Report a bug").
- 1.x stays for the Steam beta branch `previousrelease` (game build `Build83`, with UE4SS) and gets no updates.

## 1.2.0

- Auto-pick shows how long it still needs: "Auto-picking… 12 s" counts down to the open lock. `[solve] timer`
  ("Countdown" on the Auto-pick tab of Shared Mod Menu) turns it off.
- The lines got a dark background too: `[lines] plate` ("Dark background" on the Lines tab of Shared Mod Menu), off
  by default, like the tape's. A `settings.ini` from 1.1 keeps working.

## 1.1.3

- With "Always auto-pick" on, opening a chest or door that is not locked no longer shows "Auto-pick: waiting for the
  lock" for two seconds. The game starts the lockpicking task for those too, just without a lock; the note now waits
  until the mod knows the lock.

## 1.1.2

- Fixed rare crashes after loading a save (F9): a few seconds after a load during the lockpicking minigame (seen with
  auto-pick running), or at a change in Shared Mod Menu after a load. The mod kept the old world's minigame and its
  own hint widget until the game freed them. Now it lets go of the old world as soon as the game makes the new player
  controller.

## 1.1.1

- Shared Mod Menu fix: it no longer hands the controls back under an open Shared Mod Menu. F2 pressed right after
  leaving a lock used to let Esc open the game's pause menu behind the menu, and closing the menu over the pause
  left the hero unable to walk.
- `[general] smm_fix` (Shared Mod Menu: "Fix stuck controls") turns the Shared Mod Menu fix off, in case it gets in
  the way of another mod. A `settings.ini` from 1.1.0 keeps working; the fix stays on.
- Clearer texts in the hint, Shared Mod Menu and `settings.ini`; the autosolver is called auto-pick everywhere. An
  existing `settings.ini` keeps its old comments until a change in Shared Mod Menu rewrites it.

## 1.1.0

- Gamepad: the hint shows the game's own button icons (PlayStation, Xbox, Switch, as the game's "Button icons"
  option) while you play with a gamepad, letters on the keyboard; `[hint] icons` and `[hint] gamepad` fix them.
  With the game's "Button icons" set to "Do not use" the hint shows letters (unless `[hint] icons = gamepad`).
  The icons take the hint's style colours.
- Reset twice (gamepad Triangle / Y, keyboard R R) starts the autosolver - the gamepad has no free button in the
  minigame. `[solve] double_reset` turns it off.
- Shared Mod Menu opened during the minigame no longer leaves the hero unable to walk after it.
- Updating from 1.0: your `settings.ini` keeps working, the new keys (`icons`, `gamepad`, `double_reset`) use their
  defaults until they are added. The file is rewritten with them (and their comments) when you change any setting
  in Shared Mod Menu, or after you delete it (the next start writes a new one).

## 1.0.0

First public release.

- Hint with the key sequence that opens the lock, as a tape or in lines, simple or gothic style; follows the
  player's presses (keyboard and gamepad) and replans when the lock disagrees.
- Autosolver: F3 in the minigame or right after using a chest; "Auto-pick" solves every lock; only moves that
  cannot strain the pick.
- Lock layouts extracted from the game; connections removed by the lockpicking skill are removed from the hint.
- English and Russian, following the game's language by default.
- Settings in `settings.ini` and, optionally, in Shared Mod Menu.
