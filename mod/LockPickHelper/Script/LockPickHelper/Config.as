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
}
