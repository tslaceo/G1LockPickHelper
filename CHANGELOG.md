# Changelog

## 1.1.3

- With auto-pick always on, opening a chest or door that is not locked no longer shows "Auto-pick: waiting for the
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
