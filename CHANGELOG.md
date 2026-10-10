# Changelog

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
