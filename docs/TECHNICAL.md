# How G1LockPickHelper works

Notes for modders and contributors. The mod is plain Lua 5.4 running in UE4SS; everything that touches the game
is in `main.lua`, `lock_reader.lua` and `overlay.lua` (and `menu.lua` loads Shared Mod Menu's bridge), the rest
is pure Lua with offline tests.

## Modules

| File | Role |
|---|---|
| `main.lua` | UE4SS glue: minigame detection, input hooks, the game-thread loop, settings, language, menu |
| `lock_reader.lua` | reads the lock name, the plate positions and the lockpicking skill |
| `lockdb.lua`, `lockgraphs.lua` | the lock database (generated) and the graph for a lock and a skill |
| `solver.lua` | safe key sequence with the fewest A/D moves (one breadth-first search from the goal over plate positions; W/S travel chosen greedily) |
| `tracker.lua` | follows the player's presses against the plate readings, replans on a mismatch |
| `view.lua` | the hint's model: a tape or lines of keys |
| `pad.lua` | letters or the game's gamepad icons for the hint, and the icon textures |
| `input_fix.lua` | when to hand the input back to the game after a minigame (the Shared Mod Menu fix) |
| `overlay.lua` | the UMG widget next to the lock |
| `autosolve.lua` | the autosolver: which key to press and when |
| `settings.lua` | `settings.ini`: schema, parsing, writing |
| `menu.lua` | the Shared Mod Menu tab (its bridge is loaded from Shared Mod Menu's folder) |
| `i18n.lua`, `lang/*.lua` | the language and its texts |

## Threading

UE4SS 3.0.1 (c838a8ac) runs game-thread actions, `LoopAsync` and key binds without serializing the mod's Lua
state, and Lua running on two threads at once corrupts it. So all work happens on the game thread: one
`LoopInGameThreadWithDelay(0)` loop (every frame), `NotifyOnNewObject`, the hooks on the minigame's input
functions and Shared Mod Menu's bridge. A key bind callback (F3, F4, and the minigame keys when the hooks are
unavailable) only stores an integer into a preallocated ring buffer; the loop drains it.

## The minigame

- Start: `NotifyOnNewObject("/Script/G1R.AbilityTask_LockPick", ...)`. The minigame is open while the task and
  its `Ability` are valid.
- Lock: `task.Ability.m_Lock` (an FName, e.g. `OC_Chest_Shadow316_Lock`). A chest or door that is not locked gets
  the task too, but its `Ability` never becomes valid; a real lock's name is readable within about 0.1 s. The mod
  waits 2 s for the name, then drops the session; until the name is known it shows nothing, not even auto-pick's
  note.
- Plates: `FindFirstOf("LockPickSubsystem").m_LockSceneActor.m_LockPieceData[1..7]`, front to back; hidden plates
  have `m_Plate.bHidden`. A plate's position is the X of its root component minus the X of its bar: one of seven
  settled values about 6.2 apart (holes 1..7, 4 is the middle); in between, the plate is moving.
- Cursor: the selected plate is not exposed. It starts on plate 1 (front); W selects the next plate towards the
  back, S the previous one, without wrapping. The mod tracks it.
- Moves: A/D move the selected plate one hole (D towards hole 7) and every plate connected to it (the
  connections of the selected plate only, not chained) with or against it. A move that would push a plate past
  hole 1 or 7 strains the pick, which may break; a broken pick resets the lock and the cursor. The lock opens
  when every plate is in hole 4.
- Readiness: the game ignores presses for about 0.7-1 s after the minigame opens. The mod starts after
  `ready_delay_ms` (2000) and `ready_frames` (30) and two equal plate readings.

## Lock database

Gothic 1 Remake runs an AngelScript fork of UE 5.4; its scripts are precompiled into
`G1R/Script/PrecompiledScript_Shipping.Cache`. Each lock class's `__InitDefaults` calls `AddPiece(index,
rotation)` per plate and `AddConnection(src, dst, dir)` per connection. `tools/extract_lockgraphs.py` finds
these calls in the bytecode and writes `lockgraphs.lua`: for each lock its plate count and its connections in
authored order (416 locks: 49 with 4 plates, 163 with 5, 183 with 6, 21 with 7). The start positions are not
needed (they are read from the game). The build the database was made from is stored with it; the mod warns
when the game's `G1R/Version/version.txt` names another build.

### Cache format

What `tools/extract_lockgraphs.py` relies on (build `Build83_CL174209`; offsets differ between builds, the parser
does not hardcode them):

- The file is uncompressed serialized Hazelight AngelScript modules: classes, functions and AngelScript bytecode
  with 64-bit compile-time pointers, plus reference tables at the end. Strings are `i32 length`, the bytes and a
  NUL (an empty string is just `00 00 00 00`).
- Every lock is an AngelScript class whose superclass is `UGothicLockConfig` (`/Script/G1R.GothicLockConfig`);
  the class name is in the string `__StaticType_<class>` that follows the superclass strings. All 416 sit in the
  modules `Items.GenericItems.LockPickGeneric` and `Items.TestLockDifficulty`.
- A lock class record is: class name, namespace, 8 flag bytes, `i32` method count, then the method
  `__InitDefaults`: name, namespace, 56 bytes of metadata, `i32 n` and `n` 32-bit words of bytecode.
- The bytecode of every lock uses six opcodes (low byte of a word): `0x02 PshC4 v` (2 words), `0x30 PshVPtr`
  (1), `0x3B PshRPtr` (1), `0x4F ADDSi` (2), `0x3D CALLSYS ptr` (3: an 8-byte function pointer), `0x0A RET` (1).
  Arguments are pushed right to left and `this` last, so `PshC4 dir, PshC4 dst, PshC4 src, PshVPtr, CALLSYS`
  is `AddConnection(src, dst, dir)`.
- A `CALLSYS` pointer is resolved to a name through the function reference table: the same 8 bytes followed by
  the function's name string (`AddPiece`, `AddConnection`, `__STATIC_NAME`, `opAssign`).
- The lock's own name is an FName literal: `PshC4 i; CALLSYS __STATIC_NAME` picks entry `i` of the FName table
  (`u32 N`, then N strings) and assigns it to `m_UniqueName`.

## Lockpicking skill

The skill is `FindFirstOf("AttributeSet_Lockpicking").LockpickPrecision.CurrentValue`. When the minigame starts,
the game removes the first `round(precision)` connections of the lock's authored list (from Tautellini's public
notes; checked in game for skill 1 and 2). The mod builds the graph the same way, so the hint and the solver see
the same lock as the player. An unreadable skill counts as 0.

## Input

The player's presses come from hooks on the task's input functions: `UpPressed` (W), `DownPressed` (S),
`LeftPressed` (A), `RightPressed` (D), `ResetPressed` (R) of `/Script/G1R.AbilityTask_LockPick`. They see the
keyboard and the gamepad. If a hook cannot be registered, the mod listens to the keys from `settings.ini`
through key binds instead (no gamepad, and the autosolver stays off).

No other gamepad button reaches a mod in the minigame: its widget (`W_LockPickUI_C`, a Blueprint of the C++
`LockPickUIWidget`) turns key events into the task's input functions in C++, and
`PlayerController:WasInputKeyJustPressed` sees no key while the minigame is open. So two resets of the player
within 500 ms (`[solve] double_reset`) start the autosolver like F3; a reset while the autosolver runs only stops
it.

## Gamepad icons

`CommonInputSubsystem:GetCurrentInputType()` (0 keyboard and mouse, 1 gamepad) tells the device of the last input;
the mod reads it every frame. The icon set follows the game's "Button icons" option,
`GothicGameUserSettings.ButtonGraphics` (0 do not use, 1 auto, 2 Xbox, 3 PlayStation 5, 4 Switch; "do not use" keeps
the letters unless `[hint] icons = gamepad`); with "auto" the game names the pad in
`CommonInputSubsystem:GetCurrentGamepadName()` (`PS5`, `XSX`, `SWITCH`). The option and the name are read every 2 s
and at once when the input type changes. If `CommonInputSubsystem` is not found within 10 s of the start, one log
line says so; with `[hint] icons = auto` the letters stay. The icons are the game's textures
`/Game/UI/Textures/Common/HotkeysIcons/T_Icon_PS_Dpad<Up|Down|Left|Right>` (Xbox: `T_Icon_Xbox_Dpad…`, Switch:
`T_Icon_Switch_<Up|Down|Left|Right>`), drawn in a UMG `Image` and tinted like the letters: the icon's dark circle
stays dark, its symbol takes the colour.

## Shared Mod Menu input fix

Shared Mod Menu, closed over the minigame, leaves the input on its UI (the minigame owns the mouse cursor then), and
the game does not switch it back when the minigame ends: the hero cannot walk. With Shared Mod Menu installed the mod
waits after each minigame until the game hides the cursor (200 ms and 5 frames in a row, within 10 s) and calls
`WidgetBlueprintLibrary.SetInputMode_GameOnly(PlayerController, false)` once, for the player controller found when
the minigame closed (a load ends the wait, see "Loading a save"). A cursor that stays shown (a chest window) is
left alone, and so is one that cannot be read. Right before the call the mod checks for an open menu: a plain
`UserWidget` in the viewport (`FindAllOf("UserWidget")`) that is not the mod's own and was not on screen when the
minigame opened - Shared Mod Menu's window is one; another mod's HUD that was already there is not. An open menu owns
the input; the call under it would let Esc through to the game's pause menu, and closing the menu over the pause
leaves the input on its UI. So the call waits for it: the check repeats about every 0.5 s while the menu stays open,
up to 60 s after the minigame (then one log line, "input fix gave up"). Two scans per minigame when no menu is open.
`[general] smm_fix = false` (the switch "Fix stuck controls" in Shared Mod Menu) turns the fix off.

## Loading a save

Each load (F9, a saved game, back to the main menu) makes a new player controller, and the game calls its
`PlayerController:ClientRestart` (the hook UE4SS's CheatManagerEnabler uses too). The old world's objects stay
readable a few seconds more, then the game frees them, and UE4SS's `IsValid()` cannot always tell a freed object:
reading the old minigame's task crashed the game after F9 during an autosolve, and so did moving the hint's dropped
widget at a settings change after F9. So at that hook the mod forgets every object of the old world without reading
it - the minigame and its autosolver, the lock scene, the hint's widget and the fonts and icons it found, the input
fix's wait, the objects found with `FindFirstOf` - and keeps the new controller. The next hint builds a new widget. Without the hook (one log line) the minigame
ends when the game frees it, as before 1.1.2.

## Tracker and autosolver

The player reads the autosolver as "auto-pick" (the hint's notes, Shared Mod Menu, `settings.ini`); the code and
`UE4SS.log` keep "autosolve".

- The tracker applies each press to the expected positions at once and checks them against the settled plate
  readings; a move that does not show within `grace_ms` (1200) or a reading that disagrees makes it re-read the
  lock and replan. When the cursor cannot be inferred, the new hint starts with up to n−1 S presses to park it on
  plate 1.
- The autosolver presses the hint's current key by calling the same input function the game calls; the hook
  inside that call passes the press to the tracker, and a flag tells the autosolver's own calls from the
  player's. After a W/S it waits 60 ms; after an A/D, until the plates confirm it. It stops when the lock opens,
  on any press of the player, when the minigame closes, when an A/D does not show within 2.5 s, and after 3
  replans in a row.

## Language

`[general] language = auto` follows the game's culture:
`StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary"):GetCurrentCulture()`, read on the
game thread every 2 s; it changes as soon as the player switches the game's language. Do not pass a Lua string
to a UE function's FName parameter from UE4SS 3.0.1 Lua: it crashes the game.

## Tests

`tests/*_test.lua` run each module against fakes of UE4SS and of the minigame (`main_test.lua` plays whole
minigames: hint, presses, autosolver, settings, menu, language). `tests/test_extract.py` checks the extractor
against `tests/fixtures/groundtruth.json` (a lock checked in game) when `G1R_GAME_DIR` is set.
