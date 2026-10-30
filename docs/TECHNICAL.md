# How LockPick Helper 2.0 works

Notes for modders and contributors. The mod is a package of the game's official Modkit (`mod/LockPickHelper/`) written
in Hazelight's AngelScript for UE 5.4 ([docs](https://angelscript.hazelight.se), not the original AngelScript;
[the game's types](https://alkimiainteractive.github.io/G1R-Modkit/script-reference/); the game's own scripts in the
[Modkit repository](https://github.com/AlkimiaInteractive/G1R-Modkit) are the best examples). Everything that does not
need the game - lock database, solver, tracker, autosolver, hint model, session controller, texts, settings as numbers -
is in classes and structs that touch no game object and have tests that run in the game. A thin layer ties them to it.
All script runs on the game thread; there are no locks or queues.

## Modules

`Script/LockPickHelper/`:

| File | Role | Touches the game |
|---|---|---|
| `Config.as` | the internal numbers (those of `config.lua` of 1.2.0 unchanged, and the new ones), `LPH::ModVersion`, `LPH::DebugAlways` | no |
| `Keys.as` | `ELPH_Key` W S A D R | no |
| `Values.as` | `FLPH_Values`: the settings as plain numbers, `Clamped`, `SameValues` | no |
| `Texts.as` | the notes and the row labels, English and Russian | no |
| `LockDb.as`, `LockGraphs.as` | the lock database; its generated data | no |
| `Solver.as` | the solver | no |
| `Tracker.as` | follows the player's presses and the plate readings, replans | no |
| `AutoSolve.as` | which key to press and when, the countdown | no |
| `View.as` | the hint model: the tape or the lines | no |
| `Plates.as` | `LPH::ReadingOf`: the lock pieces the game reports -> one reading (holes, cursor, visible plates) | no |
| `Icons.as` | letters or the gamepad icons, by the settings and what the game says | no |
| `Controller.as` | one minigame session: phases, F3/F4, notes, auto-pick, what to draw | no |
| `Look.as` | sizes, colours, fonts of the hint | no |
| `Log.as` | `LPH::NowMs()`, the log file | file only |
| `Settings.as` | `ULPH_Settings`: the 20 rows of the game's options, `LPH::ReadValues()` | yes |
| `Game.as` | `LPHGame::`: every read from the game (lock, skill, plates, language, icons, build) | yes |
| `Mod.as` | `ULPH_Mod`: the game instance subsystem that owns the log, the database, the controller | yes |
| `LockPickExtension.as` | the extension of the minigame window: lifecycle, tick, presses | yes |
| `KeyCatcher.as` | the invisible widget that takes F3, F4 and the D-pad in the minigame | yes |
| `Hotkeys.as` | F3/F4 outside the minigame; the notes shown outside it | yes |
| `HintWidget.as`, `ViewportLayer.as` | the UMG widgets of the hint; the mod's layer in the viewport | yes |
| `UnitTests/` | the tests (not in the archive) | |

## The minigame window

`ULPH_LockPickExtension` extends `UGothicModExt_WidgetExtension` of `W_LockPickUI_C`
(`AddToWidgetOfClass = /Game/UI/LockPick/W_LockPickUI.W_LockPickUI_C`) with `RequiresTick() = true`. The window is made
once per world and shown again for every minigame: its `Construct` runs when a minigame opens, `Tick` every frame while
it is open, `Destruct` when it closes or the world goes.

- **Construct.** The settings (`Mod.Configure()`), the icon set, `Controller.Opened` (the "Always auto-pick" setting
  arms the session here, so the settings come first), the window's press events heard (once per window), the hint
  attached to the window's root canvas, the key catcher with the focus, the search for the lock started.
- **Tick**, in this order: the lock (tried at once and every 100 ms; after 2 s without one the minigame has none),
  the icons, the catcher's focus (taken back every 500 ms), the plates (read when the controller asks), the
  controller's `Tick`, the autosolver's key, the drawing (only when the controller's signature changed), the hint's
  animation.
- **Destruct.** The session ends (`Controller.Closed`). The hint forgets the window's widgets *without calling into them*:
  the world may be going. The window outlives the minigame, so the next Construct takes the old plate out of the
  canvas first.

What must outlive a world is in `ULPH_Mod` (a `UScriptGameInstanceSubsystem`, made once at the start of the game): the
log, the database, the controller. It holds no widget, actor or component. The world subsystems of `Hotkeys.as` are made
anew in every world.

## Lock, plates, cursor

**The lock.** The minigame window does not say which lock it is. The hero's interaction ability does: for a chest
`GA_Human_OpenContainer`, for a door `GA_Human_OpenDoor`; it is a `UGameplayAbilityInteractionBase`, and its
`m_InteractiveActor` is the object. `Hero.GetAbilitySystemComponent()` -> `GetAllAbilities` -> `FindAbilitySpecFromHandle`
-> `Spec.GetAbilityInstances()`; `IsActive()` is not in the script API, so an ability counts when `m_AbilityEnded` is
false. `AInteractiveObjectActor.GetInteractiveObjectDefinition().m_Lock` is the lock's name (an `FName`). An object with
no lock (a chest or door that is not locked opens the minigame too) gives no lock and no hint, and no fallback: the lock
of another chest nearby is not its lock. With no such ability the nearest object with a lock within 4 m is taken.

**The skill.** `Hero.GetAttributeValue(UAttributeSet_Lockpicking, n"LockpickPrecision", 0)`. When the minigame starts, the
game removes the first `round(precision)` connections of the lock's authored list (from Tautellini's public notes;
checked in game on 1.x for skill 1 and 2). The mod builds the graph the same way, so the hint and the solver see the same lock
as the player. An unreadable skill counts as 0.

**The plates.** `GetAllActorsOfClass(AGothicLockPieceActor)` gives 21 actors in every lock scene: 7 plates (`m_LockPieceType`
1), 7 bars (2) and 7 latches (3), `m_PieceId` 0..6 front to back. A plate's hole is its root's X minus its bar's X
(`RootComponent.GetRelativeLocation()`): hole 1..7 is -18.5, -12.2, -6.1, 0, 6.3, 12.5, 18.7 (within 0.3; 4 is the
middle, where an open lock rests). Any other value means the plate is moving (the game animates a move for about a
second), and the reading is not settled. A lock with fewer than 7 plates does not hide the others: they stand about
100,000 units away from the lock, still "visible". So `LPH::ReadingOf` (`Plates.as`, a pure function over `FLPH_Piece`s) counts a plate
as shown when it is not hidden and stands within 200 units, on every axis, of plate 0; the controller compares that
count with the database's plate count and shows "Can't read the lock" when they differ (a lock changed by another mod).
The plates are read once per 50 ms, and only while the controller wants it.

**The cursor.** The selected plate's material has the vector parameter `HighlightColor`: (0.65, 0.70, 1.0) on the selected
plate, white on the others, none while the lock resets. `Cast<UMaterialInstance>(Prim.GetMaterial(0)).VectorParameterValues`
reads it. 1.x had to infer the cursor from the presses; 2.0 still tracks it from the presses and uses the highlight
when the tracker does not know it and no press waits for the game.

**Readiness.** The game ignores presses for the first moments. The session starts tracking after 2000 ms and 30 frames
since the minigame opened, and two settled readings in a row that agree.

## Presses

`ULockPickUIWidget` (the base of `W_LockPickUI_C`) has the events `m_OnUpPressed`, `m_OnDownPressed`, `m_OnLeftPressed`,
`m_OnRightPressed`, `m_OnResetPressed` (`FOnButtonPressedEvent`). The minigame's task subscribes to them. So:

- `Broadcast()` is a press of W / S / A / D / R for the minigame, and it is how auto-pick presses;
- `AddUFunction` hears every press of the player, keyboard and gamepad alike.
- `m_OnBackPressed` closes the minigame and is never touched.
- At the first Construct the task has not subscribed yet (`IsBound` is false); presses before that are ignored by the
  game anyway.

A handler is called synchronously inside `Broadcast`, so the extension tells its own presses from the player's with a
flag that is up for the duration of its call. When the handler did not see the key, `Controller.OwnKeyMissed` stops
the autosolver (it could no longer tell its keys from the player's). Six presses 60 ms apart were all taken by the game.

## Keys: F3, F4, the D-pad

- **Outside the minigame.** `UInputComponent::Get(Hero).BindKey(EKeys::F3 / F4, IE_Pressed, ...)` in
  `HandleReadyForPlay` of `ULPH_Hotkeys` (a `UGothicModExt_WorldSubsystem`): once per world, because a load makes a new
  hero. It does not run in the main menu.
- **In the minigame** no key reaches the player's input: neither a key binding nor `WasInputKeyJustPressed` sees
  anything. So the extension puts `ULPH_KeyCatcher`, an invisible focusable `UUserWidget` of 1x1, into the window's
  canvas (`Window.ConstructWidget`, `SetbIsFocusable(true)`, visibility `Visible`) and gives it the focus
  (`SetUserFocus(PC)` and `SetKeyboardFocus()`). It gets every key first:
  - F3 and F4: handled (`Handled`); a held key does not toggle twice.
  - Everything else (W/S/A/D, R, Esc, the face buttons): `Unhandled`, it bubbles up to the window, which works as
    without the mod.
  - The D-pad: for the minigame it is the navigation of its own focus, which is on the catcher now, so the D-pad
    stopped working (`RequestRefreshFocus()` did not give the focus back). The catcher passes it on itself: the
    extension broadcasts the matching event and the catcher answers `Handled`. For the tracker and the autosolver it is
    a press of the player. A held D-pad arrives in repeats about every 100 ms, and they are passed on too.
  - Alt+Tab takes the focus away; it is taken back every 500 ms.
  - A held key: `Input::InputEvent_IsRepeat` does not accept an `FKeyEvent` in this build, so the catcher keeps the set
    of keys held (`OnKeyDown` adds, `OnKeyUp` removes, forgotten when it gets the focus anew).
- F3/F4 go through `ULPH_Mod.Hotkey` (settings first, then the controller). Should one press arrive both ways, the same
  key the other way within 150 ms is not counted twice.
- The arrow keys do not move the pick (neither do they without the mod).

## The hint on screen

`ULPH_HintWidget` builds UMG widgets from script inside a canvas: the window's root `CanvasPanel`
(`AddChildToCanvas`), anchor (1; 0.45), alignment (1; 0.5), offset -760 in UI units by default (the game draws the lock
at a fixed UI distance from the right edge on every aspect ratio). The tree is a plate (a `Border`: a dark rounded box
with a gold outline, or clear) with a column of the counter, the message and the body. The body is the tape (cells of a
fixed width, so the slide needs no measuring) or the lines (tokens as wide as their text).

- The game's own assets, loaded by path with `System::MakeSoftObjectPath` and `FAssetPreload::BlockingLoad`: the fonts
  `Boucherie-Block_Font` (simple style) and `NotoSerif-Regular_Font` (`Bold` for the gothic style, `Default` for the
  counter and the notes), the D-pad icons `/Game/UI/Textures/Common/HotkeysIcons/T_Icon_PS_Dpad<Up|Down|Left|Right>`
  (Xbox: `T_Icon_Xbox_Dpad...`, Switch: `T_Icon_Switch_<...>`), tinted like the letters. An asset that does not load gives
  the engine font or the letter, with one log line per path.
- A new shape (layout, style, size, the tape's cells, the lines' size, the plate) builds the tree again; anything else
  changes the built widgets, and only where it changed. Tokens are made when a model first needs them, so a short plan
  costs a few widgets, not 40x12.
- `Draw` runs only when the controller's signature changes; `Animate` runs every frame (the tape slides for 120 ms
  after a press, the hint shakes for 300 ms after a miss).
- **Outside the minigame** (F3/F4 notes) `ULPH_NoteLayer`, a `UScriptWorldSubsystem`, draws messages on
  `ULPH_ViewportLayer`: a `UUserWidget` the size of the screen with an empty canvas, Z-order 1000, `HitTestInvisible`, made
  the first time a note shows in a world. The engine takes viewport widgets out when the world goes. While the minigame
  is open the window shows the notes, and the layer's own note hides.

## Lock database

Gothic 1 Remake's scripts ship in the Modkit: `Script/Items/GenericItems/LockPickGeneric.as` (346 lock classes) and
`TestLockDifficulty.as` (70). A lock is a class of `UGothicLockConfig` with `default m_UniqueName = n"..."`,
`default AddPiece(id, rotation)` for each plate and `default AddConnection(src, dst, dir)` for each connection. The
game does not let scripts read a lock's layout back (only these three members are exposed), so a generator copies it
out of the sources.

`tools/gen_lockgraphs.py --modkit <clone> [--commit <sha>] [--build <Build...>]` reads every `class X : UGothicLockConfig`
(comments stripped; a keyword line it does not recognise, an unparsable or out-of-range line stops it) and writes:

- `LockGraphs.as`: `LPH_RegisterLockGraphs(ULPH_LockDb)` with `Db.AddLock(n"Name", plates)` and
  `Db.AddEdge(src, dst, dir)` in authored order, plus `LPH::LocksSource` (the Modkit commit) and `LPH::LocksBuild` (the
  game build). 416 locks: 49 with 4 plates, 163 with 5, 183 with 6, 21 with 7 (one 3,600-statement function compiles).
- `tools/oracle/locks_data.lua`: the same for the Lua reference of the solver (plates 1-based), with each plate's start
  hole, `4 - rotation` (checked in game on `OC_Chest_Mud_Lock`: 7 5 7 7 5).

Names are compared without case (an `FName` does). Where a class has two `m_UniqueName` lines (`UOC_Mages_Room_01_Lock`)
the last wins, as in 1.x. The start line of the log names the database's build, and a `WARNING` line comes when
`G1R/Version/version.txt` names another one. The 416 locks equal the database of 1.2.0, which was extracted from the game's
precompiled script cache.

## Solver

`solver.lua` of 1.2.0 ported, and the same sequences are required (the golden tests). Plates are 0..n-1 front to back,
a hole is 1..7, the lock is open when every hole is 4. A move is A (-1) or D (+1) of the selected plate and, with it,
the plates its connections list (with or against it); a hole that would leave 1..7 strains the pick, so it is not a
move. Moves can be undone, so one breadth-first search from the open lock gives every state's distance to it. A state
is `sum((hole - 1) * 7^plate)`, and travels as a packed number (4 bits a plate) from which one table lookup per two
plates says which moves are open. Among the paths with the fewest A/D presses the one of 1.2.0 is chosen: plate by
plate, A before D, the first of the least cursor travel; W/S walk the cursor first.

A 7-plate lock has 823,543 states and needs about 230 ms of work (the probe's plain version took 1.8 s). `Begin` only
builds the moves; `Step(BudgetMs)` fills `Dist` and searches in pieces of 1000 states, looking at the clock after each,
and does at least one piece per call. The controller gives it 6 ms a frame, so a lock is prepared over about 40 frames
with no hitch. Until it is ready the hint says nothing, then "Thinking…" once the 2 s ready delay has passed. The
last two prepared locks stay in memory (by lock and skill).

## Tracker and autosolver

The player reads the autosolver as "auto-pick"; the code and the log keep "autosolve". Both are ports of 1.2.0.

- The tracker applies each press to the expected plate positions at once and checks them against the settled readings;
  a move that does not show within 1200 ms or a reading that disagrees makes it take the game's holes, infer the cursor
  from the plate that moved, and replan. When the cursor cannot be inferred the new hint starts with up to n-1 S presses
  to park it on plate 0 (S does not wrap); a known highlight replaces that. A strained move may break the pick, which
  resets the lock and the cursor: strains and a return to the starting holes forget the cursor. R sends the lock back
  to the start.
- The autosolver presses the hint's current key. After a W/S it waits 60 ms; after an A/D, until the plates confirm it.
  It stops when the lock opens, on any press of the player, when the minigame closes, when an A/D does not show within
  2.5 s, and after 3 replans in a row.
- While it runs the counter's place shows the seconds it still needs (the "Countdown" row): each A/D counts 400 ms and
  each W/S 70 ms (measured in game over 760 presses: an A/D takes 370-420 ms until the next press, a W/S 60-70 ms),
  rounded up. A replan recounts it.
- Two resets of the player within 500 ms start it like F3, when it is off ("Double reset"); a reset while it runs only
  stops it.
- F3 outside the minigame arms the session that opens within 5 s (with "Always auto-pick": skips it); F3 again in that
  time goes back to the setting.

## The controller

`ULPH_Controller` is one session, from the window opening to its closing, and knows nothing of the game. The glue tells
it what happens (opened, the lock, the plates read, the player's presses, F3, F4, closed), asks for the key to send, and
draws what it returns. Phases: `Lock` (waiting for the lock) -> `Prepare` (the solver works) -> `Ready` (waiting for the
minigame to take presses and for two equal readings) -> `Track`; `Idle` when there is no hint (not in the database, the
visible plates do not fit, no lock).

`Display` decides in this order: the note (F3/F4/stops; shown with the hint hidden too, and outside a minigame), the
session's message, the hint (or the tracker's "no safe path" / "can't read"; nothing once the lock is open),
"waiting for the lock", "Thinking…", nothing. F4 off hides all but the note. Its `Sig` is a string that changes exactly
when the picture has to: session, settings version, icon set, whether the autosolver runs, the tracker's plan, index,
history length, pressed and misses. The glue asks `DisplaySig` every frame (no copies) and `Display` only when it
changed, so the model, which copies the tracker's keys and history, is built once per change. Every time the
controller reads is the caller's `LPH::NowMs()`, so the tests keep their own clock.

## Settings, language, icons

- **Settings.** `ULPH_Settings : UGothicModExt_UserSettings` with `UCLASS(Config=GameUserSettings)`: 20 `FModUserSettingsBool`
  / `FModUserSettingsInt` properties, `CategoryName` "LockPick Helper"; the game lists them on the Game tab as
  "[Mod] LockPick Helper" and keeps them in `GameUserSettings.ini` under `[/Script/Angelscript.LPH_Settings]`. The class
  name and the property names are in the players' files and must not change. The script sees only a row's `Value` /
  `bValue`; the limits are repeated in `Values.as` (`Clamped`) because a hand-edited ini can hold anything.
  `Initialize()` gives each row a new struct with the same value and the label in the mod's language (a row has no
  setter for its label). A plain `UPROPERTY(Config) bool Debug` is no row and is saved all the same.
- **Reading.** The game keeps the values on the class default object: `ReadValues()` = `ValuesOf(ULPH_Settings.DefaultObject)`.
  `Mod.Configure()` reads them at the start of the game, at every minigame start (before `Opened`) and right before every
  F3/F4; a change is logged. The options cannot be opened during a minigame, so a change reaches the next one.
- **Language.** "0 as in the game" is `UGothicGameUserSettings.DisplayLanguage` (`Russian` -> Russian, otherwise English);
  `Internationalization::GetCurrentCulture()` is `en-US-POSIX` in the main menu and does not do. The texts are two
  tables in `Texts.as`; the Modkit's own text database is for dialogues and is not used.
- **Icons.** `UCommonInputSubsystem::Get(PC)`: `GetCurrentInputType()` (0 keyboard and mouse, 1 gamepad) every frame in
  the minigame, `GetCurrentGamepadName()` (`PS5`, `XSX`, `SWITCH`, or `Generic` before CommonUI has named the pad). The set
  follows the game's "Button icons" option, `UGothicGameUserSettings.ButtonGraphics` (0 do not use, 1 auto, 2 Xbox, 3 PS5,
  4 Switch), read every 2 s and after each `Configure`; with "auto" the pad's name decides. Right after a switch to the
  gamepad `Generic` is the name for about 1.4 s, so a set that goes by the name keeps the old one for up to 1500 ms
  (otherwise the hint flashes Xbox) and a known name applies at once. The D-pad icons are the only icons used.

## Log

`LockPickHelper.log` in `%LOCALAPPDATA%\G1R\Saved\` (the release game has no log of its own for mods), a new file on
every start, UTF-8 without a byte order mark (`FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM`; the default turned the
file into UTF-16 as soon as a line held Cyrillic). The lines wait in memory and the whole file is written again at most
every 250 ms (`FlushIfDue()` each frame) and at the end of a minigame.

The start line: the mod's version, the game build, the database's build, source and lock count, the language (setting and
the game's), the icon settings, how F3/F4 are caught, whether debug is on. `Line()` always writes (the start, the
settings and their changes, the lock of each minigame, auto-pick's starts and stops, warnings); `Debug()` writes only
with debug on: every reading and press, the draws, the key catcher, the lock search.

Debug is on when `LPH::DebugAlways` (`Config.as`) is true, when the command line has `-LPHDebug`, or when the hidden
`Debug=True` is in `GameUserSettings.ini` under `[/Script/Angelscript.LPH_Settings]`. `DebugAlways` is a switch for the
in-game checks of 2.0; `scripts/package.ps1` refuses to pack while it is true. In a release only the last two are left.

## Loading a save

Each load (F9, a saved game, back to the main menu) makes a new world with a new hero and a new window. Nothing of
the old world is kept: the minigame window and its extension die with the world (its `Destruct` ends the session, and
the hint forgets the widgets without a call into them), the world subsystems are made anew (F3/F4 bound again,
`WorldReady` closes a session whose window gave no `Destruct`), the note layer belongs to its world, and `ULPH_Mod` holds
no world object. F9 in the middle of a minigame, and in the middle of auto-pick, ended with no crash in game.

## Tests

- **In the game.** The release game does not run Hazelight's `Test_...` functions, so the mod has its own runner
  (`UnitTests/TestRunner.as`): with `-LPHTests` on the command line, `OnWorldBeginPlay` of the main menu world runs
  `LPHTests_<Module>(ULPH_TestRun)` of every module once and writes `Saved/LockPickHelper-tests.log` (`case <name>` before
  each group, `FAIL <case>: ...` for a failure, last line `tests done: <N> passed, <M> failed`). A script error stops the
  run with no last line; the last `case` line says where. About 1,750 checks. `-LPHTests=golden` adds the full runs of
  the solver against the sequences of 1.2.0; `-LPHTests=defaults` also compares the rows' declared defaults with
  `FLPH_Values` (right only on a profile without the mod's section in `GameUserSettings.ini`). `-LPHPreview` shows
  the hint in the main menu on the viewport layer (for pictures). Run it with `-as-development-mode`, which shows the
  compile errors in a window.
- **Reference data.** `tools/oracle/solver.lua` is a byte copy of the 1.2.0 solver; `lua tools/oracle/golden.lua` runs it
  over `locks_data.lua` (every lock, skill 0-2, the start holes and a cursor) and writes `UnitTests/GoldenSolver.as`: 1206
  full cases (55 of them without a safe path) and 17 quick ones. The solver must give the same keys.
- **The generator.** `python -m unittest tests.test_gen_lockgraphs`: the parser on `tests/fixtures/modkit_locks_sample.as`,
  the outputs, and, with `G1R_MODKIT_DIR` set, the 416 locks of the Modkit, the lock `OC_Chest_Digger526_Lock` against what
  1.x read in game (`tests/fixtures/groundtruth.json`), the start holes of `OC_Chest_Mud_Lock`, equality with the 1.2.0
  database, and that the committed `LockGraphs.as` is what the generator writes.
- Not covered by tests, checked in game: the extension, the focus catcher, the key binding, the widgets in the window
  and in the layer.

## AngelScript pitfalls of this build

- The game silently does not compile script folders named `Test`, `Tests` or `Dev` (no error, the files are just not
  there): the tests are in `UnitTests/`.
- Warnings fail the whole compile: a `return` after a `switch` that covers every enum value is "Unreachable code"; use
  an if chain. An integer `/` is a warning too: `Math::IntegerDivisionTrunc(a, b)`.
- `int64(<float>)` crashes the game (or gives 0): `int(...)`.
- Time: `Gameplay::GetAccurateRealTime(int&, float&)` (`LPH::NowMs()`); `FDateTime` ticks are 0 and
  `System::GetPlatformTime_Seconds` does not compile.
- No string literals inside `{}` of an f-string. A method cannot be named like a property of its class. A parameter named
  `Name` is not allowed (it shadows `GetName`). Function parameters are const: copy before changing.
- `TArray<T>` of an enum cannot be filled with an initialization list: `Add`. `TArray::Init` does not exist: `SetNum`,
  then a loop. A literal cannot be passed to a `&` parameter.
- `Input::InputEvent_IsRepeat` does not take an `FKeyEvent`.
- Object references in fields need `UPROPERTY()` so that the garbage collector sees them. Script objects are collected
  between frames: free big arrays by hand when making many objects in one call.
- `GetCurrentCulture()` in the main menu is `en-US-POSIX`; use the game's `DisplayLanguage`.
- A `UScriptWorldSubsystem` works in the main menu; `HandleReadyForPlay` of a `UGothicModExt_WorldSubsystem` does not run
  there.
