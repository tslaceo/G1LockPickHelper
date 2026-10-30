// The mod's internal numbers, all in milliseconds unless the name or comment says otherwise. They are not settings:
// the player's choices live in Settings.as. The first block is carried over from config.lua of 1.2.0 unchanged.

namespace LPH
{
	const int PollMs = 50; // how often the plates are read while a minigame is open
	const int ReadyDelayMs = 2000; // the game ignores presses right after the minigame opens; no hint before this
	const int ReadyFrames = 30; // and at least this many frames since the start (a loading freeze stops frames, not the clock)
	const int GraceMs = 1200; // how long a move may stay invisible before the game is believed
	const int ToggleNoteMs = 1500; // how long the on/off note stays after the toggle key
	const int SolveWsGapMs = 60; // autosolver: pause after its W/S
	const int SolveTimeoutMs = 2500; // autosolver: stops when its A/D does not show on the plates in this time
	const int SolveMaxReplans = 3; // autosolver: stops after this many hint replans in a row (model and game disagree)
	const int SolveEtaAdMs = 400; // autosolver: the time its text counts for an A/D (measured in game: 370-420 ms)
	const int SolveEtaWsMs = 70; // autosolver: the time its text counts for a W/S (measured in game: 60-70 ms)
	const int SolveEarlyMs = 5000; // autosolver: F3 outside a minigame arms the one that opens within this time (the hero sits down first)
	const int DoubleResetMs = 500; // two resets of the player within this time start the autosolver

	// New in 2.0.
	const int LockWaitMs = 2000; // how long to wait for the lock after the minigame window opens
	const int PrepareBudgetMs = 6; // the solver's work per frame while it prepares a lock
	const int FocusRetryMs = 500; // how often the key catcher takes the focus back (Alt+Tab, gamepad and keyboard switching)
	const int ContextCache = 2; // how many prepared locks (solver tables) stay in memory
	const int LockRetryMs = 100; // how often the lock is looked for until it is found (the search walks the hero's abilities)
	const int IconReadMs = 2000; // how often the game's button icons option and the gamepad's name are read again
	const int HotkeyTwiceMs = 150; // F3/F4 by the key binding and by the key catcher this close together: one press
	const int PadNameWaitMs = 1500; // after a switch to the gamepad, icons that go by its name wait this long for the name (R15)

	const FString ModVersion = "2.0.0"; // also modVersion in GothicMod.json

	// A switch for the in-game checks of 2.0 (Tasks 12 and 14), which want every detail in the log without the tester
	// touching the ini: while this is true the debug lines are always written. False in everything that ships (the
	// release, the Workshop upload; package.ps1 refuses to pack while it is true): then only Debug=True in
	// GameUserSettings.ini or -LPHDebug on the command line turns them on.
	const bool DebugAlways = false;
}
